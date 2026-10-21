import XCTest
@testable import CredentialKit

/// Exercises the real Keychain. Skips (and says so) if the environment denies Keychain access,
/// for example an unsigned test host without keychain entitlements.
final class SystemKeychainTests: XCTestCase {
    private var keychain: SystemIdentityKeychain!
    private var ids: [UUID] = []

    override func setUp() {
        keychain = SystemIdentityKeychain(service: "dev.localsigner.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        for id in ids { try? keychain.remove(id: id) }
    }

    private func storeFixture() throws -> UUID {
        let parsed = try PKCS12Reader.read(FixtureData.p12ValidLegacy, password: FixtureData.password)
        let id = UUID()
        ids.append(id)
        do { try keychain.store(identity: parsed.identity, id: id) }
        catch CredentialError.keychain(_, let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain unavailable in this test host (errSecMissingEntitlement)")
        }
        return id
    }

    func testStoreFetchSignAndRemove() throws {
        let id = try storeFixture()
        let identity = try keychain.identity(id: id)

        var key: SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(identity, &key), errSecSuccess)
        let privateKey = try XCTUnwrap(key)
        // Prove the stored key is really usable, not just present.
        var error: Unmanaged<CFError>?
        let sig = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data("x".utf8) as CFData, &error)
        XCTAssertNotNil(sig, "\(String(describing: error?.takeRetainedValue()))")

        var cert: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(identity, &cert), errSecSuccess)
        XCTAssertEqual(SecCertificateCopyData(try XCTUnwrap(cert)) as Data, FixtureData.certADER)

        try keychain.remove(id: id)
        XCTAssertThrowsError(try keychain.identity(id: id)) { XCTAssertEqual($0 as? CredentialError, .notFound) }
    }

    func testRemoveIsIdempotent() throws {
        let id = try storeFixture()
        try keychain.remove(id: id)
        XCTAssertNoThrow(try keychain.remove(id: id))
        XCTAssertNoThrow(try keychain.remove(id: UUID()))
    }

    func testStoringSameIDTwiceFailsAndKeepsOriginal() throws {
        let id = try storeFixture()
        let parsed = try PKCS12Reader.read(FixtureData.p12ValidLegacy, password: FixtureData.password)
        XCTAssertThrowsError(try keychain.store(identity: parsed.identity, id: id)) {
            guard case .keychain = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertNoThrow(try keychain.identity(id: id))
    }

    func testSameCertificateUnderNewIDReplacesStaleItem() throws {
        // Simulates a reinstall: the Keychain still holds the certificate, the index is gone.
        let old = try storeFixture()
        let parsed = try PKCS12Reader.read(FixtureData.p12ValidModern, password: FixtureData.password)
        let new = UUID()
        ids.append(new)
        try keychain.store(identity: parsed.identity, id: new)
        XCTAssertNoThrow(try keychain.identity(id: new))
        try keychain.remove(id: new)
        try keychain.remove(id: old)
        XCTAssertThrowsError(try keychain.identity(id: new))
    }

    func testStoreEndToEndThroughCredentialStore() throws {
        _ = try storeFixture() // skip early if Keychain is unavailable
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try CredentialStore(directory: dir, keychain: keychain)
        let info = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        ids.append(info.id)
        XCTAssertNoThrow(try store.identity(for: info.id))
        try store.deleteCertificate(id: info.id)
        XCTAssertThrowsError(try keychain.identity(id: info.id))
    }

    func testAccessibilityPolicyIsAfterFirstUnlock() {
        XCTAssertEqual(SystemIdentityKeychain.accessibility as String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testMigrationKeepsTheIdentityUsable() throws {
        let id = try storeFixture()
        keychain.migrateAccessibility()
        _ = try keychain.identity(id: id)
    }
}
