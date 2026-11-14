import SwiftUI
import GoogleTVKit

/// Owns the TV connection and publishes UI state. Main-actor isolated so SwiftUI can observe it;
/// all networking happens inside GoogleTVKit.
@MainActor @Observable
final class TVSession {
    enum Phase: Equatable {
        case idle
        case pairingStarting
        case awaitingCode
        case pairingFinishing
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(TVError)
    }

    private(set) var phase: Phase = .idle
    private(set) var power: Bool?
    private(set) var currentApp: String?
    private(set) var volume: TVVolume?
    private(set) var deviceModel: String?
    private(set) var tvName: String?
    private(set) var discovered: [DiscoveredTV] = []
    private(set) var discoveryProblem: TVError?
    private(set) var lastCodeError: TVError?
    private(set) var textFieldActive = false
    private(set) var textFieldLabel: String?

    var haptics: Bool {
        didSet { UserDefaults.standard.set(haptics, forKey: "haptics") }
    }
    var forceKeyEvents: Bool {
        didSet { UserDefaults.standard.set(forceKeyEvents, forKey: "forceKeyEvents") }
    }
    var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "lastHost") }
    }

    private var browser: TVBrowser?
    private var discoveryTask: Task<Void, Never>?
    private let store = KeychainIdentityStore()
    private var pairing: PairingClient?
    private var client: RemoteConnection?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var typingTail: Task<Void, Never>?

    init() {
        host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
        haptics = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true
        forceKeyEvents = UserDefaults.standard.bool(forKey: "forceKeyEvents")
    }

    var isLive: Bool {
        switch phase {
        case .connected, .reconnecting: true
        default: false
        }
    }

    private var pairedHosts: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "pairedHosts") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "pairedHosts") }
    }
    var isPairedWithCurrentHost: Bool { pairedHosts.contains(host) }

    // MARK: Discovery

    func startDiscovery() {
        guard discoveryTask == nil else { return }
        let b = TVBrowser()
        browser = b
        let results = b.results { [weak self] problem in
            Task { @MainActor in self?.discoveryProblem = problem }
        }
        discoveryTask = Task { [weak self] in
            for await tvs in results { self?.discovered = tvs }
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel(); discoveryTask = nil; browser = nil; discoveryProblem = nil
    }

    /// Resolves the chosen TV's IP, then connects (if already paired) or starts pairing.
    func select(_ tv: DiscoveredTV) async {
        phase = .connecting
        tvName = tv.name
        UserDefaults.standard.set(tv.name, forKey: "lastTVName")
        do {
            host = try await TVBrowser.resolveHost(tv)
        } catch {
            phase = .failed(error as? TVError ?? .unreachable(host: tv.name))
            return
        }
        if isPairedWithCurrentHost { await connect() } else { await startPairing() }
    }

    // MARK: Pairing

    func startPairing() async {
        phase = .pairingStarting
        lastCodeError = nil
        do {
            let identity = try store.loadOrCreate()
            let p = try PairingClient(host: host, store: store, identity: identity, clientName: "iPhone Remote")
            pairing = p
            try await p.begin()
            phase = .awaitingCode
        } catch {
            phase = .failed(error as? TVError ?? .connectionReset)
        }
    }

    func submit(code: String) async {
        guard let pairing else { return }
        phase = .pairingFinishing
        do {
            try await pairing.finish(code: code)
            self.pairing = nil
            pairedHosts.insert(host)
            await connect()
        } catch let e as TVError where e == .wrongCode || e == .invalidCodeFormat {
            phase = .awaitingCode          // let the user retry on the same session
            lastCodeError = e
        } catch {
            phase = .failed(error as? TVError ?? .connectionReset)
        }
    }

    func cancelPairing() {
        pairing?.cancel(); pairing = nil; phase = .idle
    }

    // MARK: Connection lifecycle

    func autoConnect() async {
        guard !host.isEmpty, isPairedWithCurrentHost, phase == .idle else { return }
        tvName = UserDefaults.standard.string(forKey: "lastTVName")
        await connect()
    }

    /// Called when the app returns to the foreground.
    func reconnectIfNeeded() async {
        guard !host.isEmpty, isPairedWithCurrentHost else { return }
        switch phase {
        case .connected, .connecting, .reconnecting, .awaitingCode, .pairingStarting, .pairingFinishing: return
        case .failed(let e) where e.recovery == .pair: return
        default: break
        }
        await connect()
    }

    func connect() async {
        reconnectTask?.cancel()
        phase = .connecting
        do {
            try await openConnection()
            phase = .connected
        } catch {
            let e = error as? TVError ?? .connectionReset
            if e == .notPaired { pairedHosts.remove(host) }
            phase = .failed(e)
        }
    }

    private func openConnection() async throws {
        eventTask?.cancel()
        await client?.disconnect()
        let c = try RemoteConnection(host: host, store: store)
        client = c
        let events = c.events
        eventTask = Task { [weak self] in
            for await e in events { self?.apply(e) }
        }
        try await c.connect()
    }

    func disconnect() async {
        reconnectTask?.cancel()
        eventTask?.cancel()
        await client?.disconnect()
        client = nil
        phase = .idle
    }

    /// Forget this TV so it must be paired again.
    func forgetCurrentTV() async {
        await disconnect()
        pairedHosts.remove(host)
        host = ""
        power = nil; currentApp = nil; volume = nil
    }

    /// Exponential backoff: 1, 2, 4, 8, 16, then 30s. Gives up on pairing errors.
    private func beginReconnect() {
        reconnectTask?.cancel()
        phase = .reconnecting(attempt: 1)
        reconnectTask = Task { [weak self] in
            var attempt = 1
            while !Task.isCancelled {
                guard let self else { return }
                let delay = min(30.0, pow(2.0, Double(attempt - 1)))
                self.phase = .reconnecting(attempt: attempt)
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                do {
                    try await self.openConnection()
                    self.phase = .connected
                    return
                } catch {
                    let e = error as? TVError ?? .connectionReset
                    if e.recovery == .pair {
                        self.pairedHosts.remove(self.host)
                        self.phase = .failed(e)
                        return
                    }
                    attempt += 1
                }
            }
        }
    }

    private func apply(_ e: TVEvent) {
        switch e {
        case .ready(let info): deviceModel = info.model
        case .power(let on): power = on
        case .currentApp(let pkg):
            if pkg != currentApp { textFieldActive = false; textFieldLabel = nil }
            currentApp = pkg
        case .volume(let v): volume = v
        case .textFieldFocused(let f):
            textFieldActive = true
            textFieldLabel = f.label.isEmpty ? nil : f.label
        case .textFieldDismissed: textFieldActive = false; textFieldLabel = nil
        case .disconnected(let err):
            guard phase == .connected else { return }
            if let err, err.recovery == .pair { phase = .failed(err) } else { beginReconnect() }
        }
    }

    // MARK: Commands

    func send(_ key: TVKey, direction: KeyDirection = .short) {
        guard let client, phase == .connected else { return }
        Task {
            do { try await client.send(key, direction: direction) }
            catch { beginReconnect() }
        }
    }

    /// Types text on the TV. Uses IME text edits when the TV has shown a text field, otherwise
    /// (or when `forceKeyEvents` is on, e.g. browsers) sends individual key presses.
    func type(_ text: String) {
        guard !text.isEmpty else { return }
        let ime = textFieldActive && !forceKeyEvents
        enqueueTyping { c in
            if ime { try await c.sendText(text) } else { try await c.sendCharacterKeys(text) }
        }
    }

    func backspace(_ count: Int = 1) {
        enqueueTyping { c in for _ in 0..<count { try await c.send(.delete) } }
    }

    /// Typing operations run strictly in order.
    private func enqueueTyping(_ op: @escaping @Sendable (RemoteConnection) async throws -> Void) {
        guard let client, phase == .connected else { return }
        let previous = typingTail
        typingTail = Task { [weak self] in
            await previous?.value
            do { try await op(client) } catch { self?.beginReconnect() }
        }
    }

    func launch(appLink: String) {
        haptic(.medium)
        guard let client, phase == .connected else { return }
        Task { try? await client.launch(appLink: appLink) }
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    #if DEBUG
    /// Builds a session frozen in a given state, for SwiftUI previews and `-uiPreview` launches.
    static func preview(
        phase: Phase,
        host: String = "192.168.1.50",
        power: Bool? = true,
        app: String? = "com.google.android.youtube.tv",
        volume: TVVolume? = TVVolume(level: 12, max: 25, muted: false),
        model: String? = "Chromecast",
        name: String? = "Bedroom TV",
        codeError: TVError? = nil,
        discovered: [DiscoveredTV] = [],
        discoveryProblem: TVError? = nil
    ) -> TVSession {
        let s = TVSession()
        s.phase = phase
        s.host = host
        s.power = power
        s.currentApp = app
        s.volume = volume
        s.deviceModel = model
        s.tvName = name
        s.lastCodeError = codeError
        s.discovered = discovered
        s.discoveryProblem = discoveryProblem
        s.haptics = false
        return s
    }
    #endif
}
