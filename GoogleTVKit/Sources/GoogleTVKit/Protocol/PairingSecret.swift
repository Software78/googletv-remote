import Foundation
import Crypto

/// Port of the secret computation in androidtvremote2 `pairing.py`.
public enum PairingSecret {
    public enum CodeError: Error, Equatable, Sendable {
        case invalidFormat      // not exactly 6 hex chars
        case checksumMismatch   // first byte of hash != first byte of code (wrong code)
    }

    /// Validates "AABBCC" style input and returns the 3 decoded bytes.
    public static func decodeCode(_ code: String) throws -> [UInt8] {
        guard code.count == 6, let data = Data(hexString: code) else { throw CodeError.invalidFormat }
        return [UInt8](data)
    }

    /// - Parameters: moduli are big-endian unsigned (leading zeros are stripped, matching
    ///   Python's `bytes.fromhex(f"{n:X}")`); exponents likewise but the reference prefixes a
    ///   literal "0" nibble, so 65537 hashes as 01 00 01.
    public static func compute(
        clientModulus: Data, clientExponent: Data,
        serverModulus: Data, serverExponent: Data,
        code: String
    ) throws -> Data {
        let codeBytes = try decodeCode(code)
        var hasher = SHA256()
        hasher.update(data: strip(clientModulus))
        hasher.update(data: exponentBytes(clientExponent))
        hasher.update(data: strip(serverModulus))
        hasher.update(data: exponentBytes(serverExponent))
        hasher.update(data: Data(codeBytes[1...]))
        let digest = Data(hasher.finalize())
        guard digest[0] == codeBytes[0] else { throw CodeError.checksumMismatch }
        return digest
    }

    static func strip(_ d: Data) -> Data { Data(d.drop(while: { $0 == 0 })) }

    /// Python: bytes.fromhex(f"0{e:X}") — pad with one "0" nibble, and if that leaves an odd
    /// number of nibbles the reference would throw; we left-pad to even length instead.
    static func exponentBytes(_ d: Data) -> Data {
        let hex = strip(d).map { String(format: "%02X", $0) }.joined()
        let trimmed = String(hex.drop(while: { $0 == "0" }))
        var padded = "0" + trimmed
        if padded.count % 2 != 0 { padded = "0" + padded }
        return Data(hexString: padded) ?? Data()
    }
}

extension Data {
    public init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var out = Data(capacity: hexString.count / 2)
        var i = hexString.startIndex
        while i < hexString.endIndex {
            let j = hexString.index(i, offsetBy: 2)
            guard let b = UInt8(hexString[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        self = out
    }
}
