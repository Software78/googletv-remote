import SwiftUI

/// Soft "neumorphic" design tokens. Every color adapts to dark/light; dark is the primary look.
enum Theme {
    static let background = Color(light: 0xEEF0F3, dark: 0x08080A)
    static let surfaceTop = Color(light: 0xFFFFFF, dark: 0x232327)
    static let surfaceBottom = Color(light: 0xF1F2F5, dark: 0x141417)
    static let surfacePressedTop = Color(light: 0xE4E6EA, dark: 0x101012)
    static let surfacePressedBottom = Color(light: 0xF0F1F4, dark: 0x1A1A1D)
    static let highlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF).opacity(0.0)
    static let rimLight = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let shadowDark = Color(light: 0xB9BEC8, dark: 0x000000)
    static let label = Color(light: 0x1B1C20, dark: 0xF2F2F5)
    static let secondaryLabel = Color(light: 0x7A7E88, dark: 0x8D8F98)
    static let accent = Color(light: 0x0A84FF, dark: 0x2D9BFF)
    static let power = Color(light: 0xE5384F, dark: 0xFF5A6E)
    static let online = Color(light: 0x2FC25B, dark: 0x3DDC72)
    static let warning = Color(light: 0xE59A16, dark: 0xFFB43B)

    static let corner: CGFloat = 22
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Raised (or pressed-in) soft surface used behind every control.
struct NeuSurface<S: InsettableShape>: View {
    let shape: S
    var pressed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        shape
            .fill(LinearGradient(
                colors: pressed ? [Theme.surfacePressedTop, Theme.surfacePressedBottom] : [Theme.surfaceTop, Theme.surfaceBottom],
                startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.rimLight.opacity(scheme == .dark ? 0.14 : 0.9), .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            .shadow(color: Theme.shadowDark.opacity(scheme == .dark ? 0.9 : 0.55), radius: pressed ? 2 : 10, x: 0, y: pressed ? 1 : 6)
            .shadow(color: Theme.rimLight.opacity(scheme == .dark ? 0.03 : 0.95), radius: pressed ? 0 : 6, x: 0, y: -2)
    }
}

/// Tap-feedback style shared by simple buttons (no long-press support).
struct NeuButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(NeuSurface(shape: shape, pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(shape)
    }
}

extension View {
    func neuBackground<S: InsettableShape>(_ shape: S, pressed: Bool = false) -> some View {
        background(NeuSurface(shape: shape, pressed: pressed))
    }
}

struct ThemedScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .foregroundStyle(Theme.label)
    }
}
