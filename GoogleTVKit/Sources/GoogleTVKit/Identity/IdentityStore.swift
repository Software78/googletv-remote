import Foundation
import Security

public protocol IdentityStore: Sendable {
    func load() throws -> ClientIdentity?
    func save(_ identity: ClientIdentity) throws
    func delete() throws
}

extension IdentityStore {
    /// Returns the stored identity, generating and persisting one on first use.
    public func loadOrCreate() throws -> ClientIdentity {
        if let existing = try load() { return existing }
        let fresh = try CertificateFactory.generate()
        try save(fresh)
        return fresh
    }
}

public final class InMemoryIdentityStore: IdentityStore, @unchecked Sendable {
    private let lock = NSLock()
    private var identity: ClientIdentity?
    public init() {}
    public func load() throws -> ClientIdentity? { lock.withLock { identity } }
    public func save(_ identity: ClientIdentity) throws { lock.withLock { self.identity = identity } }
    public func delete() throws { lock.withLock { identity = nil } }
}

/// Stores the certificate and private key as separate Keychain items so `SecIdentity` can be
/// reconstructed (needed for Network.framework client auth). The key's application label
/// (public-key hash) is what links the two.
public struct KeychainIdentityStore: IdentityStore {
    private let tag: Data
    private let certLabel: String
    private let accessGroup: String?

    public init(service: String = "com.googletvremote.identity", accessGroup: String? = nil) {
        self.tag = Data(service.utf8)
        self.certLabel = service + ".cert"
        self.accessGroup = accessGroup
    }

    private func base(_ cls: CFString) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: cls]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        #if !os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }
    private var certQuery: [String: Any] {
        var q = base(kSecClassCertificate); q[kSecAttrLabel as String] = certLabel; return q
    }
    private var keyQuery: [String: Any] {
        var q = base(kSecClassKey)
        q[kSecAttrApplicationTag as String] = tag
        q[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        return q
    }

    public func load() throws -> ClientIdentity? {
        var certResult: CFTypeRef?
        var q = certQuery
        q[kSecReturnRef as String] = true
        let cs = SecItemCopyMatching(q as CFDictionary, &certResult)
        if cs == errSecItemNotFound { return nil }
        guard cs == errSecSuccess, let certRef = certResult else { throw TVError.keychain(cs) }
        let certDER = SecCertificateCopyData(certRef as! SecCertificate) as Data

        var keyResult: CFTypeRef?
        var kq = keyQuery
        kq[kSecReturnRef as String] = true
        let ks = SecItemCopyMatching(kq as CFDictionary, &keyResult)
        if ks == errSecItemNotFound { return nil }
        guard ks == errSecSuccess, let keyRef = keyResult else { throw TVError.keychain(ks) }
        var err: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(keyRef as! SecKey, &err) as Data? else {
            throw TVError.keychain(errSecInvalidKeychain)
        }
        return try ClientIdentity(certificateDER: certDER, privateKeyDER: keyData)
    }

    public func save(_ identity: ClientIdentity) throws {
        try delete()
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(identity.privateKeyDER as CFData, keyAttrs as CFDictionary, &err) else {
            throw TVError.keychain(errSecParam)
        }
        var kq = keyQuery
        kq[kSecValueRef as String] = key
        #if !os(macOS)
        kq[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        var status = SecItemAdd(kq as CFDictionary, nil)
        guard status == errSecSuccess else { throw TVError.keychain(status) }

        guard let cert = SecCertificateCreateWithData(nil, identity.certificateDER as CFData) else {
            throw TVError.keychain(errSecParam)
        }
        var cq = certQuery
        cq[kSecValueRef as String] = cert
        #if !os(macOS)
        cq[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        status = SecItemAdd(cq as CFDictionary, nil)
        guard status == errSecSuccess else { throw TVError.keychain(status) }
    }

    public func delete() throws {
        for q in [certQuery, keyQuery] {
            let s = SecItemDelete(q as CFDictionary)
            guard s == errSecSuccess || s == errSecItemNotFound else { throw TVError.keychain(s) }
        }
    }

    /// Returns the `SecIdentity` Network.framework needs for TLS client auth. The Keychain
    /// forms an identity from the certificate + private key whose public-key hashes match.
    public func secIdentity() throws -> SecIdentity {
        var result: CFTypeRef?
        var q = base(kSecClassIdentity)
        q[kSecAttrLabel as String] = certLabel
        q[kSecReturnRef as String] = true
        let s = SecItemCopyMatching(q as CFDictionary, &result)
        guard s == errSecSuccess, let ref = result else { throw TVError.keychain(s) }
        return ref as! SecIdentity
    }
}
