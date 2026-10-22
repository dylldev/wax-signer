#if !SWIFT_PACKAGE && canImport(UIKit)
import CredentialKit
import IPAKit
import Security
import XCTest
@testable import LocalIPASigner

@MainActor
final class SigningModelTests: XCTestCase {
    private var work: URL!
    private var model: SigningModel!

    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("wax-model-tests-\(UUID().uuidString)")
        let store = try CredentialStore(directory: work, keychain: ModelTestKeychain())
        let cert = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        try store.importProfile(FixtureData.profileWildcardAll)
        model = SigningModel(credentials: CredentialsModel(store: store))
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
