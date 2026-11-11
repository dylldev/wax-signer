import CredentialKit
import Combine
import XCTest
import Security
import SwiftUI
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
    func testCombinedImportPersistsOnlyNicknameAndClearsDrafts() async throws {
        let info = try certificate(), provision = try profile()
        let suite = "credential-nicknames-\(UUID())"
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        let model = CredentialsModel(store: try store(), preferences: isolated,
            certificateImport: { _, _, password in XCTAssertEqual(password, "temporary secret"); return [info] },
            profileImport: { _, _ in return provision })
        await model.stageCertificate(.success(try picked()))?.value
        await model.stageProfile(.success(try picked(name: "matching.mobileprovision")))?.value
        XCTAssertTrue(model.canSubmitImport)
        XCTAssertFalse(model.awaitingPassword)
        await model.confirmImport(password: "temporary secret", nickname: "  My identity  ")?.value
        XCTAssertTrue(model.importCompleted)
        XCTAssertEqual(model.displayName(for: info), "My identity")
        XCTAssertFalse(model.canSubmitImport)
        XCTAssertEqual(model.pendingFileName, "")
        XCTAssertEqual(model.pendingProfileName, "")
        let reloaded = CredentialsModel(store: try store(), preferences: isolated)
        XCTAssertEqual(reloaded.displayName(for: info), "My identity")
        XCTAssertEqual(reloaded.displayName(for: try certificate("Other identity")), "Other identity")
        XCTAssertFalse(String(describing: isolated.persistentDomain(forName: suite)).contains("temporary secret"))
    }
    func testCombinedWrongPasswordDoesNotImportProfileAndCanRetry() async throws {
        let info = try certificate()
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, password in
            guard password == "correct" else { throw CredentialError.incorrectPassword }; return [info]
        }, profileImport: { _, _ in XCTFail("profile must not import after certificate failure"); throw CredentialError.profileNotCMS })
        await model.stageCertificate(.success(try picked()))?.value
        await model.stageProfile(.success(try picked(name: "profile.mobileprovision")))?.value
        await model.confirmImport(password: "wrong", nickname: "")?.value
        XCTAssertFalse(model.importCompleted); XCTAssertTrue(model.canSubmitImport)
        XCTAssertEqual(model.message, CredentialError.incorrectPassword.errorDescription)
        model.dismissImport()
        XCTAssertFalse(model.canSubmitImport); XCTAssertEqual(model.pendingProfileName, "")
    }
    func testCombinedProfileFailureReportsCertificateAndPreservesItsNickname() async throws {
        let info = try certificate()
        let suite = "credential-partial-\(UUID())"
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        let model = CredentialsModel(store: try store(), preferences: isolated,
            certificateImport: { _, _, _ in [info] }, profileImport: { _, _ in throw CredentialError.profileNotCMS })
        await model.stageCertificate(.success(try picked()))?.value
        await model.stageProfile(.success(try picked(name: "bad.mobileprovision")))?.value
        await model.confirmImport(password: "", nickname: "Kept identity")?.value
        XCTAssertFalse(model.importCompleted)
        XCTAssertTrue(model.message?.contains("Certificate imported") == true)
        XCTAssertTrue(model.message?.contains("Profile was not imported") == true)
        XCTAssertEqual(model.displayName(for: info), "Kept identity")
        XCTAssertFalse(model.canSubmitImport)
    }
    func testCombinedDismissAndRepeatedDoneAreSafe() async throws {
        let entered = expectation(description: "combined worker began"), release = DispatchSemaphore(value: 0)
        let info = try certificate()
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in
            entered.fulfill()
            guard release.wait(timeout: .now() + 5) == .success else { throw CredentialError.storage("timeout") }
            return [info]
        })
        await model.stageCertificate(.success(try picked()))?.value
        let work = try XCTUnwrap(model.confirmImport(password: "", nickname: ""))
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertNil(model.confirmImport(password: "", nickname: ""))
        model.dismissImport(); XCTAssertNotNil(model.busyMessage)
        release.signal(); await work.value
        XCTAssertTrue(model.importCompleted); XCTAssertFalse(model.canSubmitImport)
        await model.stageProfile(.success(try picked(name: "discard.mobileprovision")))?.value
        model.dismissImport(); XCTAssertFalse(model.canSubmitImport)
    }

    func testImportSheetRendersLongFilenamesWithoutLosingEitherSelection() async throws {
        let model = CredentialsModel(store: try store())
        let certificateName = String(repeating: "Long-certificate-name-", count: 6) + ".p12"
        let profileName = String(repeating: "Long-provisioning-profile-", count: 6) + ".mobileprovision"
        await model.stageCertificate(.success(try picked(name: certificateName)))?.value
        await model.stageProfile(.success(try picked(name: profileName)))?.value
        XCTAssertEqual(model.pendingFileName, certificateName)
        XCTAssertEqual(model.pendingProfileName, profileName)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: CredentialImportSheet().environmentObject(model))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "credential-import-long-filenames"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(image.size.width, 0)
        model.dismissImport()
        XCTAssertFalse(model.canSubmitImport)
    }

    func testCombinedImportPublishesItsTargetAfterProfileImport() async throws {
        let info = try certificate(), provision = try profile()
        let profileImported = expectation(description: "profile import finishes")
        let targetPublished = expectation(description: "scroll target publishes")
        let model = CredentialsModel(store: try store(), certificateImport: { _, _, _ in [info] },
            profileImport: { _, _ in profileImported.fulfill(); return provision })
        let listener = model.$importedItemID.compactMap { $0 }.sink { _ in targetPublished.fulfill() }
        defer { listener.cancel() }
        await model.stageCertificate(.success(try picked()))?.value
        await model.stageProfile(.success(try picked(name: "matching.mobileprovision")))?.value
        await model.confirmImport(password: "", nickname: "")?.value
        await fulfillment(of: [profileImported, targetPublished], timeout: 1, enforceOrder: true)
        XCTAssertTrue(model.importCompleted)
    }

    func testDeletingCertificateRemovesOnlyItsNicknameAfterSuccess() async throws {
        let first = try certificate("First"), second = try certificate("Second")
        for failRemoval in [false, true] {
            let directory = base.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            struct Index: Encodable { let certificates: [CertificateInfo]; let profiles: [ProfileInfo] }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Index(certificates: [first, second], profiles: [])).write(to: directory.appendingPathComponent("index.json"))
            let preferences = try XCTUnwrap(UserDefaults(suiteName: "credential-delete-\(UUID())"))
            defer { preferences.removeObject(forKey: "credential.displayNicknames") }
            preferences.set([first.id.uuidString: "First nickname", second.id.uuidString: "Second nickname"], forKey: "credential.displayNicknames")
            let store = try CredentialStore(directory: directory, keychain: ImportRemovalKeychain(failRemoval: failRemoval))
            let model = CredentialsModel(store: store, preferences: preferences)
            model.delete(certificate: first)
            for _ in 0..<200 where model.busyMessage != nil { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertNil(model.busyMessage)
            XCTAssertEqual(model.displayName(for: first), failRemoval ? "First nickname" : "First")
            XCTAssertEqual(model.displayName(for: second), "Second nickname")
            XCTAssertEqual(model.certificates.contains(first), failRemoval)
        }
    }

}


private struct ImportRemovalKeychain: IdentityKeychain {
    let failRemoval: Bool
    func store(identity: SecIdentity, id: UUID) throws { }
    func identity(id: UUID) throws -> SecIdentity { throw CredentialError.notFound }
    func remove(id: UUID) throws {
        if failRemoval { throw CredentialError.keychain(operation: "remove", status: -50) }
    }
}
