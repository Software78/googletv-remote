import SwiftUI
import GoogleTVKit

struct SettingsView: View {
    @Environment(TVSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Settings").font(.largeTitle.bold())
                    Spacer()
                    Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(Theme.accent)
                }

                card {
                    row("TV", value: session.tvName ?? session.deviceModel ?? "—")
                    divider
                    row("Address", value: session.host)
                    divider
                    row("Model", value: session.deviceModel ?? "—")
                    divider
                    row("Status", value: statusText)
                }

                card {
                    Toggle(isOn: $session.haptics) {
                        Label("Haptic feedback", systemImage: "hand.tap")
                    }
                    .tint(Theme.accent)
                }

                Button { dismiss(); Task { await session.disconnect() } } label: {
                    Label("Switch TV", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(NeuButtonStyle(shape: Capsule()))

                Button(role: .destructive) { dismiss(); Task { await session.forgetCurrentTV() } } label: {
                    Label("Forget this TV", systemImage: "trash")
                        .foregroundStyle(Theme.power)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(NeuButtonStyle(shape: Capsule()))

                Text("Everything stays on your local network. This app has no analytics and makes no internet requests.")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var statusText: String {
        switch session.phase {
        case .connected: session.power == false ? "Standby" : "Connected"
        case .reconnecting(let n): "Reconnecting (\(n))"
        default: "Offline"
        }
    }

    private var divider: some View { Divider().overlay(Theme.secondaryLabel.opacity(0.2)) }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondaryLabel)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .neuBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#if DEBUG
#Preview("Settings") {
    ThemedScreen { SettingsView() }.environment(TVSession.preview(phase: .connected))
}
#endif
