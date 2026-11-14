import SwiftUI
import GoogleTVKit

enum RemoteMode: String, CaseIterable, Identifiable {
    case dpad, touchpad, keyboard
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dpad: "dot.circle.and.hand.point.up.left.fill"
        case .touchpad: "hand.point.up.left.fill"
        case .keyboard: "keyboard"
        }
    }
    var label: String {
        switch self { case .dpad: "D-pad"; case .touchpad: "Touchpad"; case .keyboard: "Keyboard" }
    }
}

struct RemoteView: View {
    @State private var mode: RemoteMode = .dpad
    @State private var showSettings = false

    var body: some View {
        // Fits one screen at normal sizes; falls back to scrolling for very large Dynamic Type.
        ViewThatFits(in: .vertical) {
            content(minPad: 280).padding(.horizontal, 18).padding(.vertical, 8)
            ScrollView {
                content(minPad: 300).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .sheet(isPresented: $showSettings) {
            ThemedScreen { SettingsView() }
        }
    }

    private func content(minPad: CGFloat) -> some View {
        VStack(spacing: 16) {
            TopBar(onPillTap: { showSettings = true })
            Group {
                switch mode {
                case .dpad: DPadCluster()
                case .touchpad: TouchpadView()
                case .keyboard: KeyboardView()
                }
            }
            .frame(minHeight: mode == .keyboard ? 0 : minPad, maxHeight: .infinity)
            ModePicker(mode: $mode)
            if mode != .keyboard {
                NavRow()
                VolumeBar()
                ShortcutRow()
            }
        }
    }
}

// MARK: Top bar

private struct TopBar: View {
    @Environment(TVSession.self) private var session
    let onPillTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            KeyButton(key: .power, shape: Circle(), longPress: false) {
                Image(systemName: "power").font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.power)
                    .frame(width: 56, height: 56)
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel("Power")

            Button(action: onPillTap) { StatusPill() }
                .buttonStyle(.plain)
                .accessibilityHint("Opens settings")

            KeyButton(key: .mute, shape: Circle(), longPress: false) {
                Image(systemName: session.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(session.volume?.muted == true ? Theme.accent : Theme.label)
                    .frame(width: 56, height: 56)
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel(session.volume?.muted == true ? "Unmute" : "Mute")
        }
    }
}

private struct StatusPill: View {
    @Environment(TVSession.self) private var session

    private var dotColor: Color {
        if case .reconnecting = session.phase { return Theme.warning }
        return session.power == false ? Theme.secondaryLabel : Theme.online
    }
    private var subtitle: String? {
        if case .reconnecting(let n) = session.phase { return "Reconnecting… (\(n))" }
        if session.power == false { return "Standby" }
        return AppLibrary.displayName(forPackage: session.currentApp)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
                .shadow(color: dotColor.opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.tvName ?? session.deviceModel ?? "TV")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Theme.secondaryLabel).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .neuBackground(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.tvName ?? "TV"), \(session.power == false ? "standby" : "on")")
        .accessibilityValue(subtitle ?? "")
    }
}

// MARK: D-pad

private struct DPadCluster: View {
    var body: some View {
        GeometryReader { geo in
            Ring(diameter: min(geo.size.width * 0.8, 300, geo.size.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Ring: View {
    let diameter: CGFloat
    var body: some View {
        let inner = diameter * 0.42
        ZStack {
            Circle().fill(Color.clear).neuBackground(Circle())
            Group {
                arrow("chevron.up", "Up", .dpadUp).offset(y: -diameter * 0.35)
                arrow("chevron.down", "Down", .dpadDown).offset(y: diameter * 0.35)
                arrow("chevron.left", "Left", .dpadLeft).offset(x: -diameter * 0.35)
                arrow("chevron.right", "Right", .dpadRight).offset(x: diameter * 0.35)
            }
            KeyButton(key: .dpadCenter, shape: Circle()) {
                Text("OK").font(.title2.weight(.semibold)).frame(width: inner, height: inner)
            }
            .frame(width: inner, height: inner)
            .accessibilityLabel("Select")
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ symbol: String, _ label: String, _ key: TVKey) -> some View {
        KeyButton(key: key, shape: Circle(), raised: false, repeatsWhenHeld: true) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Theme.secondaryLabel)
                .frame(width: diameter * 0.26, height: diameter * 0.26)
        }
        .frame(width: diameter * 0.26, height: diameter * 0.26)
        .accessibilityLabel(label)
    }
}

// MARK: Touchpad

private struct TouchpadView: View {
    @Environment(TVSession.self) private var session
    @State private var lastTranslation: CGSize = .zero
    @State private var accum: CGSize = .zero
    @State private var moved = false
    @State private var longTask: Task<Void, Never>?
    @State private var didLong = false
    @State private var active = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            Canvas { ctx, size in
                let gap: CGFloat = 28
                var y: CGFloat = gap / 2
                while y < size.height {
                    var x: CGFloat = gap / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
                                 with: .color(Theme.secondaryLabel.opacity(0.35)))
                        x += gap
                    }
                    y += gap
                }
            }
            .clipShape(shape)
            Text("Swipe to move · Tap to select · Hold for long press")
                .font(.caption).foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
                .opacity(active ? 0 : 1)
        }
        .neuBackground(shape, pressed: active)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(onChanged)
                .onEnded(onEnded)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Touchpad")
        .accessibilityHint("Swipe to move focus, double tap to select")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction { session.send(.dpadCenter) }
    }

