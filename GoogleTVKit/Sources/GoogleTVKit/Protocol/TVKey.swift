import Foundation

/// Remote keys exposed to the UI. Raw values are Android `KEYCODE_*` constants.
public enum TVKey: Int, CaseIterable, Sendable, Codable {
    case home = 3, back = 4
    case num0 = 7, num1 = 8, num2 = 9, num3 = 10, num4 = 11, num5 = 12, num6 = 13, num7 = 14, num8 = 15, num9 = 16
    case comma = 55
    case dpadUp = 19, dpadDown = 20, dpadLeft = 21, dpadRight = 22, dpadCenter = 23
    case volumeUp = 24, volumeDown = 25, power = 26
    case enter = 66, delete = 67, menu = 82, search = 84
    case playPause = 85, rewind = 89, fastForward = 90
    case mute = 164, info = 165, channelUp = 166, channelDown = 167
    case guide = 172, settings = 176, tvPower = 177, tvInput = 178
    case assist = 219

    public var protoKeyCode: Remote_RemoteKeyCode {
        Remote_RemoteKeyCode(rawValue: rawValue) ?? .keycodeUnknown
    }
    public init?(protoKeyCode: Remote_RemoteKeyCode) { self.init(rawValue: protoKeyCode.rawValue) }
}

public enum KeyDirection: Sendable {
    case short, startLong, endLong
    public var proto: Remote_RemoteDirection {
        switch self {
        case .short: .short
        case .startLong: .startLong
        case .endLong: .endLong
        }
    }
}
