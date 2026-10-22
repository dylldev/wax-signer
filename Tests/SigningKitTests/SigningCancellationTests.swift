import CredentialKit
import IPAKit
import XCTest
@testable import SigningKit

final class SigningCancellationTests: XCTestCase {
    private var root: URL!
    private var output: URL { root.appendingPathComponent("previous-good.ipa") }
    private let prior = Data("existing output must survive".utf8)
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sign-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try prior.write(to: output)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func sign(_ cancellation: SigningCancellation, progress: ((SigningProgress) -> Void)? = nil) throws -> IPASigningOutcome {
        let credentials = try TestCredentials()
        var options = SigningOptions(); options.cancellation = cancellation
        return try IPASigner.sign(ipa: Fixtures.ipa, identity: credentials.signer, certificateTeamID: credentials.loaded.teamID,
            profiles: ProfileSet(single: .parse(FixtureData.profileWildcardAll)), options: options, output: output, workDirectory: root, progress: progress)
    }
    private func assertPriorAndCleanup(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: output), prior, file: file, line: line)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix("sign-") }), file: file, line: line)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasSuffix(".part") }), file: file, line: line)
    }
    func testAlreadyCanceledOperationPreservesExistingOutput() throws {
        let token = SigningCancellation(); token.cancel()
        XCTAssertThrowsError(try sign(token)) { XCTAssertTrue($0 is CancellationError) }
        try assertPriorAndCleanup()
    }
    func testCancellationAtExtractionSigningAndVerificationBoundariesPreservesOutput() throws {
        let source = try Data(contentsOf: Fixtures.ipa)
        for stage in ["Unpacking…", "Signing…", "Checking the signature…"] {
            let token = SigningCancellation()
            XCTAssertThrowsError(try sign(token) { if $0.message == stage { token.cancel() } }) { XCTAssertTrue($0 is CancellationError) }
            try assertPriorAndCleanup(); XCTAssertEqual(try Data(contentsOf: Fixtures.ipa), source)
        }
    }
    func testCancellationDuringStagedPackingCannotPublishOverGoodArtifact() throws {
        let token = SigningCancellation()
        XCTAssertThrowsError(try sign(token) { if $0.message == "Packing…", $0.fraction > 0.99 { token.cancel() } }) {
            XCTAssertTrue($0 is CancellationError)
        }
        try assertPriorAndCleanup()
    }
    func testPublicationBarrierSettlesEvenIfCancellationArrivesAfterIt() throws {
        let token = SigningCancellation(); try token.claim(); try token.beginPublication()
        token.cancel(); XCTAssertNoThrow(try token.check())
    }
    func testCancellationBeforePublicationBarrierIsRejected() throws {
        let token = SigningCancellation(); try token.claim(); token.cancel()
        XCTAssertThrowsError(try token.beginPublication()) { XCTAssertTrue($0 is CancellationError) }
    }
    func testSuccessfulOutputIsKeptAndTokenCannotBeReusedForAnotherOperation() throws {
        let token = SigningCancellation(), result = try sign(token)
        XCTAssertTrue(result.selfCheck.passed); let signed = try Data(contentsOf: output)
        token.cancel(); XCTAssertEqual(try Data(contentsOf: output), signed)
        XCTAssertThrowsError(try sign(token)) { XCTAssertTrue($0.localizedDescription.contains("one IPA operation")) }
        XCTAssertEqual(try Data(contentsOf: output), signed); XCTAssertTrue(try IPAInspector.inspect(url: output).hasCodeSignature)
    }
    func testCancellationAfterASynchronousKeyOperationStopsBeforeNextWrite() throws {
        struct Identity: CodeSigningIdentity {
            let base: SecurityFrameworkIdentity
            let token: SigningCancellation
            var certificateChainDER: [Data] { base.certificateChainDER }
            func signRSAPKCS1SHA256(_ message: Data) throws -> Data {
                let signed = try base.signRSAPKCS1SHA256(message)
                token.cancel() // the complete key operation returns; the next safe boundary must refuse
                return signed
            }
        }
        let token = SigningCancellation(), credentials = try TestCredentials()
        var options = SigningOptions(); options.cancellation = token
        XCTAssertThrowsError(try IPASigner.sign(ipa: Fixtures.ipa, identity: Identity(base: credentials.signer, token: token),
            certificateTeamID: credentials.loaded.teamID, profiles: ProfileSet(single: .parse(FixtureData.profileWildcardAll)), options: options,
            output: output, workDirectory: root)) { XCTAssertTrue($0 is CancellationError) }
        try assertPriorAndCleanup()
    }
    func testDispatchWorkersObserveOwnerCancellationWithoutASwiftTask() {
        let token = SigningCancellation(), complete = expectation(description: "worker observes cancellation")
        token.cancel()
        DispatchQueue.global().async {
            do { try token.check(); XCTFail("must observe explicit owner token") }
            catch { XCTAssertTrue(error is CancellationError) }
            complete.fulfill()
        }
        wait(for: [complete], timeout: 5)
    }
}