    private func onChanged(_ v: DragGesture.Value) {
        if !active {
            active = true; moved = false; didLong = false
            lastTranslation = .zero; accum = .zero
            longTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, !moved else { return }
                didLong = true
                session.haptic(.medium)
                session.send(.dpadCenter, direction: .startLong)
            }
        }
        let dx = v.translation.width - lastTranslation.width
        let dy = v.translation.height - lastTranslation.height
        lastTranslation = v.translation
        if hypot(v.translation.width, v.translation.height) > 10 { moved = true; longTask?.cancel() }
        guard moved, !didLong else { return }
        accum.width += dx; accum.height += dy

        // Faster swipes → smaller step → more key presses per point of travel.
        let speed = hypot(v.velocity.width, v.velocity.height)
        let step = max(14, 44 - speed / 45)
        if abs(accum.width) >= abs(accum.height) {
            while abs(accum.width) >= step {
                emit(accum.width > 0 ? .dpadRight : .dpadLeft)
                accum.width -= step * (accum.width > 0 ? 1 : -1)
                accum.height = 0
            }
        } else {
            while abs(accum.height) >= step {
                emit(accum.height > 0 ? .dpadDown : .dpadUp)
                accum.height -= step * (accum.height > 0 ? 1 : -1)
                accum.width = 0
            }
        }
    }

    private func onEnded(_ v: DragGesture.Value) {
        longTask?.cancel()
        active = false
        if didLong { session.send(.dpadCenter, direction: .endLong) }
        else if !moved { session.haptic(); session.send(.dpadCenter) }
        didLong = false
    }

    private func emit(_ key: TVKey) {
        session.haptic(.soft)
        session.send(key)
    }
}

// MARK: Keyboard

/// Types on the TV. The field is a scratch buffer: each edit is diffed against the previous
/// value and sent as inserted text or Backspace presses; Return sends Enter.
private struct KeyboardView: View {
    @Environment(TVSession.self) private var session
    @State private var text = ""
    @State private var previous = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 14) {
            Text(session.textFieldLabel ?? (session.textFieldActive ? "Text field on TV" : "Select a text field on the TV"))
                .font(.caption).foregroundStyle(Theme.secondaryLabel).lineLimit(1)
            TextField("Type here", text: $text)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { session.haptic(); session.send(.enter); focused = true }
                .padding(.horizontal, 18).frame(height: 56)
                .neuBackground(Capsule(), pressed: true)
                .accessibilityLabel("Type on TV")
            HStack(spacing: 12) {
                action("delete.left", "Backspace", .delete, repeats: true)
                action("return", "Enter", .enter, repeats: false)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuBackground(shape)
        .onAppear { focused = true }
        .onChange(of: text) { _, new in
            sync(from: previous, to: new)
            previous = new
        }
        .onChange(of: session.textFieldActive) { _, active in
            if !active { text = ""; previous = "" }
        }
    }

    private func action(_ symbol: String, _ label: String, _ key: TVKey, repeats: Bool) -> some View {
        KeyButton(key: key, shape: Capsule(), longPress: false) {
            Image(systemName: symbol).font(.title3).frame(maxWidth: .infinity, minHeight: 52)
        }
        .accessibilityLabel(label)
    }

    private func sync(from old: String, to new: String) {
        let o = Array(old), n = Array(new)
        var i = 0
        while i < o.count, i < n.count, o[i] == n[i] { i += 1 }
        for _ in i..<o.count { session.send(.delete) }
        if i < n.count { session.sendText(String(n[i...])) }
    }
}

