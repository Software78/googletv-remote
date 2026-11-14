import Foundation

public struct TVDeviceInfo: Equatable, Sendable {
    public var model: String
    public var vendor: String
    public var appVersion: String
    public init(model: String, vendor: String, appVersion: String) {
        self.model = model; self.vendor = vendor; self.appVersion = appVersion
    }
}

public struct TVVolume: Equatable, Sendable {
    public var level: Int
    public var max: Int
    public var muted: Bool
    public init(level: Int, max: Int, muted: Bool) {
        self.level = level; self.max = max; self.muted = muted
    }
}

public struct TVTextField: Equatable, Sendable {
    public var value: String
    public var label: String
    public init(value: String, label: String) {
        self.value = value; self.label = label
    }
}

public enum TVEvent: Equatable, Sendable {
    case ready(TVDeviceInfo)            // handshake finished; keys will be accepted
    case power(Bool)                    // RemoteStart.started
    case currentApp(String)             // package name
    case volume(TVVolume)
    case textFieldFocused(TVTextField)  // IME showing
    case textFieldDismissed
    case disconnected(TVError?)         // nil = closed locally
}

/// Everything the UI layer needs from a TV connection. Mockable (see MockTVClient).
public protocol TVClient: Sendable {
    /// Opens the connection and completes the handshake. Events then flow on `events`.
    func connect() async throws
    func disconnect() async
    var events: AsyncStream<TVEvent> { get }

    func send(_ key: TVKey, direction: KeyDirection) async throws
    func launch(appLink: String) async throws
    func sendText(_ text: String) async throws
    func sendCharacterKeys(_ text: String) async throws
}

extension TVClient {
    public func send(_ key: TVKey) async throws { try await send(key, direction: .short) }

    /// Long press: START_LONG, hold, END_LONG.
    public func longPress(_ key: TVKey, hold: Duration = .milliseconds(600)) async throws {
        try await send(key, direction: .startLong)
        try await Task.sleep(for: hold)
        try await send(key, direction: .endLong)
    }
}
