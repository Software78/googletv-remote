import Foundation
import Network

public struct DiscoveredTV: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let endpoint: NWEndpoint
    public let model: String?
    public init(name: String, endpoint: NWEndpoint, model: String?) {
        self.name = name; self.endpoint = endpoint; self.model = model
    }
}

/// Browses `_androidtvremote2._tcp`. Resolution of host/IP is done at connect time via the
/// Bonjour endpoint; `resolveHost` converts it to a numeric IP when needed.
public final class TVBrowser: @unchecked Sendable {
    private var browser: NWBrowser?
    public init() {}

    public func results(onProblem: @escaping @Sendable (TVError?) -> Void = { _ in }) -> AsyncStream<[DiscoveredTV]> {
        AsyncStream { continuation in
            let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
            b.browseResultsChangedHandler = { results, _ in
                let tvs = results.compactMap { r -> DiscoveredTV? in
                    guard case let .service(name, _, _, _) = r.endpoint else { return nil }
                    var model: String?
                    if case let .bonjour(txt) = r.metadata { model = txt["md"] }
                    return DiscoveredTV(name: name, endpoint: r.endpoint, model: model)
                }
                continuation.yield(tvs.sorted { $0.name < $1.name })
            }
            b.stateUpdateHandler = { state in
                switch state {
                case .ready: onProblem(nil)
                case .waiting(let e), .failed(let e):
                    // -65570 = kDNSServiceErr_PolicyDenied: the Local Network permission is off.
                    if case .dns(let code) = e, code == -65570 { onProblem(.localNetworkDenied) }
                    else { onProblem(.unreachable(host: "your network")) }
                default: break
                }
            }
            continuation.onTermination = { _ in b.cancel() }
            b.start(queue: .global())
            self.browser = b
        }
    }

    /// Resolves a Bonjour service to its IPv4 address by opening a throwaway connection.
    public static func resolveHost(_ tv: DiscoveredTV, timeout: TimeInterval = 5) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            let params = NWParameters.tcp
            (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
            let conn = NWConnection(to: tv.endpoint, using: params)
            let gate = Gate(conn, c)
            let finish: @Sendable (Result<String, Error>) -> Void = { gate.finish($0) }
            conn.stateUpdateHandler = { state in
                if case .ready = state, case let .hostPort(host, _)? = conn.currentPath?.remoteEndpoint {
                    var s = "\(host)"
                    if let i = s.firstIndex(of: "%") { s = String(s[..<i]) }
                    finish(.success(s))
                } else if case .failed = state { finish(.failure(TVError.unreachable(host: tv.name))) }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.failure(TVError.unreachable(host: tv.name))) }
        }
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    private let conn: NWConnection; private let c: CheckedContinuation<String, Error>
    init(_ conn: NWConnection, _ c: CheckedContinuation<String, Error>) { self.conn = conn; self.c = c }
    func finish(_ r: Result<String, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }; done = true
        conn.cancel(); c.resume(with: r)
    }
}
