import SwiftUI

@main
struct GoogleTVRemoteApp: App {
    @State private var session: TVSession
    @State private var library = AppLibrary()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // `-uiPreview` launches into a frozen connected state, for screenshots and UI tests.
        if CommandLine.arguments.contains("-uiPreview") {
            _session = State(initialValue: TVSession.preview(phase: .connected))
            return
        }
        #endif
        _session = State(initialValue: TVSession())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(library)
                .tint(Theme.accent)
                .task { await session.autoConnect() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await session.reconnectIfNeeded() } }
                }
        }
    }
}
