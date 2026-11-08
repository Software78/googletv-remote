import Foundation

/// Varint length-prefixed framing used by both the polo (6467) and remote (6466) protocols.
public enum VarintFraming {
    public enum FramingError: Error, Equatable, Sendable {
        case varintTooLong
        case frameTooLarge(Int)
    }

    /// Frames larger than this are treated as protocol corruption.
    public static let maxFrameSize = 1 << 20

    public static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    /// Returns `(value, bytesConsumed)`, or nil if more bytes are needed.
    public static func decodeVarint(_ data: Data, at start: Int = 0) throws -> (value: UInt64, length: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var idx = data.startIndex + start
        var consumed = 0
        while idx < data.endIndex {
            let byte = data[idx]
            result |= UInt64(byte & 0x7F) << shift
            consumed += 1
            if byte & 0x80 == 0 { return (result, consumed) }
            shift += 7
            if shift >= 64 { throw FramingError.varintTooLong }
            idx += 1
        }
        return nil
    }

    public static func frame(_ payload: Data) -> Data {
        encodeVarint(UInt64(payload.count)) + payload
    }
}

/// Accumulates stream bytes and yields complete frames. Value type; owner provides isolation.
public struct FrameDecoder: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) { buffer.append(data) }

    /// Returns the next complete frame payload, or nil if incomplete.
    public mutating func nextFrame() throws -> Data? {
        guard let (length, prefix) = try VarintFraming.decodeVarint(buffer) else { return nil }
        guard length <= UInt64(VarintFraming.maxFrameSize) else {
            throw VarintFraming.FramingError.frameTooLarge(Int(clamping: length))
        }
        let total = prefix + Int(length)
        guard buffer.count >= total else { return nil }
        let start = buffer.startIndex + prefix
        let payload = Data(buffer[start..<(buffer.startIndex + total)])
        buffer = Data(buffer.dropFirst(total))
        return payload
    }
}
