import CredentialKit
import InstallKit
import IPAKit
import SigningKit
import Security
import XCTest
import UIKit
@testable import LocalIPASigner

@MainActor
final class PreparedSigningOutcomeTests: XCTestCase {
    private var root: URL!
    private var store: CredentialStore!
    private var library: LibraryModel!
    private var model: SigningModel!
    private var certificate: UUID!
    private var profile: UUID!
    private var fixture: URL { Bundle(for: Self.self).url(forResource: "TestApp", withExtension: "ipa")! }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("preview-model-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try CredentialStore(directory: root.appendingPathComponent("credentials"), keychain: FixtureIdentities())
        certificate = try store.importCertificates(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)[0].id
        profile = try store.importProfile(FixtureData.profileWildcardAll).id
        library = LibraryModel(library: IPALibrary(root: root.appendingPathComponent("shelf")), announce: { _ in }, load: false)
        model = SigningModel(credentials: CredentialsModel(store: store), library: library)
    }
    override func tearDownWithError() throws {
        model?.clearResult()
        for cert in store?.certificates() ?? [] { try? store.deleteCertificate(id: cert.id) }
        try? FileManager.default.removeItem(at: root)
    }
    private func select() async throws {
        let saved = try await library.fileNow(fixture, info: IPAInspector.inspect(url: fixture))
        await model.picked(ipa: library.url(for: saved.entry), fromLibrary: saved.entry).value
        model.certificateID = certificate
    }
    private func prepare(installAfter: Bool = false) async throws {
        let task = try XCTUnwrap(model.prepareForSigning(installAfter: installAfter))
        await task.value
        XCTAssertNil(model.errorText); XCTAssertNotNil(model.preview)
        XCTAssertNil(model.report); XCTAssertFalse(model.shelfSaveState.confirmedSaved)
        XCTAssertNil(model.busyMessage); XCTAssertFalse(model.runningSign)
    }
    func testActualApplicationFlowRequiresPreviewThenExplicitConfirmation() async throws {
        try await select()
        XCTAssertNil(model.sign()); XCTAssertNil(model.report)
        // Refusing an unconfirmed request does not poison the next preparation.
        try await prepare()
        let id = try XCTUnwrap(model.preview?.proposed.identifier)
        await model.sign()?.value
        XCTAssertNil(model.errorText); XCTAssertNil(model.preview)
        XCTAssertTrue(model.shelfSaveState.confirmedSaved)
        XCTAssertEqual(model.report?.installTarget.bundleIdentifier, id)
        XCTAssertNil(model.sign()); XCTAssertNotNil(model.report)
    }
    func testChangedOptionsInvalidatePreviewAndNeverSilentlySignNewSettings() async throws {
        try await select(); try await prepare()
        model.edits.version = "77"
        XCTAssertNil(model.preview); XCTAssertNil(model.sign()); XCTAssertNil(model.report)
        try await prepare(); XCTAssertEqual(model.preview?.proposed.version, "77")
        await model.sign()?.value
        XCTAssertEqual(model.report?.installTarget.version, "77")
    }
    func testProfileAndStrictModeChangesRequireNewPreview() async throws {
        try await select(); try await prepare()
        model.bundleProfiles["PlugIns/TestExt.appex"] = profile
        XCTAssertNil(model.preview)
        try await prepare()
        model.strictEntitlements = true; XCTAssertNil(model.preview)
        XCTAssertNil(model.sign())
    }
    func testCredentialRemovalAfterPreviewRefusesWithNoFalseSavedResult() async throws {
        try await select(); try await prepare()
        try store.deleteProfile(id: profile)
        await model.sign()?.value
        XCTAssertNil(model.report); XCTAssertFalse(model.shelfSaveState.confirmedSaved)
        XCTAssertTrue(model.errorText?.contains("changed after preview") == true)
    }
    func testImmediateCancellationSuppressesLatePreviewAndKeepsInput() async throws {
        try await select()
        let task = try XCTUnwrap(model.prepareForSigning())
        model.clearResult()
        await task.value
        XCTAssertNil(model.preview); XCTAssertNil(model.report)
        XCTAssertFalse(model.runningSign); XCTAssertNil(model.busyMessage)
        XCTAssertEqual(library.unsigned.count, 1)
        XCTAssertNotNil(try? IPAInspector.inspect(url: library.url(for: library.unsigned[0])))
    }
    func testSecondOperationCannotReplaceInFlightPreparation() async throws {
        try await select()
        let task = try XCTUnwrap(model.prepareForSigning())
        XCTAssertNil(model.prepareForSigning()); XCTAssertNil(model.sign())
        await task.value
        XCTAssertNotNil(model.preview); XCTAssertNil(model.report)
    }
    func testSigningSuccessShelfFailureStillExportsAndRetriesWithoutResigning() async throws {
        try await select(); try await prepare()
        let index = root.appendingPathComponent("shelf/index.json")
        let original = try Data(contentsOf: index)
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        await model.sign()?.value
        XCTAssertNotNil(model.report); XCTAssertFalse(model.shelfSaveState.confirmedSaved)
        let output = try XCTUnwrap(model.report?.output), bytes = try Data(contentsOf: output)
        let exported = root.appendingPathComponent("export.ipa")
        try FileManager.default.copyItem(at: output, to: exported)
        XCTAssertEqual(try Data(contentsOf: exported), bytes)
        await model.retrySignedSave(); XCTAssertEqual(try Data(contentsOf: output), bytes)
        try FileManager.default.removeItem(at: index); try original.write(to: index)
        await model.retrySignedSave()
        XCTAssertTrue(model.shelfSaveState.confirmedSaved)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.report?.output)), bytes)
    }
    func testPreparationKeepsInstallIntentButDoesNotReserveOrStartInstallation() async throws {
        try await select(); try await prepare(installAfter: true)
        XCTAssertTrue(model.previewInstalls); XCTAssertFalse(model.installing)
        XCTAssertNil(model.readyLink); XCTAssertNil(model.report)
    }
    func testBackgroundExpirationCancelsOwnedPreparationAndNeverAnnouncesSaved() async throws {
        let background = BackgroundJob(system: .init(beginGrace: { _, expired in expired(); return UIBackgroundTaskIdentifier(rawValue: 1) },
            endGrace: { _ in }, requestContinued: { _ in }, cancelContinued: {}, isInBackground: { true }))
        model = SigningModel(credentials: CredentialsModel(store: store), library: library, background: background)
        try await select()
        await model.prepareForSigning()?.value
        XCTAssertNil(model.preview); XCTAssertNil(model.report); XCTAssertFalse(model.shelfSaveState.confirmedSaved)
        XCTAssertTrue(model.errorText?.contains("canceled") == true); XCTAssertEqual(background.activeCount, 0)
        XCTAssertEqual(library.unsigned.count, 1)
    }
    func testOversizedEntitlementInputRefusesBeforeBecomingPreviewConfiguration() throws {
        let file = root.appendingPathComponent("oversized.entitlements")
        try Data(repeating: 32, count: 256 * 1024 + 1).write(to: file)
        XCTAssertThrowsError(try model.setEntitlements(from: file)) { XCTAssertTrue($0.localizedDescription.contains("256 KiB")) }
        XCTAssertNil(model.customEntitlements); XCTAssertNil(model.preview)
    }
    func testProductionAppAndProbeBothRefuseInvalidCMSWithoutWeakeningUnknownTrust() async throws {
        var invalid = FixtureData.profileWildcardAll
        invalid[invalid.count - 1] ^= 1
        guard case .invalid = ProfileTrust.evaluate(invalid) else { return XCTFail("tampered CMS control must be invalid") }
        _ = try store.importProfile(invalid)
        try await select()
        await model.prepareForSigning()?.value
        XCTAssertNil(model.preview); XCTAssertTrue(model.errorText?.contains("CMS signature invalid") == true)
        let output = root.appendingPathComponent("probe.ipa"), cert = try XCTUnwrap(store.certificates().first)
        let source = fixture, credentialStore = store!, work = root!
        do {
            try await Task.detached {
                try IdentityTester.signProbe(source, store: credentialStore, certificateID: cert.id, certificateTeamID: cert.teamID,
                    output: output, workDirectory: work, cancellation: SigningCancellation())
            }.value
            XCTFail("invalid profile must not create a probe")
        } catch { XCTAssertTrue(error.localizedDescription.contains("CMS signature invalid")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testUnknownProfilePinFailsPreparationAndKeepsUnsignedArtifact() async throws {
        try await select(); model.bundleProfiles["missing.appex"] = profile
        await model.prepareForSigning()?.value
        XCTAssertNil(model.preview); XCTAssertNil(model.report)
        XCTAssertTrue(model.errorText?.contains("unknown bundle path") == true)
        XCTAssertEqual(library.unsigned.count, 1)
    }
}

/// The unsigned Simulator host has no persistent Keychain access group (-34018). This seam replaces
/// custody only: PKCS#12 decoding, SecIdentity/SecKey signatures and the complete IPA engine remain real.
private final class FixtureIdentities: IdentityKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [UUID: SecIdentity] = [:]
    func store(identity: SecIdentity, id: UUID) throws { lock.withLock { identities[id] = identity } }
    func identity(id: UUID) throws -> SecIdentity {
        try lock.withLock {
            guard let value = identities[id] else { throw CredentialError.notFound }
            return value
        }
    }
    func remove(id: UUID) throws { _ = lock.withLock { identities.removeValue(forKey: id) } }
}
