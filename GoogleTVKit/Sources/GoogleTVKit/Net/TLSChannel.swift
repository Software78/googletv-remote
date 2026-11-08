import Foundation
import Network
import Security

/// A TLS connection (client cert auth, TV's self-signed cert accepted) that exchanges
/// varint-framed protobuf messages. Owns one NWConnection.
public final class TLSChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "googletvkit.tls")
    private var decoder = FrameDecoder()
    private let lock = NSLock()
    private var serverCertDER: Data?
    private let host: String

    public init(host: String, port: UInt16, identity: SecIdentity) {
        self.host = host
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(sec, sec_identity_create(identity)!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        // The TV presents a self-signed cert: accept it but capture the leaf for pairing.
        let box = CertBox()
        self.box = box
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let t = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(t) as? [SecCertificate], let leaf = chain.first {
                box.set(SecCertificateCopyData(leaf) as Data)
            }
            complete(true)
        }, queue)
        let params = NWParameters(tls: tls, tcp: {
            let tcp = NWProtocolTCP.Options()
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 10
            tcp.noDelay = true
            return tcp
        }())
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
    }
    private let box: CertBox

    public var serverCertificateDER: Data? { box.get() }

    public func open(timeout: TimeInterval = 8) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { [host] state in
                switch state {
                case .ready: if once.fire() { c.resume() }
                case .failed(let e), .waiting(let e):
                    if once.fire() {
                        self.connection.cancel()
                        c.resume(throwing: Self.map(e, host: host))
                    }
                case .cancelled:
                    if once.fire() { c.resume(throwing: TVError.connectionReset) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [host] in
                if once.fire() { self.connection.cancel(); c.resume(throwing: TVError.unreachable(host: host)) }
            }
        }
    }

    public func send(_ payload: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: VarintFraming.frame(payload), completion: .contentProcessed { e in
                if let e { c.resume(throwing: Self.map(e, host: self.host)) } else { c.resume() }
            })
        }
    }

    /// Receives the next complete frame.
    public func receiveFrame() async throws -> Data {
        while true {
            if let f = try lock.withLock({ try decoder.nextFrame() }) { return f }
            let chunk: Data = try await withCheckedThrowingContinuation { c in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, isComplete, error in
                    if let error { c.resume(throwing: Self.map(error, host: self.host)) }
                    else if let data, !data.isEmpty { c.resume(returning: data) }
                    else { c.resume(throwing: TVError.connectionReset) }
                }
            }
            lock.withLock { decoder.append(chunk) }
        }
    }

    public func close() { connection.cancel() }

    static func map(_ e: NWError, host: String) -> TVError {
        switch e {
        case .tls(let status):
            // TV rejected our client certificate (unpaired) shows up as a TLS alert.
            return status == errSSLPeerBadCert || status == errSSLPeerCertRevoked || status == errSSLPeerAccessDenied
                || status == errSSLClosedAbort || status == errSSLPeerHandshakeFail || status == errSSLPeerUnknownCA
                ? .certificateRejected : .connectionReset
        case .posix(let code) where code == .ECONNRESET || code == .EPIPE: return .connectionReset
        default: return .unreachable(host: host)
        }
    }
}

private final class CertBox: @unchecked Sendable {
    private let lock = NSLock(); private var der: Data?
    func set(_ d: Data) { lock.withLock { der = d } }
    func get() -> Data? { lock.withLock { der } }
}
private final class Once: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    func fire() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
