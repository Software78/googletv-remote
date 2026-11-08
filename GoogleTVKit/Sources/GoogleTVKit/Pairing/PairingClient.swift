import Foundation
import SwiftProtobuf

/// Drives the polo pairing handshake on port 6467. Usage:
///   let p = PairingClient(...); try await p.begin(); // TV shows code
///   try await p.finish(code: "AB12CD")
public final class PairingClient: @unchecked Sendable {
    public static let port: UInt16 = 6467
    private let channel: TLSChannel
    private let identity: ClientIdentity
    private let clientName: String

    public init(host: String, store: KeychainIdentityStore, identity: ClientIdentity, clientName: String) throws {
        self.channel = TLSChannel(host: host, port: Self.port, identity: try store.secIdentity())
        self.identity = identity
        self.clientName = clientName
    }
    /// For callers that already have a SecIdentity (e.g. macOS tooling).
    public init(host: String, secIdentity: SecIdentity, identity: ClientIdentity, clientName: String) {
        self.channel = TLSChannel(host: host, port: Self.port, identity: secIdentity)
        self.identity = identity
        self.clientName = clientName
    }

    private func outer() -> Polo_Wire_Protobuf_OuterMessage {
        var m = Polo_Wire_Protobuf_OuterMessage()
        m.protocolVersion = 2
        m.status = .ok
        return m
    }

    private func send(_ m: Polo_Wire_Protobuf_OuterMessage) async throws {
        try await channel.send(try m.serializedData())
    }

    private func receive(_ check: (Polo_Wire_Protobuf_OuterMessage) -> Bool, _ what: String) async throws -> Polo_Wire_Protobuf_OuterMessage {
        let frame = try await channel.receiveFrame()
        let m = try Polo_Wire_Protobuf_OuterMessage(serializedBytes: frame)
        guard m.status == .ok else {
            throw m.status == .badSecret ? TVError.wrongCode : TVError.protocolViolation("status \(m.status) awaiting \(what)")
        }
        guard check(m) else { throw TVError.protocolViolation("expected \(what)") }
        return m
    }

    /// Connects, negotiates options; the TV then displays the code.
    public func begin() async throws {
        try await channel.open()
        var req = outer()
        req.pairingRequest.serviceName = "atvremote"
        req.pairingRequest.clientName = clientName
        try await send(req)
        _ = try await receive({ $0.hasPairingRequestAck }, "pairing request ack")

        var enc = Polo_Wire_Protobuf_Options.Encoding()
        enc.type = .hexadecimal
        enc.symbolLength = 6
        var opts = outer()
        opts.options.inputEncodings = [enc]
        opts.options.preferredRole = .input
        try await send(opts)
        _ = try await receive({ $0.hasOptions }, "options")

        var cfg = outer()
        cfg.configuration.encoding = enc
        cfg.configuration.clientRole = .input
        try await send(cfg)
        _ = try await receive({ $0.hasConfigurationAck }, "configuration ack")
    }

    /// Validates the code locally, sends the secret, and completes pairing.
    public func finish(code: String) async throws {
        guard let serverDER = channel.serverCertificateDER else { throw TVError.protocolViolation("no server certificate") }
        let server = try RSAPublicNumbers(certificateDER: serverDER)
        let secret: Data
        do {
            secret = try PairingSecret.compute(
                clientModulus: identity.publicNumbers.modulus, clientExponent: identity.publicNumbers.exponent,
                serverModulus: server.modulus, serverExponent: server.exponent, code: code)
        } catch PairingSecret.CodeError.invalidFormat { throw TVError.invalidCodeFormat }
        catch PairingSecret.CodeError.checksumMismatch { throw TVError.wrongCode }
        var m = outer()
        m.secret.secret = secret
        try await send(m)
        _ = try await receive({ $0.hasSecretAck }, "secret ack")
        channel.close()
    }

    public func cancel() { channel.close() }
}
