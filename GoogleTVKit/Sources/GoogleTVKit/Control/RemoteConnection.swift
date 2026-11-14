import Foundation
import Security

/// Android TV Remote v2 control connection on port 6466.
public final class RemoteConnection: TVClient, @unchecked Sendable {
    public static let port: UInt16 = 6466

    /// PING | KEY | IME | POWER | VOLUME | APP_LINK, as in androidtvremote2.
    static let ourFeatures: Int32 = 1 | 2 | 4 | 32 | 64 | 512

    private let channel: TLSChannel
    private let stream: AsyncStream<TVEvent>
    private let continuation: AsyncStream<TVEvent>.Continuation
    private let lock = NSLock()
    private var imeCounter: Int32 = 0
    private var fieldCounter: Int32 = 0
    private var activeFeatures: Int32 = RemoteConnection.ourFeatures
    private var deviceInfo = TVDeviceInfo(model: "", vendor: "", appVersion: "")
    private var readerTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var closed = false

    public var events: AsyncStream<TVEvent> { stream }

    public init(host: String, secIdentity: SecIdentity) {
        channel = TLSChannel(host: host, port: Self.port, identity: secIdentity)
        (stream, continuation) = AsyncStream.makeStream(of: TVEvent.self, bufferingPolicy: .bufferingNewest(64))
    }

    public convenience init(host: String, store: KeychainIdentityStore) throws {
        self.init(host: host, secIdentity: try store.secIdentity())
    }

    // MARK: TVClient

