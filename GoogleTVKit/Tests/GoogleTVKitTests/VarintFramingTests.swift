import Testing
import Foundation
@testable import GoogleTVKit

@Suite struct VarintFramingTests {
    struct Case: Sendable { let value: UInt64; let bytes: [UInt8] }
    static let cases: [Case] = [
        Case(value: 0, bytes: [0x00]),
        Case(value: 1, bytes: [0x01]),
        Case(value: 127, bytes: [0x7F]),
        Case(value: 128, bytes: [0x80, 0x01]),
        Case(value: 300, bytes: [0xAC, 0x02]),
        Case(value: 16384, bytes: [0x80, 0x80, 0x01]),
    ]

    @Test(arguments: cases)
    func encodesKnownValues(c: Case) throws {
        let value = c.value, bytes = c.bytes
        #expect([UInt8](VarintFraming.encodeVarint(value)) == bytes)
        let decoded = try #require(try VarintFraming.decodeVarint(Data(bytes)))
        #expect(decoded.value == value && decoded.length == bytes.count)
    }

    @Test func incompleteVarintReturnsNil() throws {
        #expect(try VarintFraming.decodeVarint(Data([0x80])) == nil)
    }

    @Test func overlongVarintThrows() {
        #expect(throws: VarintFraming.FramingError.varintTooLong) {
            _ = try VarintFraming.decodeVarint(Data(repeating: 0xFF, count: 11))
        }
    }

    @Test func decoderHandlesSplitAndCoalescedFrames() throws {
        let a = Data(repeating: 0xAA, count: 200)   // 2-byte prefix
        let b = Data([1, 2, 3])
        let stream = VarintFraming.frame(a) + VarintFraming.frame(b)
        var decoder = FrameDecoder()
        var frames: [Data] = []
        for byte in stream {                         // worst case: 1 byte at a time
            decoder.append(Data([byte]))
            while let f = try decoder.nextFrame() { frames.append(f) }
        }
        #expect(frames == [a, b])

        var all = FrameDecoder()
        all.append(stream)
        #expect(try all.nextFrame() == a)
        #expect(try all.nextFrame() == b)
        #expect(try all.nextFrame() == nil)
    }

    @Test func oversizedFrameRejected() {
        var d = FrameDecoder()
        d.append(VarintFraming.encodeVarint(UInt64(VarintFraming.maxFrameSize) + 1))
        #expect(throws: VarintFraming.FramingError.self) { _ = try d.nextFrame() }
    }
}
