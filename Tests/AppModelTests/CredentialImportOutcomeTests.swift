import CredentialKit
import XCTest
@testable import LocalIPASigner

/// Model outcomes use bounded, synthetic encrypted input and public metadata, never a private key.
/// Real modern/legacy crypto and Keychain integration remain in CredentialKit's suites.
@MainActor
final class CredentialImportOutcomeTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("credential-outcome-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }
    private func store() throws -> CredentialStore { try CredentialStore(directory: base.appendingPathComponent("store")) }
    private func picked(_ bytes: Data = Data([1, 2, 3]), name: String = UUID().uuidString + ".p12") throws -> URL {
        let file = base.appendingPathComponent(name); try bytes.write(to: file); return file
    }
    private func certificate(_ name: String = "Public test identity") throws -> CertificateInfo {
        let json: [String: Any] = ["id": UUID().uuidString, "commonName": name, "serialNumberHex": "01", "sha1Fingerprint": String(repeating: "A", count: 40), "notBefore": 0, "notAfter": 1000000, "importedAt": 0]
        return try JSONDecoder().decode(CertificateInfo.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func profile() throws -> ProfileInfo {
        let json: [String: Any] = ["id": UUID().uuidString, "name": "Test profile", "teamID": "AAAAAAAAAA", "applicationIdentifier": "AAAAAAAAAA.*", "platforms": ["iOS"], "expirationDate": 1000000, "kind": "development", "provisionsAllDevices": false, "getTaskAllow": true, "certificateSHA1s": [], "importedAt": 0]
        return try JSONDecoder().decode(ProfileInfo.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func testWrongPasswordCanRetryRepeatedlyWithoutAnotherFilePick() async throws {
        let info = try certificate()
        let model = CredentialsModel(store: try store(), certificateImport: { _, data, password in
            XCTAssertFalse(Thread.isMainThread); XCTAssertEqual(data, Data([1, 2, 3]))
            guard password == "correct" else { throw CredentialError.incorrectPassword }; return [info]
        })
        let file = try picked(); await model.picked(p12: .success(file))?.value
        XCTAssertTrue(model.awaitingPassword); XCTAssertNil(model.busyMessage)
        await model.confirmPassword("wrong")?.value
        XCTAssertTrue(model.canRetryPassword); XCTAssertEqual(model.message, CredentialError.incorrectPassword.errorDescription)
        model.requestPasswordRetry(); XCTAssertTrue(model.awaitingPassword)
        await model.confirmPassword("wrong again")?.value; XCTAssertTrue(model.canRetryPassword)
        await model.confirmPassword("correct")?.value
        XCTAssertTrue(model.message?.hasPrefix("Imported ") == true); XCTAssertFalse(model.canRetryPassword)
        XCTAssertEqual(model.importedItemID, "credential-\(info.id)"); XCTAssertFalse(model.awaitingPassword)
        XCTAssertNil(model.confirmPassword("correct"), "success must clear retained bytes")
    }
    func testConfirmedSlowImportLeavesMainActorResponsiveAndCannotBeReplaced() async throws {
        let entered = expectation(description: "worker began"), release = DispatchSemaphore(value: 0), info = try certificate()
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in
            XCTAssertFalse(Thread.isMainThread); entered.fulfill()
            guard release.wait(timeout: .now() + 5) == .success else { throw CredentialError.storage("test worker timed out") }
            return [info]
        })
        await model.picked(p12: .success(try picked()))?.value
        let task = try XCTUnwrap(model.confirmPassword("test"))
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 3)
        // These actor-isolated assertions and actions execute while crypto is deliberately blocked.
        XCTAssertNotNil(model.busyMessage); XCTAssertFalse(model.canCancelReading)
        XCTAssertNil(model.picked(p12: .success(try picked(name: "other.p12"))))
        XCTAssertNil(model.confirmPassword("another")); model.cancelPassword(); model.dismissPassword()
        XCTAssertNotNil(model.busyMessage, "confirmed Keychain commit must not pretend to cancel")
        release.signal(); await task.value
        XCTAssertEqual(model.importedItemID, "credential-\(info.id)"); XCTAssertNil(model.busyMessage)
    }
    func testCancelAndDismissClearPendingInput() async throws {
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in XCTFail("must not import cancelled bytes"); return [] })
        await model.picked(p12: .success(try picked()))?.value
        model.cancelPassword(); XCTAssertFalse(model.awaitingPassword); XCTAssertFalse(model.canRetryPassword)
        XCTAssertNil(model.confirmPassword("ignored"))
        await model.picked(p12: .success(try picked()))?.value
        model.dismissPassword(); XCTAssertFalse(model.canRetryPassword); XCTAssertEqual(model.pendingFileName, "")
    }
    func testNewPickAndCancelledReadCannotPublishOldPendingInput() async throws {
        let model = CredentialsModel(store: try store())
        let first = model.picked(p12: .success(try picked(name: "old.p12")))
        let second = model.picked(p12: .success(try picked(name: "new.p12")))
        await first?.value; await second?.value
        XCTAssertTrue(model.awaitingPassword); XCTAssertEqual(model.pendingFileName, "new.p12")
        let cancelled = model.picked(p12: .success(try picked()))
        model.cancelPassword(); await cancelled?.value
        XCTAssertNil(model.busyMessage); XCTAssertFalse(model.awaitingPassword); XCTAssertFalse(model.canRetryPassword)
    }
    func testEmptyImporterAndKeychainFailureNeverAnnounceSuccess() async throws {
        for importer: @Sendable (CredentialStore, Data, String) throws -> [CertificateInfo] in [
            { _, _, _ in [] }, { _, _, _ in throw CredentialError.keychain(operation: "test", status: -50) }
        ] {
            let model = CredentialsModel(store: try store(), certificateImport: importer)
            await model.picked(p12: .success(try picked()))?.value
            await model.confirmPassword("test")?.value
            XCTAssertNil(model.importedItemID); XCTAssertTrue(model.canRetryPassword)
            XCTAssertFalse(model.message?.hasPrefix("Imported ") == true); XCTAssertNil(model.busyMessage)
        }
    }
    func testOnlyActualImportedIdentitiesAreReported() async throws {
        let first = try certificate("One"), second = try certificate("Two")
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in [first, second] })
        await model.picked(p12: .success(try picked()))?.value; await model.confirmPassword("test")?.value
        XCTAssertEqual(model.message, "Imported 2 identities: One, Two.")
        XCTAssertEqual(model.importedItemID, "credential-\(first.id)")
    }
    func testUnknownErrorsAndPasswordsAreNotLoggedOrShown() async throws {
        struct SecretError: LocalizedError { let value: String; var errorDescription: String? { value } }
        let sentinel = "sensitive-password-" + UUID().uuidString
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, password in throw SecretError(value: password) })
        await model.picked(p12: .success(try picked()))?.value; await model.confirmPassword(sentinel)?.value
        XCTAssertFalse(model.message?.contains(sentinel) == true)
        XCTAssertFalse(ImportLogs.shared.recentLines(60).joined().contains(sentinel)); XCTAssertTrue(model.canRetryPassword)
    }
    func testOversizedInputIsRejectedBeforeImporterRuns() async throws {
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in XCTFail("oversized file reached importer"); return [] })
        await model.picked(p12: .success(try picked(Data(repeating: 0, count: 5 * 1024 * 1024 + 1))))?.value
        XCTAssertEqual(model.message, CredentialError.fileTooLarge.errorDescription)
        XCTAssertNil(model.busyMessage); XCTAssertFalse(model.awaitingPassword); XCTAssertFalse(model.canRetryPassword)
    }
    func testBoundedReadExactLimitOverflowMissingAndNonregular() throws {
        let file = try picked(Data([1, 2, 3]))
        XCTAssertEqual(try CredentialsModel.readBounded(file, limit: 3), Data([1, 2, 3]))
        XCTAssertThrowsError(try CredentialsModel.readBounded(file, limit: 2)) { XCTAssertEqual($0 as? CredentialError, .fileTooLarge) }
        XCTAssertThrowsError(try CredentialsModel.readBounded(file, limit: 0))
        XCTAssertThrowsError(try CredentialsModel.readBounded(base, limit: 100))
        XCTAssertThrowsError(try CredentialsModel.readBounded(base.appendingPathComponent("missing"), limit: 100))
    }
    func testProfileImportRunsOffMainAndClearsBusyState() async throws {
        let info = try profile()
        let model = CredentialsModel(store: try store(), profileImport: { _, data in
            XCTAssertFalse(Thread.isMainThread); XCTAssertEqual(data, Data([1, 2, 3])); return info
        })
        await model.picked(profile: .success(try picked(name: "test.mobileprovision")))?.value
        XCTAssertEqual(model.message, "Imported profile Test profile.")
        XCTAssertEqual(model.importedItemID, "credential-\(info.id)"); XCTAssertNil(model.busyMessage)
    }
    func testProfileFailureAndOversizeNeverAnnounceImported() async throws {
        let model = CredentialsModel(store: try store(), profileImport: { _, _ in throw CredentialError.profileNotCMS })
        await model.picked(profile: .success(try picked()))?.value
        XCTAssertEqual(model.message, CredentialError.profileNotCMS.errorDescription); XCTAssertNil(model.importedItemID)
        await model.picked(profile: .success(try picked(Data(repeating: 0, count: 1024 * 1024 + 1))))?.value
        XCTAssertEqual(model.message, CredentialError.fileTooLarge.errorDescription); XCTAssertNil(model.busyMessage)
    }
}