// MARK: Mode picker

private struct ModePicker: View {
    @Binding var mode: RemoteMode
    @Environment(TVSession.self) private var session

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RemoteMode.allCases) { m in
                Button {
                    session.haptic(.soft)
                    mode = m
                } label: {
                    Image(systemName: m.symbol)
                        .font(.body)
                        .foregroundStyle(mode == m ? Theme.accent : Theme.secondaryLabel)
                        .frame(width: 56, height: 40)
                        .background {
                            if mode == m { NeuSurface(shape: Capsule(), pressed: true) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.label)
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(4)
        .neuBackground(Capsule())
    }
}

// MARK: Navigation + volume

private struct NavRow: View {
    var body: some View {
        HStack(spacing: 12) {
            key(.back, "arrow.uturn.backward", "Back", long: false)
            key(.home, "house.fill", "Home", long: true)
            key(.playPause, "playpause.fill", "Play or pause", long: false)
        }
    }

    private func key(_ key: TVKey, _ symbol: String, _ label: String, long: Bool) -> some View {
        KeyButton(key: key, shape: Capsule(), longPress: long) {
            Image(systemName: symbol).font(.title3)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .accessibilityLabel(label)
    }
}

/// Horizontal volume rocker: minus, level, plus. Hold either side to repeat.
private struct VolumeBar: View {
    @Environment(TVSession.self) private var session

    var body: some View {
        HStack(spacing: 0) {
            half(.volumeDown, "minus", "Volume down")
            VStack(spacing: 0) {
                Text("VOL").font(.caption2.weight(.medium)).foregroundStyle(Theme.secondaryLabel)
                Text(session.volume.map { "\($0.level)" } ?? "–")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue(session.volume.map { "\($0.level) of \($0.max)" } ?? "unknown")
            half(.volumeUp, "plus", "Volume up")
        }
        .frame(height: 60)
        .neuBackground(Capsule())
    }

    private func half(_ key: TVKey, _ symbol: String, _ label: String) -> some View {
        KeyButton(key: key, shape: Capsule(), raised: false, repeatsWhenHeld: true) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(label)
    }
}

// MARK: Shortcut row

private struct ShortcutRow: View {
    @Environment(TVSession.self) private var session
    @Environment(AppLibrary.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            ForEach(library.favorites) { app in
                Button { session.launch(appLink: app.link) } label: {
                    Text(app.name)
                        .font(.system(.subheadline, weight: .heavy))
                        .foregroundStyle(app.color)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(NeuButtonStyle(shape: Capsule()))
                .accessibilityLabel("Open \(app.name)")
            }
        }
    }
}

#if DEBUG
#Preview("Remote – dark") {
    ThemedScreen { RemoteView() }
        .environment(TVSession.preview(phase: .connected))
        .environment(AppLibrary())
        .preferredColorScheme(.dark)
}
#Preview("Remote – light") {
    ThemedScreen { RemoteView() }
        .environment(TVSession.preview(phase: .connected))
        .environment(AppLibrary())
        .preferredColorScheme(.light)
}
#Preview("Remote – reconnecting") {
    ThemedScreen { RemoteView() }
        .environment(TVSession.preview(phase: .reconnecting(attempt: 3)))
        .environment(AppLibrary())
        .preferredColorScheme(.dark)
}
#Preview("Remote – large text") {
    ThemedScreen { RemoteView() }
        .environment(TVSession.preview(phase: .connected))
        .environment(AppLibrary())
        .dynamicTypeSize(.accessibility3)
}
#endif
