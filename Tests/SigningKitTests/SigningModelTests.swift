#if !SWIFT_PACKAGE && canImport(UIKit)
import CredentialKit
import InstallKit
import IPAKit
import Security
import SigningKit
import UIKit
import XCTest
@testable import LocalIPASigner

@MainActor
final class SigningModelTests: XCTestCase {
    private var work: URL!
    private var model: SigningModel!
    private var expireBackground: (() -> Void)?
    private var credentials: CredentialsModel!
    private var background: BackgroundJob!
    private var certificate: CertificateInfo!

    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("wax-model-tests-\(UUID().uuidString)")
        let store = try CredentialStore(directory: work, keychain: ModelTestKeychain())
        let cert = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        try store.importProfile(FixtureData.profileWildcardAll)
        let background = BackgroundJob(system: .init(beginGrace: { _, expired in
            self.expireBackground = expired
            return UIBackgroundTaskIdentifier(rawValue: 1)
        }, endGrace: { _ in }, requestContinued: { _ in }, cancelContinued: {}, isInBackground: { true }))
        credentials = CredentialsModel(store: store); self.background = background; certificate = cert
        model = SigningModel(credentials: credentials, background: background)
        let input = work.appendingPathComponent("input.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: input)
        model.picked(ipa: input)
        for _ in 0..<500 where model.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.ipaInfo, model.errorText ?? "IPA not loaded")
        model.certificateID = cert.id
    }

    override func tearDown() async throws {
        model.discardPreflight()
        try? FileManager.default.removeItem(at: work)
        model = nil
    }

    private func extensionSigner(profile: Data = FixtureData.profileExactTestApp,
                                 p12: Data = FixtureData.p12ValidLegacy) async throws -> (SigningModel, LibraryModel, URL) {
        let directory = work.appendingPathComponent(UUID().uuidString)
        let store = try CredentialStore(directory: directory.appendingPathComponent("Credentials"), keychain: ModelTestKeychain())
        let cert = try store.importCertificate(p12: p12, password: FixtureData.password)
        try store.importProfile(profile)
        let library = LibraryModel(library: IPALibrary(root: directory.appendingPathComponent("Shelf")), announce: { _ in })
        let saved = try await library.fileNow(Fixtures.ipa, info: IPAInspector.inspect(url: Fixtures.ipa))
        let source = library.url(for: saved.entry)
        let signer = SigningModel(credentials: CredentialsModel(store: store), library: library, background: background)
        signer.use(saved.entry)
        for _ in 0..<500 where signer.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(signer.ipaInfo, signer.errorText ?? "IPA not loaded")
        let oldKeep = UserDefaults.standard.object(forKey: "keepBundleID")
        let oldRewrite = UserDefaults.standard.object(forKey: "rewriteBundleID")
        signer.keepBundleID = false; signer.rewriteBundleID = false
        UserDefaults.standard.set(oldKeep, forKey: "keepBundleID")
        UserDefaults.standard.set(oldRewrite, forKey: "rewriteBundleID")
        signer.edits = AppEdits()
        signer.certificateID = cert.id
        return (signer, library, source)
    }

    func testExtensionMismatchOffersExplicitOutputOnlyRecovery() async throws {
        let (signer, library, source) = try await extensionSigner()
        let original = try Data(contentsOf: source)
        let task = try XCTUnwrap(signer.sign()); await task.value

        XCTAssertEqual(signer.errorText, "Bundle PlugIns/TestExt.appex has identifier dev.localsigner.testapp.TestExt, which the profile's application identifier FIXT123456.dev.localsigner.testapp does not permit.")
        XCTAssertEqual(signer.recovery, .removeAppExtensions(bundle: "PlugIns/TestExt.appex"))
        XCTAssertNil(signer.passportReport)
        XCTAssertNil(signer.report)
        XCTAssertFalse(signer.edits.removeExtensions)
        XCTAssertTrue(library.signed.isEmpty)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: library.storage.root, includingPropertiesForKeys: nil))
        XCTAssertEqual(files.compactMap { $0 as? URL }.filter { $0.pathExtension == "ipa" }.count, 1, "Only the original IPA may exist after refusal")

        signer.removeUnsupportedExtensions()
        XCTAssertTrue(signer.edits.removeExtensions)
        XCTAssertNil(signer.recovery)
        XCTAssertNil(signer.errorText)
        XCTAssertNil(signer.passportReport)
        XCTAssertNil(signer.report)
        XCTAssertFalse(signer.runningSign)
        XCTAssertTrue(library.signed.isEmpty, "Recovery requires another explicit Sign")
        XCTAssertEqual(try Data(contentsOf: source), original)

        let retry = try XCTUnwrap(signer.sign()); await retry.value
        let report = try XCTUnwrap(signer.report, signer.errorText ?? "No signed result")
        XCTAssertTrue(report.checkFailures.isEmpty)
        XCTAssertTrue(signer.shelfSaveState.confirmedSaved)
        XCTAssertEqual(library.signed.count, 1)
        let outputNames = try IPAExtractor.extract(ipa: report.output, to: work.appendingPathComponent("recovered-output"))
        XCTAssertFalse(outputNames.contains { $0.contains(".appex/") })
        XCTAssertEqual(try Data(contentsOf: source), original, "The retained original must remain byte-identical")
        let sourceNames = try IPAExtractor.extract(ipa: source, to: work.appendingPathComponent("retained-original"))
        XCTAssertTrue(sourceNames.contains { $0.contains("PlugIns/TestExt.appex/") })
    }

    func testExtensionRecoveryClearsOnInputChangesAndNewRuns() async throws {
        let (signer, _, _) = try await extensionSigner()
        for change in 0..<4 {
            let task = try XCTUnwrap(signer.sign()); await task.value
            XCTAssertNotNil(signer.recovery)
            switch change {
            case 0: signer.edits.displayName = "Changed"
            case 1: signer.profileChoice = UUID(); signer.profileChoice = nil
            case 2: let id = signer.certificateID; signer.certificateID = nil; signer.certificateID = id
            default: signer.strictEntitlements.toggle()
            }
            XCTAssertNil(signer.recovery)
            XCTAssertNil(signer.errorText)
        }
        signer.strictEntitlements = false
        let failed = try XCTUnwrap(signer.sign()); await failed.value
        XCTAssertNotNil(signer.recovery)
        let cancellation = SigningCancellation(); cancellation.cancel()
        let retry = try XCTUnwrap(signer.sign(cancellation: cancellation))
        XCTAssertNil(signer.recovery, "A new attempt must discard the previous recovery")
        await retry.value
        XCTAssertNil(signer.recovery, "Cancellation must not reuse an extension recovery")

        let again = try XCTUnwrap(signer.sign()); await again.value
        XCTAssertNotNil(signer.recovery)
        let malformed = work.appendingPathComponent("malformed.ipa")
        try Data("not an IPA".utf8).write(to: malformed)
        signer.picked(ipa: malformed)
        XCTAssertNil(signer.recovery)
        for _ in 0..<500 where signer.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(signer.errorText)
        XCTAssertNil(signer.recovery)
    }

    func testMainAppAndCertificateFailuresDoNotOfferExtensionRemoval() async throws {
        for (profile, p12, expected) in [
            (FixtureData.profileValidBER, FixtureData.p12ValidLegacy, "Bundle . has identifier"),
            (FixtureData.profileExactTestApp, FixtureData.p12SecondIdentity, "does not list the signing certificate")
        ] {
            let (signer, library, _) = try await extensionSigner(profile: profile, p12: p12)
            let task = try XCTUnwrap(signer.sign()); await task.value
            XCTAssertTrue(signer.errorText?.contains(expected) == true, signer.errorText ?? "No error")
            XCTAssertNil(signer.recovery)
            signer.removeUnsupportedExtensions()
            XCTAssertFalse(signer.edits.removeExtensions)
            XCTAssertNil(signer.report)
            XCTAssertNil(signer.passportReport)
            XCTAssertTrue(library.signed.isEmpty)
        }
    }

    func testRecoveryClassificationRequiresTypedExtensionIdentifierMismatch() {
        XCTAssertEqual(SigningModel.recovery(for: .appIdentifierMismatch(bundle: "PlugIns/homewidget.appex", id: "app.widget", profile: "TEAM.app")),
                       .removeAppExtensions(bundle: "PlugIns/homewidget.appex"))
        let errors: [SigningError] = [
            .appIdentifierMismatch(bundle: ".", id: "app", profile: "TEAM.other"),
            .appIdentifierMismatch(bundle: "Watch/WatchApp.app", id: "app.watch", profile: "TEAM.app"),
            .appIdentifierMismatch(bundle: "Watch/WatchApp.app/PlugIns/WatchExt.appex", id: "app.watch.ext", profile: "TEAM.app"),
            .certificateExpired(.distantPast), .profileDoesNotListCertificate,
            .profileRejected(bundle: "PlugIns/homewidget.appex", profile: "Main", reason: "expired"),
            .noCompatibleProfile(bundle: "PlugIns/homewidget.appex", id: "app.widget", reasons: ["certificate not listed"]),
            .bundle("malformed input")
        ]
        for error in errors {
            XCTAssertNil(SigningModel.recovery(for: error), "\(error)")
        }
    }

    func testOneTapSigningProducesVerifiedSavedOutput() async throws {
        let library = LibraryModel(library: IPALibrary(root: work.appendingPathComponent("OneTapShelf")), announce: { _ in })
        let signer = SigningModel(credentials: credentials, library: library, background: background)
        let input = work.appendingPathComponent("one-tap.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: input)
        signer.picked(ipa: input)
        for _ in 0..<500 where signer.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(signer.ipaInfo, signer.errorText ?? "IPA not loaded")
        signer.certificateID = certificate.id

        let task = try XCTUnwrap(signer.sign())
        await task.value

        let report = try XCTUnwrap(signer.report, signer.errorText ?? "Signing stopped at a review instead of producing output")
        XCTAssertTrue(report.checkFailures.isEmpty)
        XCTAssertTrue(signer.shelfSaveState.confirmedSaved)
        XCTAssertEqual(library.signed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.output.path))
        XCTAssertNil(signer.passportReport)
        XCTAssertFalse(signer.runningSign)
    }

    func testOneTapSigningAndInstallReachesTheHost() async throws {
        struct Secrets: SecretStore {
            func load() -> Data? { Data(String(repeating: "t", count: 40).utf8) }
            func save(_ data: Data) throws {}
            func delete() {}
        }
        struct Publisher: InstallHost {
            func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
                URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
            }
        }
        let previousHost = UserDefaults.standard.object(forKey: "installHost")
        let previousServer = UserDefaults.standard.object(forKey: "otaServer")
        defer {
            UserDefaults.standard.set(previousHost, forKey: "installHost")
            UserDefaults.standard.set(previousServer, forKey: "otaServer")
        }
        let ota = OTAInstallModel(store: Secrets(), bucketStore: Secrets(),
                                  cleanupStore: BucketCleanupStore(file: work.appendingPathComponent("automatic-journal")),
                                  sweepOnStart: false, prepareServer: { _, _ in .init(publisher: Publisher()) })
        ota.hostKind = .server
        ota.serverText = "https://fixture.example"

        await model.signAndInstall(ota: ota, open: { _ in })

        XCTAssertNotNil(model.report, model.errorText ?? "No signed output")
        XCTAssertEqual(ota.state, .handedToiOS)
        XCTAssertNotNil(model.readyLink)
        XCTAssertNil(model.passportReport)
        XCTAssertFalse(model.installing)
    }

    func testAutomaticSigningCannotPublishAStaleResultAfterEditsChange() async throws {
        let task = try XCTUnwrap(model.sign())
        model.edits.displayName = "Changed during automatic signing"
        await task.value
        XCTAssertNil(model.report)
        XCTAssertNil(model.passportReport)
        XCTAssertFalse(model.runningSign)
    }

    func testBackgroundExpirationStopsAutomaticPreparation() async throws {
        expireBackground = nil
        let task = try XCTUnwrap(model.sign())
        try XCTUnwrap(expireBackground)()
        await task.value
        XCTAssertNil(model.report)
        XCTAssertNil(model.passportReport)
        XCTAssertFalse(model.runningSign)
        XCTAssertEqual(model.errorText, "Signing stopped before it finished. Try again with Wax open.")
    }

    func testCanceledPreparationCannotProduceAReview() async throws {
        let cancellation = SigningCancellation()
        cancellation.cancel()
        let task = try XCTUnwrap(model.sign(cancellation: cancellation))
        await task.value
        XCTAssertNil(model.passportReport)
        XCTAssertNotNil(model.errorText)
        XCTAssertFalse(model.runningSign)
    }

    func testBackgroundExpirationStopsSigningBeforePublication() async throws {
        let preparation = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await preparation.value
        XCTAssertTrue(try XCTUnwrap(model.passportReport).canContinue)
        let task = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        try XCTUnwrap(expireBackground)()
        await task.value
        XCTAssertNil(model.report, "Expired work must stop before it publishes a signed output")
        XCTAssertEqual(model.errorText, "Signing stopped before it finished. Try again with Wax open.")
        XCTAssertFalse(model.runningSign)
    }

    func testBackgroundExpirationDuringSignAndInstallStopsSigningToo() async throws {
        struct Secrets: SecretStore {
            func load() -> Data? { Data(String(repeating: "t", count: 40).utf8) }
            func save(_ data: Data) throws {}
            func delete() {}
        }
        struct Publisher: InstallHost {
            func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
                URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
            }
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "wax-install-expiry-\(UUID())"))
        let ota = OTAInstallModel(store: Secrets(), bucketStore: Secrets(),
                                  cleanupStore: BucketCleanupStore(file: work.appendingPathComponent("journal")), defaults: defaults,
                                  sweepOnStart: false, prepareServer: { _, _ in .init(publisher: Publisher()) })
        ota.hostKind = .server; ota.serverText = "https://fixture.example"
        let preparation = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await preparation.value
        XCTAssertTrue(try XCTUnwrap(model.passportReport).canContinue)
        expireBackground = nil
        let install = Task { await model.signAndInstall(ota: ota, open: { _ in XCTFail("an expired install must not open a link") }) }
        while expireBackground == nil { await Task.yield() }
        try XCTUnwrap(expireBackground)()
        await install.value
        XCTAssertNil(model.report, "Signing for an expired install must stop, not save a signed copy")
        XCTAssertFalse(model.runningSign)
        XCTAssertFalse(model.errorText?.contains("CancellationError") ?? false, model.errorText ?? "")
    }

    func testInputChangeDiscardsPreparationStillInFlight() async throws {
        let task = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        model.edits.displayName = "Changed during preparation"
        await task.value
        XCTAssertNil(model.passportReport, "The old input snapshot must not reappear after invalidation")
        XCTAssertNil(model.busyMessage)
        XCTAssertNil(model.report)
    }

    func testReviewedPreparationContinuesToASignedResult() async throws {
        let preparation = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await preparation.value
        XCTAssertTrue(try XCTUnwrap(model.passportReport).canContinue)
        let signing = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await signing.value
        let report = try XCTUnwrap(model.report, model.errorText ?? "No signing result")
        XCTAssertTrue(report.checkFailures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.output.path),
                      "Output: \(report.output.lastPathComponent); save state: \(String(describing: model.shelfSaveState))")
        XCTAssertNil(model.passportReport)
    }

    func testASignedCopyKeepsItsRecordAndTheNextPreparationComparesWithIt() async throws {
        let library = LibraryModel(library: IPALibrary(root: work.appendingPathComponent("Shelf")), announce: { _ in })
        let signer = SigningModel(credentials: credentials, library: library, background: background)
        let input = work.appendingPathComponent("again.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: input)
        signer.picked(ipa: input)
        for _ in 0..<500 where signer.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        signer.certificateID = certificate.id
        let preparation = try XCTUnwrap(signer.sign(reviewBeforeSigning: true)); await preparation.value
        XCTAssertFalse(try XCTUnwrap(signer.passportReport).findings.contains { $0.id == "identity-continuity" }, "nothing to compare with yet")
        let signing = try XCTUnwrap(signer.sign(reviewBeforeSigning: true)); await signing.value
        XCTAssertTrue(signer.shelfSaveState.confirmedSaved, signer.errorText ?? "\(signer.shelfSaveState)")

        let entry = try XCTUnwrap(library.signed.first)
        let record = try XCTUnwrap(entry.record, "a Wax-signed shelf copy keeps its signing record")
        XCTAssertEqual(record.finalBundleID, entry.bundleID)
        XCTAssertEqual(record.certificateSHA1, certificate.sha1Fingerprint)
        XCTAssertFalse(record.profiles.isEmpty)

        signer.clearResult()
        let next = try XCTUnwrap(signer.sign(reviewBeforeSigning: true)); await next.value
        let row = try XCTUnwrap(signer.passportReport?.findings.first { $0.id == "identity-continuity" })
        XCTAssertEqual(row.status, .pass, row.detail)
        XCTAssertTrue(row.title.contains("Updates"), row.title)
        signer.discardPreflight()
    }

    func testChangingStrictEntitlementsDiscardsACachedPreparation() async throws {
        let preparation = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await preparation.value
        XCTAssertNotNil(model.passportReport)
        model.strictEntitlements = true          // the reviewed check was made under the permissive policy
        XCTAssertNil(model.passportReport, "a preparation made under another entitlement policy must not be signed")
        XCTAssertFalse(model.runningSign)
        let again = try XCTUnwrap(model.sign(reviewBeforeSigning: true), "a fresh preparation must be possible after the policy change")
        await again.value
        XCTAssertNotNil(model.passportReport)
    }

    func testAnotherIPACannotReplaceTheInputWhileSigningIsBusy() async throws {
        let task = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        let other = work.appendingPathComponent("other.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: other)
        model.picked(ipa: other)
        XCTAssertNotNil(model.ipaInfo, "A busy signing run must retain its chosen input")
        await task.value
        XCTAssertNotNil(model.passportReport)
    }

    func testMinimumIOSFindingUsesThePreparedAppEdits() async throws {
        model.edits.minimumOSVersion = "99.0"
        let task = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        await task.value
        let finding = try XCTUnwrap(model.passportReport?.findings.first { $0.id == "minimum-ios" })
        XCTAssertEqual(finding.status, .warning)
        XCTAssertTrue(finding.detail.contains("99.0"))
    }

    func testSecondSignCannotStartWhilePreparing() async throws {
        let task = try XCTUnwrap(model.sign(reviewBeforeSigning: true))
        XCTAssertNil(model.sign(reviewBeforeSigning: true), "Only one preparation may run at a time")
        await task.value
        XCTAssertNotNil(model.passportReport)
    }
}

private final class ModelTestKeychain: IdentityKeychain, @unchecked Sendable {
    private var identities: [UUID: SecIdentity] = [:]
    func store(identity: SecIdentity, id: UUID) throws { identities[id] = identity }
    func identity(id: UUID) throws -> SecIdentity {
        guard let identity = identities[id] else { throw CredentialError.notFound }
        return identity
    }
    func remove(id: UUID) throws { identities[id] = nil }
}
#endif
