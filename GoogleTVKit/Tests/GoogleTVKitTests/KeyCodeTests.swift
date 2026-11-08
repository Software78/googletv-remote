import Testing
@testable import GoogleTVKit

@Suite struct KeyCodeTests {
    struct Case: Sendable { let key: TVKey; let code: Int }
    static let cases: [Case] = [
        Case(key: TVKey.home, code: 3), Case(key: TVKey.back, code: 4), Case(key: TVKey.dpadUp, code: 19), Case(key: TVKey.dpadDown, code: 20), Case(key: TVKey.dpadLeft, code: 21),
        Case(key: TVKey.dpadRight, code: 22), Case(key: TVKey.dpadCenter, code: 23), Case(key: TVKey.volumeUp, code: 24), Case(key: TVKey.volumeDown, code: 25), Case(key: TVKey.power, code: 26),
        Case(key: TVKey.enter, code: 66), Case(key: TVKey.delete, code: 67), Case(key: TVKey.playPause, code: 85), Case(key: TVKey.rewind, code: 89), Case(key: TVKey.fastForward, code: 90),
        Case(key: TVKey.mute, code: 164), Case(key: TVKey.channelUp, code: 166), Case(key: TVKey.channelDown, code: 167), Case(key: TVKey.settings, code: 176),
        Case(key: TVKey.tvInput, code: 178), Case(key: TVKey.num0, code: 7), Case(key: TVKey.num9, code: 16), Case(key: TVKey.comma, code: 55), Case(key: TVKey.assist, code: 219),
    ]

    @Test(arguments: cases)
    func androidKeycodeValues(c: Case) {
        let key = c.key, code = c.code
        #expect(key.rawValue == code)
        #expect(key.protoKeyCode.rawValue == code)
        #expect(TVKey(protoKeyCode: key.protoKeyCode) == key)
    }

    @Test func everyKeyMapsToKnownProtoCase() {
        for key in TVKey.allCases {
            #expect(key.protoKeyCode != .keycodeUnknown, "\(key) has no proto case")
        }
    }

    @Test func directions() {
        #expect(KeyDirection.short.proto.rawValue == 3)
        #expect(KeyDirection.startLong.proto.rawValue == 1)
        #expect(KeyDirection.endLong.proto.rawValue == 2)
    }
}
