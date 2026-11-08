import SwiftUI

struct AppShortcut: Identifiable, Hashable {
    let id: String
    let name: String
    let link: String
    let colorHex: UInt32

    var color: Color {
        Color(red: Double((colorHex >> 16) & 0xFF) / 255, green: Double((colorHex >> 8) & 0xFF) / 255,
              blue: Double(colorHex & 0xFF) / 255)
    }
}

/// App shortcuts launched via RemoteAppLinkLaunchRequest deep links.
@MainActor @Observable
final class AppLibrary {
    let favorites: [AppShortcut] = [
        .init(id: "youtube", name: "YouTube", link: "https://www.youtube.com", colorHex: 0xFF2D2D),
        .init(id: "appletv", name: "Apple TV", link: "https://tv.apple.com", colorHex: 0x8E8E93),
        .init(id: "spotify", name: "Spotify", link: "market://launch?id=com.spotify.tv.android", colorHex: 0x1ED760),
    ]

    /// Friendly name for the Android package currently in the foreground.
    static func displayName(forPackage pkg: String?) -> String? {
        guard let pkg, !pkg.isEmpty else { return nil }
        let known: [String: String] = [
            "com.google.android.youtube.tv": "YouTube",
            "com.netflix.ninja": "Netflix",
            "com.amazon.amazonvideo.livingroom": "Prime Video",
            "com.disney.disneyplus": "Disney+",
            "com.spotify.tv.android": "Spotify",
            "com.google.android.tvlauncher": "Home",
            "com.google.android.apps.tv.launcherx": "Home",
            "com.android.tv.settings": "Settings",
            "com.hulu.livingroomplus": "Hulu",
            "com.wbd.stream": "Max",
            "com.plexapp.android": "Plex",
            "com.apple.atve.androidtv.appletv": "Apple TV",
        ]
        return known[pkg]
    }
}
