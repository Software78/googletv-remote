import Testing
import Foundation
import Security
@testable import GoogleTVKit

@Suite struct IdentityTests {
    @Test func generatesRSA2048SelfSignedCert() throws {
        let id = try CertificateFactory.generate()
        #expect(id.publicNumbers.modulus.count == 256)
        #expect(id.publicNumbers.exponent == Data([0x01, 0x00, 0x01]))
        let cert = try #require(SecCertificateCreateWithData(nil, id.certificateDER as CFData))
        let key = try #require(SecCertificateCopyKey(cert))
        let attrs = try #require(SecKeyCopyAttributes(key) as? [String: Any])
        #expect(attrs[kSecAttrKeySizeInBits as String] as? Int == 2048)
        #expect(SecCertificateCopySubjectSummary(cert) as String? == "atvremote")
    }

    @Test func privateKeyMatchesCertificate() throws {
        let id = try CertificateFactory.generate()
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var err: Unmanaged<CFError>?
        let priv = try #require(SecKeyCreateWithData(id.privateKeyDER as CFData, attrs as CFDictionary, &err))
        let pub = try #require(SecKeyCopyPublicKey(priv))
        let cert = try #require(SecCertificateCreateWithData(nil, id.certificateDER as CFData))
        let certPub = try #require(SecCertificateCopyKey(cert))
        #expect(SecKeyCopyExternalRepresentation(pub, nil) as Data? == SecKeyCopyExternalRepresentation(certPub, nil) as Data?)
    }

    @Test func inMemoryStoreReusesIdentity() throws {
        let store = InMemoryIdentityStore()
        let first = try store.loadOrCreate()
        #expect(try store.loadOrCreate() == first)
        try store.delete()
        #expect(try store.load() == nil)
    }

    /// SwiftPM test bundles have no host app, hence no keychain entitlement (-34018) on either
    /// macOS or the simulator. This test is skipped there and must be run from the app's
    /// hosted test target (added in Milestone 2).
    static let keychainAvailable: Bool = {
        #if os(macOS)
        return false   // imported keys fail with -34018 in an unsigned runner even though passwords work
        #else
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.googletvremote.probe",
            kSecValueData as String: Data([1]),
        ]
        #if !os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        let s = SecItemAdd(q as CFDictionary, nil)
        SecItemDelete(q as CFDictionary)
        return s == errSecSuccess || s == errSecDuplicateItem
        #endif
    }()

    @Test(.enabled(if: IdentityTests.keychainAvailable, "needs keychain entitlement (app-hosted tests)"))
    func keychainStoreRoundTrip() throws {
        let store = KeychainIdentityStore(service: "com.googletvremote.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        let first = try store.loadOrCreate()
        let second = try #require(try store.load())
        #expect(second == first)
        _ = try store.secIdentity()   // proves cert+key link up for TLS client auth
        try store.delete()
        #expect(try store.load() == nil)
    }
}
