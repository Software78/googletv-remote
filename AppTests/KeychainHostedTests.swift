import Testing
import Foundation
@testable import GoogleTVRemote
import GoogleTVKit

/// Runs inside the app host, which is what grants keychain access. Covers what the
/// SwiftPM test bundle can't.
@Suite struct KeychainHostedTests {
    @Test func keychainStoreRoundTrip() throws {
        let store = KeychainIdentityStore(service: "com.googletvremote.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        let first = try store.loadOrCreate()
        let second = try #require(try store.load())
        #expect(second == first)
        _ = try store.secIdentity()
        try store.delete()
        #expect(try store.load() == nil)
    }
}
