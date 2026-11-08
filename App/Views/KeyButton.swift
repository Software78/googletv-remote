import SwiftUI
import GoogleTVKit

/// A remote key. Tap sends SHORT; holding sends START_LONG then END_LONG on release.
/// With `repeatsWhenHeld`, holding instead re-sends SHORT every 140ms (volume, channel).
struct KeyButton<Content: View, S: InsettableShape>: View {
    @Environment(TVSession.self) private var session
    let key: TVKey
    let shape: S
    var raised = true                 // false: draws no surface (used inside the d-pad ring)
    var repeatsWhenHeld = false
    var longPress = true
    @ViewBuilder var content: Content

    @State private var pressed = false
    @State private var holdTask: Task<Void, Never>?
    @State private var didHold = false

    var body: some View {
        content
            .background {
                if raised { NeuSurface(shape: shape, pressed: pressed) }
                else if pressed { shape.fill(Theme.label.opacity(0.08)) }
            }
            .scaleEffect(pressed && raised ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { value in end(cancelled: hypot(value.translation.width, value.translation.height) > 48) }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.send(key) }
    }

    private func begin() {
        guard !pressed else { return }
        pressed = true
        didHold = false
        session.haptic()
        guard longPress || repeatsWhenHeld else { return }
        holdTask = Task {
            try? await Task.sleep(for: .milliseconds(repeatsWhenHeld ? 350 : 450))
            guard !Task.isCancelled else { return }
            didHold = true
            if repeatsWhenHeld {
                while !Task.isCancelled {
                    session.send(key)
                    try? await Task.sleep(for: .milliseconds(140))
                }
            } else {
                session.haptic(.medium)
                session.send(key, direction: .startLong)
            }
        }
    }

    private func end(cancelled: Bool) {
        pressed = false
        holdTask?.cancel(); holdTask = nil
        if didHold {
            if !repeatsWhenHeld { session.send(key, direction: .endLong) }
        } else if !cancelled {
            session.send(key)
        }
        didHold = false
    }
}