    public func connect() async throws {
        try await channel.open()
        // Start reading, then wait until the TV sends RemoteStart (handshake complete).
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.withLock { readyContinuation = c }
            readerTask = Task.detached { [self] in await readLoop() }
            Task.detached { [self] in
                try? await Task.sleep(for: .seconds(10))
                resolveReady(.failure(TVError.notPaired))   // TLS up but no handshake: not paired
            }
        }
    }

    public func disconnect() async {
        lock.withLock { closed = true }
        readerTask?.cancel()
        channel.close()
        continuation.yield(.disconnected(nil))
        continuation.finish()
    }

    public func send(_ key: TVKey, direction: KeyDirection) async throws {
        var m = Remote_RemoteMessage()
        m.remoteKeyInject.keyCode = key.protoKeyCode
        m.remoteKeyInject.direction = direction.proto
        try await write(m)
    }

    public func launch(appLink: String) async throws {
        var m = Remote_RemoteMessage()
        m.remoteAppLinkLaunchRequest.appLink = appLink
        try await write(m)
    }

    public func sendText(_ text: String) async throws {
        guard !text.isEmpty else { return }
        let (ime, field) = lock.withLock { (imeCounter, fieldCounter) }
        var m = Remote_RemoteMessage()
        let pos = Int32(text.utf16.count - 1)
        var obj = Remote_RemoteImeObject()
        obj.start = pos; obj.end = pos; obj.value = text
        var edit = Remote_RemoteEditInfo()
        edit.insert = 1
        edit.textFieldStatus = obj
        m.remoteImeBatchEdit.imeCounter = ime
        m.remoteImeBatchEdit.fieldCounter = field
        m.remoteImeBatchEdit.editInfo = [edit]
        try await write(m)
    }

    /// Types by sending individual key events. Works in apps (e.g. browsers) that ignore IME text edits.
    public func sendCharacterKeys(_ text: String) async throws {
        for ch in text {
            guard let (code, shift) = Self.keyCode(for: ch), let key = Remote_RemoteKeyCode(rawValue: code) else { continue }
            if shift { try await sendRaw(.keycodeShiftLeft, .startLong) }
            try await sendRaw(key, .short)
            if shift { try await sendRaw(.keycodeShiftLeft, .endLong) }
        }
    }

    private func sendRaw(_ key: Remote_RemoteKeyCode, _ dir: KeyDirection) async throws {
        var m = Remote_RemoteMessage()
        m.remoteKeyInject.keyCode = key
        m.remoteKeyInject.direction = dir.proto
        try await write(m)
    }

    /// Android KEYCODE for a character, and whether Shift is needed. nil = no key for it.
    static func keyCode(for ch: Character) -> (Int, Bool)? {
        guard let a = ch.asciiValue else { return nil }
        switch a {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return (29 + Int(a - UInt8(ascii: "a")), false)
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return (29 + Int(a - UInt8(ascii: "A")), true)
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return (7 + Int(a - UInt8(ascii: "0")), false)
        default: break
        }
        switch ch {
        case " ": return (62, false)
        case ".": return (56, false)
        case ",": return (55, false)
        case "-": return (69, false)
        case "=": return (70, false)
        case "/": return (76, false)
        case "@": return (77, false)
        case ";": return (74, false)
        case "'": return (75, false)
        case "\\": return (73, false)
        case "[": return (71, false)
        case "]": return (72, false)
        case "+": return (81, false)
        case "*": return (17, false)
        case "#": return (18, false)
        case "\n": return (66, false)
        default: return nil
        }
    }

    // MARK: Internals

    private func write(_ m: Remote_RemoteMessage) async throws {
        try await channel.send(try m.serializedData())
    }

    private func resolveReady(_ r: Result<Void, Error>) {
        let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { readyContinuation = nil }
            return readyContinuation
        }
        c?.resume(with: r)
    }

    private func readLoop() async {
        do {
            while !Task.isCancelled {
                let frame = try await channel.receiveFrame()
                guard let msg = try? Remote_RemoteMessage(serializedBytes: frame) else { continue }
                try await handle(msg)
            }
        } catch {
            let wasClosed = lock.withLock { closed }
            let err: TVError = (error as? TVError) ?? .connectionReset
            resolveReady(.failure(err == .connectionReset ? TVError.notPaired : err))
            if !wasClosed {
                continuation.yield(.disconnected(err))
                continuation.finish()
            }
        }
    }

    private func handle(_ msg: Remote_RemoteMessage) async throws {
        var reply = Remote_RemoteMessage()
        var needsReply = false

        if msg.hasRemoteConfigure {
            let cfg = msg.remoteConfigure
            deviceInfo = TVDeviceInfo(model: cfg.deviceInfo.model, vendor: cfg.deviceInfo.vendor,
                                      appVersion: cfg.deviceInfo.appVersion)
            let active = lock.withLock { () -> Int32 in
                activeFeatures &= cfg.code1
                return activeFeatures
            }
            reply.remoteConfigure.code1 = active
            reply.remoteConfigure.deviceInfo.unknown1 = 1
            reply.remoteConfigure.deviceInfo.unknown2 = "1"
            reply.remoteConfigure.deviceInfo.packageName = "atvremote"
            reply.remoteConfigure.deviceInfo.appVersion = "1.0.0"
            needsReply = true
        } else if msg.hasRemoteSetActive {
            reply.remoteSetActive.active = lock.withLock { activeFeatures }
            needsReply = true
        } else if msg.hasRemotePingRequest {
            // Must always answer, or the TV drops the connection.
            reply.remotePingResponse.val1 = msg.remotePingRequest.val1
            needsReply = true
        } else if msg.hasRemoteStart {
            continuation.yield(.power(msg.remoteStart.started))
            resolveReady(.success(()))
            continuation.yield(.ready(deviceInfo))
        } else if msg.hasRemoteImeKeyInject {
            let ime = msg.remoteImeKeyInject
            if ime.hasAppInfo { continuation.yield(.currentApp(ime.appInfo.appPackage)) }
        } else if msg.hasRemoteImeBatchEdit {
            let b = msg.remoteImeBatchEdit
            lock.withLock { imeCounter = b.imeCounter; fieldCounter = b.fieldCounter }
        } else if msg.hasRemoteImeShowRequest {
            let s = msg.remoteImeShowRequest.remoteTextFieldStatus
            continuation.yield(.textFieldFocused(TVTextField(value: s.value, label: s.label)))
        } else if msg.hasRemoteSetVolumeLevel {
            let v = msg.remoteSetVolumeLevel
            continuation.yield(.volume(TVVolume(level: Int(v.volumeLevel), max: Int(v.volumeMax), muted: v.volumeMuted)))
        } else if msg.hasRemoteError {
            continuation.yield(.disconnected(.protocolViolation("TV reported an error")))
        }
        if needsReply { try await write(reply) }
    }
}
