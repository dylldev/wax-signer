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
        let preparation = try XCTUnwrap(model.sign())
        await preparation.value
        XCTAssertTrue(try XCTUnwrap(model.passportReport).canContinue)
        let task = try XCTUnwrap(model.sign())
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
        let preparation = try XCTUnwrap(model.sign())
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
        let task = try XCTUnwrap(model.sign())
        model.edits.displayName = "Changed during preparation"
        await task.value
        XCTAssertNil(model.passportReport, "The old input snapshot must not reappear after invalidation")
        XCTAssertNil(model.busyMessage)
        XCTAssertNil(model.report)
    }

    func testReviewedPreparationContinuesToASignedResult() async throws {
        let preparation = try XCTUnwrap(model.sign())
        await preparation.value
        XCTAssertTrue(try XCTUnwrap(model.passportReport).canContinue)
        let signing = try XCTUnwrap(model.sign())
        await signing.value
        let report = try XCTUnwrap(model.report, model.errorText ?? "No signing result")
        XCTAssertTrue(report.checkFailures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.output.path))
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
        let preparation = try XCTUnwrap(signer.sign()); await preparation.value
        XCTAssertFalse(try XCTUnwrap(signer.passportReport).findings.contains { $0.id == "identity-continuity" }, "nothing to compare with yet")
        let signing = try XCTUnwrap(signer.sign()); await signing.value
        XCTAssertTrue(signer.shelfSaveState.confirmedSaved, signer.errorText ?? "\(signer.shelfSaveState)")

        let entry = try XCTUnwrap(library.signed.first)
        let record = try XCTUnwrap(entry.record, "a Wax-signed shelf copy keeps its signing record")
        XCTAssertEqual(record.finalBundleID, entry.bundleID)
        XCTAssertEqual(record.certificateSHA1, certificate.sha1Fingerprint)
        XCTAssertFalse(record.profiles.isEmpty)

        signer.clearResult()
        let next = try XCTUnwrap(signer.sign()); await next.value
        let row = try XCTUnwrap(signer.passportReport?.findings.first { $0.id == "identity-continuity" })
        XCTAssertEqual(row.status, .pass, row.detail)
        XCTAssertTrue(row.title.contains("Updates"), row.title)
        signer.discardPreflight()
    }

    func testChangingStrictEntitlementsDiscardsACachedPreparation() async throws {
        let preparation = try XCTUnwrap(model.sign())
        await preparation.value
        XCTAssertNotNil(model.passportReport)
        model.strictEntitlements = true          // the reviewed check was made under the permissive policy
        XCTAssertNil(model.passportReport, "a preparation made under another entitlement policy must not be signed")
        XCTAssertFalse(model.runningSign)
        let again = try XCTUnwrap(model.sign(), "a fresh preparation must be possible after the policy change")
        await again.value
        XCTAssertNotNil(model.passportReport)
    }

    func testAnotherIPACannotReplaceTheInputWhileSigningIsBusy() async throws {
        let task = try XCTUnwrap(model.sign())
        let other = work.appendingPathComponent("other.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: other)
        model.picked(ipa: other)
        XCTAssertNotNil(model.ipaInfo, "A busy signing run must retain its chosen input")
        await task.value
        XCTAssertNotNil(model.passportReport)
    }

    func testMinimumIOSFindingUsesThePreparedAppEdits() async throws {
        model.edits.minimumOSVersion = "99.0"
        let task = try XCTUnwrap(model.sign())
        await task.value
        let finding = try XCTUnwrap(model.passportReport?.findings.first { $0.id == "minimum-ios" })
        XCTAssertEqual(finding.status, .warning)
        XCTAssertTrue(finding.detail.contains("99.0"))
    }

    func testSecondSignCannotStartWhilePreparing() async throws {
        let task = try XCTUnwrap(model.sign())
        XCTAssertNil(model.sign(), "Only one preparation may run at a time")
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
