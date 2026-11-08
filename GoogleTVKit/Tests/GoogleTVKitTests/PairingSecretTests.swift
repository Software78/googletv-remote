import Testing
import Foundation
@testable import GoogleTVKit

@Suite struct PairingSecretTests {
    // Vector produced by running androidtvremote2's pairing.py hash expressions verbatim
    // (`bytes.fromhex(f"{n:X}")`, `bytes.fromhex(f"0{e:X}")`) on these fixed inputs.
    // Moduli are 32-byte seeds repeated 8x (2048-bit, top bit set).
    static let clientModulus = Data(hexString: String(repeating: "948FE603F61DC036B5C596DC09FE3CE3F3D30DC90F024C85F3C82DB2CCAB679D", count: 8))!
    static let serverModulus: Data = {
        var d = Data(hexString: String(repeating: "B3EACD33433B31B5252351032C9B3E7A2E7AA7738D5DECDF0DD6C62680853C06", count: 8))!
        d[d.count - 1] |= 1
        return d
    }()
    static let e65537 = Data([0x01, 0x00, 0x01])
    static let code = "721A2B"
    static let expected = "728b7904bea4602b48598f7564cdf64287910c0212522cb656d2babc85392e5c"

    @Test func matchesReferenceVector() throws {
        let secret = try PairingSecret.compute(
            clientModulus: Self.clientModulus, clientExponent: Self.e65537,
            serverModulus: Self.serverModulus, serverExponent: Self.e65537, code: Self.code)
        #expect(secret.map { String(format: "%02x", $0) }.joined() == Self.expected)
    }

    @Test func lowercaseCodeAccepted() throws {
        _ = try PairingSecret.compute(
            clientModulus: Self.clientModulus, clientExponent: Self.e65537,
            serverModulus: Self.serverModulus, serverExponent: Self.e65537, code: Self.code.lowercased())
    }

    @Test func leadingZeroBytesAreStripped() throws {
        let padded = Data([0, 0]) + Self.clientModulus
        let s = try PairingSecret.compute(
            clientModulus: padded, clientExponent: Data([0, 1, 0, 1]),
            serverModulus: Self.serverModulus, serverExponent: Self.e65537, code: Self.code)
        #expect(s.map { String(format: "%02x", $0) }.joined() == Self.expected)
    }

    @Test func wrongCodeFailsChecksum() {
        #expect(throws: PairingSecret.CodeError.checksumMismatch) {
            _ = try PairingSecret.compute(
                clientModulus: Self.clientModulus, clientExponent: Self.e65537,
                serverModulus: Self.serverModulus, serverExponent: Self.e65537, code: "731A2B")
        }
        #expect(throws: PairingSecret.CodeError.checksumMismatch) {
            _ = try PairingSecret.compute(
                clientModulus: Self.clientModulus, clientExponent: Self.e65537,
                serverModulus: Self.serverModulus, serverExponent: Self.e65537, code: "721A2C")
        }
    }

    @Test(arguments: ["", "12345", "1234567", "12345G", "ZZZZZZ", "12 456"])
    func malformedCodeRejected(code: String) {
        #expect(throws: PairingSecret.CodeError.invalidFormat) { _ = try PairingSecret.decodeCode(code) }
    }

    @Test func errorsMapToUserFacingGuidance() {
        #expect(TVError.wrongCode.recovery == .retry)
        #expect(TVError.notPaired.recovery == .pair)
        #expect(TVError.unreachable(host: "tv").message.contains("tv"))
    }
}
