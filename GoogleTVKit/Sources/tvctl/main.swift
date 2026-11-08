// Developer tool: exercises GoogleTVKit against a real TV from macOS.
//   tvctl pair <ip>      starts pairing, then waits for the code in ~/.tvctl/code
import Foundation
import GoogleTVKit
import Security

let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".tvctl")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func loadIdentity() throws -> ClientIdentity {
    let c = dir.appendingPathComponent("cert.der"), k = dir.appendingPathComponent("key.der")
    if let cd = try? Data(contentsOf: c), let kd = try? Data(contentsOf: k) {
        return try ClientIdentity(certificateDER: cd, privateKeyDER: kd)
    }
    let id = try CertificateFactory.generate()
    try id.certificateDER.write(to: c); try id.privateKeyDER.write(to: k)
    return id
}

func secIdentity(for id: ClientIdentity) throws -> SecIdentity {
    func sh(_ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); p.arguments = args
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw TVError.certificateGeneration("openssl \(args[0]) failed") }
    }
    let f = { (n: String) in dir.appendingPathComponent(n).path }
    try sh(["x509", "-inform", "DER", "-in", f("cert.der"), "-out", f("cert.pem")])
    try sh(["rsa", "-inform", "DER", "-in", f("key.der"), "-out", f("key.pem")])
    try sh(["pkcs12", "-export", "-inkey", f("key.pem"), "-in", f("cert.pem"), "-out", f("id.p12"), "-passout", "pass:tv"])
    var items: CFArray?
    let st = SecPKCS12Import(try Data(contentsOf: dir.appendingPathComponent("id.p12")) as CFData,
                             [kSecImportExportPassphrase as String: "tv"] as CFDictionary, &items)
    guard st == errSecSuccess, let first = (items as? [[String: Any]])?.first,
          let ident = first[kSecImportItemIdentity as String] else { throw TVError.keychain(st) }
    return ident as! SecIdentity
}

func pair(_ host: String) async throws {
    let id = try loadIdentity()
    let client = PairingClient(host: host, secIdentity: try secIdentity(for: id), identity: id, clientName: "tvctl")
    let codeFile = dir.appendingPathComponent("code")
    try? FileManager.default.removeItem(at: codeFile)
    try await client.begin()
    print("WAITING_FOR_CODE: enter the code shown on the TV into \(codeFile.path)")
    var code: String?
    for _ in 0..<240 {
        if let s = try? String(contentsOf: codeFile, encoding: .utf8) {
            code = s.trimmingCharacters(in: .whitespacesAndNewlines); break
        }
        try await Task.sleep(for: .seconds(1))
    }
    guard let code else { print("timed out"); exit(1) }
    try await client.finish(code: code)
    print("PAIRED OK")
}

func connect(_ host: String) async throws -> RemoteConnection {
    let id = try loadIdentity()
    let conn = RemoteConnection(host: host, secIdentity: try secIdentity(for: id))
    Task { for await e in conn.events { print("EVENT:", e) } }
    try await conn.connect()
    return conn
}

let args = CommandLine.arguments
if args.count >= 2, args[1] == "discover" {
    let browser = TVBrowser()
    let task = Task {
        for await tvs in browser.results() {
            for tv in tvs {
                let ip = (try? await TVBrowser.resolveHost(tv)) ?? "unresolved"
                print("FOUND:", tv.name, "model:", tv.model ?? "?", "ip:", ip)
            }
        }
    }
    try await Task.sleep(for: .seconds(6)); task.cancel(); exit(0)
}
guard args.count >= 3 else {
    print("usage: tvctl pair <ip> | key <ip> <KEY>... | watch <ip> <seconds> | long <ip> <KEY> | app <ip> <url>"); exit(2)
}
let host = args[2]
do {
    switch args[1] {
    case "pair": try await pair(host)
    case "key":
        let conn = try await connect(host)
        for name in args.dropFirst(3) {
            guard let key = TVKey.allCases.first(where: { "\($0)".lowercased() == name.lowercased() }) else {
                print("unknown key \(name); keys: \(TVKey.allCases)"); exit(2)
            }
            try await conn.send(key); print("SENT", key)
            try await Task.sleep(for: .milliseconds(400))
        }
        try await Task.sleep(for: .seconds(1))
        await conn.disconnect()
    case "long":
        let conn = try await connect(host)
        guard let key = TVKey.allCases.first(where: { "\($0)".lowercased() == args[3].lowercased() }) else { exit(2) }
        try await conn.longPress(key); print("LONG SENT", key)
        await conn.disconnect()
    case "app":
        let conn = try await connect(host)
        try await conn.launch(appLink: args[3]); print("LAUNCH SENT")
        try await Task.sleep(for: .seconds(2)); await conn.disconnect()
    case "watch":
        _ = try await connect(host)
        try await Task.sleep(for: .seconds(Double(args.count > 3 ? args[3] : "30") ?? 30))
        print("WATCH DONE (connection survived)")
    default: print("unknown command"); exit(2)
    }
} catch let e as TVError {
    print("FAILED: \(e) — \(e.message)"); exit(1)
} catch {
    print("FAILED: \(error)"); exit(1)
}
