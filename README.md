# Remote for Google TV

A native iOS remote for Google TV and Android TV, written in SwiftUI. It talks to the TV directly over your local network using the **Android TV Remote Service protocol v2**, the same protocol the official Google TV app uses. There is no cloud, no account, no analytics, and no network traffic other than to your TV.

> **Status: work in progress.** Pairing, control, discovery and the main remote screen work against a real Chromecast with Google TV. See [Status](#status) for what is and isn't done.

## What it does

- **Finds your TV automatically** with Bonjour (`_androidtvremote2._tcp`), or connect by IP address.
- **Pairs once** with the 6-character code shown on the TV, then reconnects on its own.
- **Remote screen:** power, mute, d-pad with OK, Back, Home, play/pause, and volume with hold-to-repeat.
- **Touchpad mode:** swipe to move (faster swipes move faster), tap to select, hold for a long press.
- **Long press** on keys sends `START_LONG` then `END_LONG`.
- **Live state:** the status pill shows the TV's power state and the app in the foreground, and the volume level follows the TV.
- **Auto-reconnect** with exponential backoff, and a reconnect when the app returns to the foreground.
- **App shortcuts** for YouTube, Apple TV and Spotify via deep links.
- **Dark and light**, soft neumorphic styling, VoiceOver labels, Dynamic Type, and haptics you can turn off.

## Requirements

- iOS 17 or later
- Xcode with Swift 6 (built with Xcode 27)
- A Google TV or Android TV on the same Wi-Fi network as your phone

## Run it

1. Open `GoogleTVRemote.xcodeproj`.
2. Select the `GoogleTVRemote` target, then **Signing & Capabilities**, and choose your development team. Signing is also what gives the app Keychain access.
3. Run on a device or simulator.
4. Tap **Allow** on the "find devices on your local network" prompt.
5. Pick your TV, then enter the code the TV shows.

Swift Package dependencies (SwiftProtobuf, swift-certificates, swift-crypto, swift-asn1) resolve automatically.

### If your TV doesn't show up

- Make sure the TV is on and on the same Wi-Fi as your phone.
- Check **Settings › Privacy & Security › Local Network › Remote** is on. iOS only lists the app there after it has asked once. If you've declined, delete and reinstall the app.
- Use **Enter IP address manually** on the Connect screen.

## How it works

```
iPhone                                        Google TV
  │  Bonjour: _androidtvremote2._tcp            │
  │────────────────────────────────────────────▶│  discover
  │  TLS :6467 (client cert) ── polo pairing ──▶│  shows 6-char code
  │  secret = SHA-256(client key, server key,   │
  │            code[2:])  (first byte == code[0])│
  │  TLS :6466 (same cert) ── remote messages ─▶│  keys, apps, state
```

- **Identity:** on first launch the app generates a self-signed RSA-2048 certificate and stores it in the Keychain. The TV pairs to that certificate, so it is reused permanently.
- **Pairing (port 6467):** the polo protobuf exchange (`PairingRequest` → `Options` → `Configuration` → `Secret`), with the secret computed from both public keys and the code. The app checks the code's first byte locally before sending, so a typo is caught without a round trip.
- **Control (port 6466):** the `RemoteConfigure` / `RemoteSetActive` handshake, then key injection. The app always answers `RemotePingRequest`, or the TV drops the connection.
- The TV's certificate is self-signed, so the app accepts it and captures its public key for the pairing secret.

The protocol logic is a Swift port of [`androidtvremote2`](https://github.com/tronikos/androidtvremote2), the library used by Home Assistant.

## Project layout

```
GoogleTVKit/         Swift package: all networking, no UI dependencies
  Sources/GoogleTVKit/
    Protocol/        varint framing, key codes, pairing secret, generated protobufs
    Identity/        certificate generation, Keychain storage
    Net/             TLS channel (Network.framework)
    Pairing/         pairing client
    Control/         remote connection and the TVClient protocol
    Discovery/       Bonjour browser
    Errors/          typed errors with messages and recovery actions
  Sources/tvctl/     macOS command-line tool for testing against a real TV
  Tests/             unit tests
App/                 SwiftUI app (MVVM, an @Observable TVSession)
AppTests/            tests that run inside the app host (Keychain)
Protos/              polo.proto, remotemessage.proto, generate.sh
```

To regenerate the protobuf Swift types, build `protoc-gen-swift` from [swift-protobuf](https://github.com/apple/swift-protobuf) and run:

```sh
PROTOC_GEN_SWIFT=/path/to/protoc-gen-swift Protos/generate.sh
```

## Tests

```sh
# Library: framing, protobuf round-trips, pairing secret, key codes, certificates
cd GoogleTVKit && swift test
```

The Keychain round trip needs the app's entitlements, so it runs from the app target instead (use an ad-hoc signed simulator build):

```sh
xcodebuild test -project GoogleTVRemote.xcodeproj -scheme GoogleTVRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES
```

The pairing-secret test vector was produced by running the reference implementation's hash expressions on fixed inputs. Pairing against a real TV is the real end-to-end check.

## `tvctl`

A small macOS tool built on the same library, for trying things against a real TV without the app:

```sh
cd GoogleTVKit && swift build --product tvctl
.build/debug/tvctl discover
.build/debug/tvctl pair  <ip>          # then write the code shown on the TV to ~/.tvctl/code
.build/debug/tvctl key   <ip> volumeUp volumeDown
.build/debug/tvctl long  <ip> dpadCenter
.build/debug/tvctl app   <ip> "https://www.youtube.com"
.build/debug/tvctl watch <ip> 30       # print TV events
```

It keeps its own pairing identity in `~/.tvctl/`. Don't share or commit that folder.

## Status

**Working, tested against a real Chromecast with Google TV:** pairing, the control handshake and pings, key injection, volume/power/current-app feedback, and Bonjour discovery.

**Built but not fully verified on hardware:** the touchpad gestures, long-press, app shortcuts (some deep links may open the browser instead of the app), and reconnect behavior.

**Not built yet:** saved list of multiple TVs, widgets, Siri Shortcuts and App Intents, a Control Center control, an Apple Watch app, an on-screen keyboard, and a `MockTVServer` for previews and UI tests. The library can already send text, but the app doesn't expose it.

## Privacy

- No analytics, no tracking, no third-party SDKs.
- The only network traffic is between your phone and your TV on your local network.
- Your pairing key stays in the iOS Keychain on your device.

## Credits and licenses

- Protocol behavior is ported from [`androidtvremote2`](https://github.com/tronikos/androidtvremote2) by tronikos.
- `Protos/polo.proto` comes from Google's [google-tv-pairing-protocol](https://android.googlesource.com/platform/external/google-tv-pairing-protocol/) (Apache 2.0). `Protos/remotemessage.proto` comes from `androidtvremote2`. Both keep their original header comments.
- This is an independent project and is not affiliated with or endorsed by Google. Google TV, Android TV, YouTube, Apple TV and Spotify are trademarks of their respective owners.
- This repository does not have a license yet, so all rights are reserved until one is added.
