import SwiftUI
import GoogleTVKit
import Network

struct RootView: View {
    @Environment(TVSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .connected, .reconnecting:
                ThemedScreen { RemoteView() }
            case .awaitingCode, .pairingFinishing:
                PairingCodeView()
            default:
                ConnectView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isLive)
    }
}

struct ConnectView: View {
    @Environment(TVSession.self) private var session
    @State private var showManual = false
    @State private var searchedLong = false

    var body: some View {
        @Bindable var session = session
        ThemedScreen {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 40)
                    Image(systemName: "tv")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 104, height: 104)
                        .neuBackground(Circle())
                        .accessibilityHidden(true)
                    Text("Choose your TV").font(.title.bold())

                    if case .failed(let error) = session.phase {
                        VStack(spacing: 10) {
                            Text(error.message).foregroundStyle(Theme.power).font(.callout).multilineTextAlignment(.center)
                            Button(error.recoveryTitle) { Task { await retry() } }
                                .fontWeight(.semibold).foregroundStyle(Theme.accent)
                                .frame(minWidth: 140, minHeight: 48)
                                .buttonStyle(NeuButtonStyle(shape: Capsule()))
                        }
                    }

                    if session.phase == .connecting || session.phase == .pairingStarting {
                        ProgressView("Connecting…").tint(Theme.accent)
                    } else if session.discovered.isEmpty {
                        VStack(spacing: 12) {
                            if let problem = session.discoveryProblem {
                                Text(problem.message).font(.callout).foregroundStyle(Theme.power)
                                    .multilineTextAlignment(.center)
                                if problem.recovery == .openSettings {
                                    Button(problem.recoveryTitle) {
                                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                    }
                                    .fontWeight(.semibold).foregroundStyle(Theme.accent)
                                    .frame(minWidth: 160, minHeight: 48)
                                    .buttonStyle(NeuButtonStyle(shape: Capsule()))
                                }
                            } else {
                                ProgressView().tint(Theme.accent)
                                Text("Looking for TVs on your Wi‑Fi…").font(.callout).foregroundStyle(Theme.secondaryLabel)
                                if searchedLong {
                                    Text("Still nothing? Make sure the TV is on and on the same Wi‑Fi, then check Settings › Privacy & Security › Local Network › Remote. You can also enter the IP address below.")
                                        .font(.footnote).foregroundStyle(Theme.secondaryLabel).multilineTextAlignment(.center)
                                }
                            }
                        }.padding(.vertical, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(session.discovered) { tv in
                                Button { Task { await session.select(tv) } } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "tv").foregroundStyle(Theme.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tv.name).font(.headline)
                                            if let m = tv.model { Text(m).font(.caption).foregroundStyle(Theme.secondaryLabel) }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryLabel)
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: .infinity, minHeight: 68)
                                }
                                .buttonStyle(NeuButtonStyle(shape: Capsule()))
                                .accessibilityLabel("Connect to \(tv.name)")
                            }
                        }
                    }

                    DisclosureGroup("Enter IP address manually", isExpanded: $showManual) {
                        HStack {
                            TextField("192.168.1.x", text: $session.host)
                                .keyboardType(.decimalPad).autocorrectionDisabled()
                                .padding(12)
                                .neuBackground(Capsule(), pressed: true)
                                .accessibilityLabel("TV IP address")
                            Button(session.isPairedWithCurrentHost ? "Connect" : "Pair") { Task { await retry() } }
                                .fontWeight(.semibold).foregroundStyle(Theme.accent)
                                .frame(minWidth: 84, minHeight: 44)
                                .buttonStyle(NeuButtonStyle(shape: Capsule()))
                                .disabled(session.host.isEmpty)
                        }
                        .padding(.top, 10)
                    }
                    .font(.callout).tint(Theme.accent).foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(24)
            }
        }
        .task {
            session.startDiscovery()
            try? await Task.sleep(for: .seconds(8))
            searchedLong = true
        }
        .onDisappear { session.stopDiscovery() }
    }

    private func retry() async {
        if session.isPairedWithCurrentHost { await session.connect() }
        else if !session.host.isEmpty { await session.startPairing() }
    }
}

struct PairingCodeView: View {
    @Environment(TVSession.self) private var session
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        ThemedScreen {
            VStack(spacing: 22) {
                Spacer()
                Text("Enter the code on your TV").font(.title2.bold()).multilineTextAlignment(.center)
                Text("6 characters, 0–9 and A–F").foregroundStyle(Theme.secondaryLabel)

                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            let chars = Array(code)
                            Text(i < chars.count ? String(chars[i]) : "")
                                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                .frame(width: 46, height: 60)
                                .neuBackground(RoundedRectangle(cornerRadius: 16, style: .continuous), pressed: i == chars.count)
                        }
                    }
                    // Real input lives in an invisible field so the system keyboard, paste and
                    // hex filtering all work.
                    TextField("", text: $code)
                        .focused($focused)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .foregroundStyle(.clear).tint(.clear)
                        .opacity(0.02)
                        .accessibilityLabel("Pairing code")
                        .onChange(of: code) { _, new in
                            let filtered = String(new.uppercased().filter { $0.isHexDigit }.prefix(6))
                            if filtered != new { code = filtered }
                            if filtered.count == 6 { Task { await session.submit(code: filtered) } }
                        }
                }
                .onTapGesture { focused = true }

                if let err = session.lastCodeError, session.phase == .awaitingCode {
                    Text(err.message).foregroundStyle(Theme.power).font(.callout).multilineTextAlignment(.center)
                }
                if session.phase == .pairingFinishing { ProgressView().tint(Theme.accent) }
                Button("Cancel") { session.cancelPairing() }
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(minWidth: 120, minHeight: 48)
                    .buttonStyle(NeuButtonStyle(shape: Capsule()))
                Spacer()
            }
            .padding(24)
        }
        .onAppear { focused = true }
    }
}

#if DEBUG
private let sampleTVs = [
    DiscoveredTV(name: "Living Room TV", endpoint: .service(name: "Living Room TV", type: "_androidtvremote2._tcp", domain: "local.", interface: nil), model: "Chromecast"),
    DiscoveredTV(name: "Bedroom TV", endpoint: .service(name: "Bedroom TV", type: "_androidtvremote2._tcp", domain: "local.", interface: nil), model: nil),
]
#Preview("Connect – searching") {
    ConnectView().environment(TVSession.preview(phase: .idle, host: ""))
}
#Preview("Connect – TVs found") {
    ConnectView().environment(TVSession.preview(phase: .idle, host: "", discovered: sampleTVs))
}
#Preview("Connect – unreachable (light)") {
    ConnectView().environment(TVSession.preview(phase: .failed(.unreachable(host: "192.168.1.50")), discovered: sampleTVs))
        .preferredColorScheme(.light)
}
#Preview("Connect – Local Network denied") {
    ConnectView().environment(TVSession.preview(phase: .idle, host: "", discoveryProblem: .localNetworkDenied))
}
#Preview("Pairing code") {
    PairingCodeView().environment(TVSession.preview(phase: .awaitingCode))
}
#Preview("Pairing code – wrong") {
    PairingCodeView().environment(TVSession.preview(phase: .awaitingCode, codeError: .wrongCode))
}
#endif
