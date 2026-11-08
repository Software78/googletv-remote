import Foundation

public enum TVError: Error, Equatable, Sendable {
    case notPaired
    case certificateRejected
    case wrongCode
    case invalidCodeFormat
    case unreachable(host: String)
    case connectionReset
    case localNetworkDenied
    case protocolViolation(String)
    case keychain(OSStatus)
    case certificateGeneration(String)

    public enum RecoveryAction: Sendable { case pair, retry, checkNetwork, regeneratePairing, openSettings, none }

    public var message: String {
        switch self {
        case .notPaired: "This TV isn't paired with your iPhone yet."
        case .certificateRejected: "The TV no longer trusts this iPhone."
        case .wrongCode: "That code doesn't match. Check the code on your TV and try again."
        case .invalidCodeFormat: "Enter the 6-character code shown on your TV (0–9, A–F)."
        case .unreachable(let host): "Couldn't reach \(host). Make sure the TV is on and on the same Wi‑Fi network."
        case .connectionReset: "The connection to the TV was interrupted."
        case .localNetworkDenied: "Remote needs Local Network access to find your TV. Turn it on in Settings › Privacy & Security › Local Network › Remote."
        case .protocolViolation: "The TV sent an unexpected response."
        case .keychain: "Couldn't access secure storage on this device."
        case .certificateGeneration: "Couldn't create this device's pairing identity."
        }
    }

    public var recovery: RecoveryAction {
        switch self {
        case .notPaired, .certificateRejected: .pair
        case .wrongCode, .invalidCodeFormat: .retry
        case .unreachable: .checkNetwork
        case .connectionReset: .retry
        case .localNetworkDenied: .openSettings
        case .protocolViolation: .retry
        case .keychain, .certificateGeneration: .none
        }
    }

    public var recoveryTitle: String {
        switch recovery {
        case .pair, .regeneratePairing: "Pair Again"
        case .retry: "Try Again"
        case .checkNetwork: "Retry"
        case .openSettings: "Open Settings"
        case .none: "OK"
        }
    }
}

extension TVError: LocalizedError {
    public var errorDescription: String? { message }
}
