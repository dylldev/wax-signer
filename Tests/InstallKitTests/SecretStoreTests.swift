import Security
import XCTest
@testable import InstallKit

final class SecretStoreTests: XCTestCase {
    func testRoundTripAndDelete() throws {
        let store = KeychainSecretStore(service: "wax.test.secret.\(UUID().uuidString)")
        defer { store.delete() }
        XCTAssertNil(store.load())
        let blob = Data((0..<64).map { UInt8($0) })
        try store.save(blob)
        XCTAssertEqual(store.load(), blob)
        try store.save(Data([9, 9]))               // replaces, does not duplicate
        XCTAssertEqual(store.load(), Data([9, 9]))
        store.delete()
        XCTAssertNil(store.load())
    }

    func testAccessibilityPolicyIsAfterFirstUnlock() {
        XCTAssertEqual(KeychainSecretStore.accessibility as String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testMigrationKeepsTheSecret() throws {
        let store = KeychainSecretStore(service: "wax.test.secret.\(UUID().uuidString)")
        defer { store.delete() }
        try store.save(Data([1, 2, 3]))
        store.migrateAccessibility()
        XCTAssertEqual(store.load(), Data([1, 2, 3]))
        store.migrateAccessibility()   // harmless when run twice
        XCTAssertEqual(store.load(), Data([1, 2, 3]))
    }
}
