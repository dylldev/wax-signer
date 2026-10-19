import Combine
import InstallKit
import XCTest
@testable import LocalIPASigner

private struct SessionSecrets: SecretStore {
    func load() -> Data? { Data(String(repeating: "t", count: 40).utf8) }
    func save(_ data: Data) throws {}
    func delete() {}
}
private actor SessionGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { open = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
private struct ImmediatePublisher: InstallHost {
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
    }
}
private actor SuspendedPublisher: InstallHost {
    let started: XCTestExpectation
    let gate = SessionGate()
    private var progress: (@Sendable (Double) -> Void)?
    init(_ started: XCTestExpectation) { self.started = started }
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        self.progress = progress; started.fulfill()
        // Intentionally ignores cancellation: the coordinator must suppress a stale/noncooperative host.
        await gate.wait()
        progress(0.8)
        return URL(string: "itms-services://?action=download-manifest&url=https://old.example/manifest")!
    }
    func emit(_ fraction: Double) { progress?(fraction) }
    func finish() async { await gate.release() }
}

@MainActor
final class OTASessionOutcomeTests: XCTestCase {
    private var root: URL!
    private var previous: [String: Any] = [:]
    private let keys = ["installHost", "otaServer", "certificateFeed", "s3Endpoint", "s3Bucket", "s3Region"]
    override func setUpWithError() throws {
        for key in keys { if let value = UserDefaults.standard.object(forKey: key) { previous[key] = value } }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("session-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artifact)
    }
    override func tearDownWithError() throws {
        for key in keys { UserDefaults.standard.set(previous[key], forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }
    private var artifact: URL { root.appendingPathComponent("retained.ipa") }
    private func model(phone: ((URL) async throws -> OTAInstallModel.PreparedHost)? = nil,
                       server: ((OTAEndpoint, String) async throws -> OTAInstallModel.PreparedHost)? = nil) -> OTAInstallModel {
        let model = OTAInstallModel(store: SessionSecrets(), bucketStore: SessionSecrets(),
            cleanupStore: BucketCleanupStore(file: root.appendingPathComponent("journal")), sweepOnStart: false,
            preparePhone: phone, prepareServer: server ?? { _, _ in .init(publisher: ImmediatePublisher()) })
        model.hostKind = .server; model.serverText = "https://fixture.example"
        return model
    }
    private func upload(_ model: OTAInstallModel, _ session: OTAInstallModel.Session? = nil) async -> URL? {
        await model.upload(ipa: artifact, bundleIdentifier: "test", version: "1", title: "Test", session: session)
    }
    private func assertArtifact(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: artifact), Data([1, 2, 3]), file: file, line: line)
    }

    func testReservationIsBusyBeforeAnyAwaitAndRejectsSecondOwner() throws {
        let model = model(), session = try model.reserve()
        XCTAssertEqual(model.state, .preparing); XCTAssertFalse(model.canInstall)
        XCTAssertThrowsError(try model.reserve()) { XCTAssertTrue($0.localizedDescription.contains("active")) }
        model.release(session); XCTAssertTrue(model.canInstall)
    }
    func testAlreadyCanceledCallerCannotLeakAReservationOrReportRemoteCompletion() async throws {
        let model = model()
        let canceled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await self.upload(model)
        }
        let link = await canceled.value; XCTAssertNil(link); XCTAssertNil(model.activeSession); XCTAssertEqual(model.state, .idle)
        let session = try model.reserve(); _ = await upload(model, session)
        let completion = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.finishPhoneTransfer(session: session)
        }
        let delivered = await completion.value; XCTAssertFalse(delivered); XCTAssertNil(model.activeSession); try assertArtifact()
    }
    func testDelayedPhoneReadinessCannotBeReplacedByAnIdentityTest() async throws {
        let entered = expectation(description: "preparation"), ready = SessionGate()
        let model = model(phone: { _ in entered.fulfill(); await ready.wait(); return .init(publisher: ImmediatePublisher()) })
        model.hostKind = .phone; model.certificateFeedText = "https://feed.example/cert.json"
        let upload = Task { await self.upload(model) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(model.state, .preparing)
        let tester = IdentityTester()
        await tester.run(identityID: UUID(), fingerprint: "fixture", ota: model,
                         sign: { XCTFail("busy installation must refuse signing"); throw CancellationError() }, detected: { false }, open: { _ in XCTFail() })
        guard case .problem(let text) = tester.state else { return XCTFail("expected explicit busy result") }
        XCTAssertTrue(text.contains("active")); XCTAssertEqual(model.state, .preparing)
        await ready.release(); let link = await upload.value; XCTAssertNotNil(link)
        model.reset(); try assertArtifact()
    }
    func testCancelDuringReadinessStopsOnlyOldHostAndCannotPublish() async throws {
        let entered = expectation(description: "preparation"), ready = SessionGate()
        var stops = 0
        let model = model(phone: { _ in entered.fulfill(); await ready.wait(); return .init(publisher: ImmediatePublisher(), stop: { stops += 1 }) })
        model.hostKind = .phone; model.certificateFeedText = "https://feed.example/cert.json"
        let old = Task { await self.upload(model) }
        await fulfillment(of: [entered], timeout: 5)
        model.cancelActive(); model.hostKind = .server
        let newer = try model.reserve(); let link = await upload(model, newer); XCTAssertNotNil(link)
        await ready.release(); let stale = await old.value; XCTAssertNil(stale)
        XCTAssertTrue(model.owns(newer)); XCTAssertEqual(model.state, .handedToiOS); XCTAssertEqual(stops, 1)
        model.release(newer); try assertArtifact()
    }
    func testParentCancellationReleasesDelayedPreparationBeforeItReturns() async throws {
        let entered = expectation(description: "preparation"), released = expectation(description: "reservation released"), ready = SessionGate()
        let model = model(server: { _, _ in entered.fulfill(); await ready.wait(); return .init(publisher: ImmediatePublisher()) })
        let subscription = model.$activeSession.dropFirst().sink { if $0 == nil { released.fulfill() } }
        defer { subscription.cancel() }
        let task = Task { await self.upload(model) }
        await fulfillment(of: [entered], timeout: 5); task.cancel()
        await fulfillment(of: [released], timeout: 5)
        XCTAssertTrue(model.canInstall)
        await ready.release(); let link = await task.value; XCTAssertNil(link); try assertArtifact()
    }
    func testServerConfigurationAndTokenAreCapturedAtReservation() async throws {
        var seen: (String, String)?
        let model = model(server: { endpoint, token in seen = (endpoint.base.host!, token); return .init(publisher: ImmediatePublisher()) })
        let session = try model.reserve()
        model.serverText = "https://changed.example"; model.hostKind = .phone; model.forgetToken()
        let link = await upload(model, session); XCTAssertNotNil(link)
        XCTAssertEqual(seen?.0, "fixture.example"); XCTAssertEqual(seen?.1, String(repeating: "t", count: 40))
        let completed = await model.finishPhoneTransfer(session: session)
        XCTAssertTrue(completed); XCTAssertNil(model.activeSession)
    }
    func testPhoneFinishUsesOriginalHostAfterSettingsChange() async throws {
        let waiting = expectation(description: "own delivery"), gate = SessionGate()
        var stops = 0
        let model = model(phone: { _ in .init(publisher: ImmediatePublisher(), stop: { stops += 1 }, wait: { _ in waiting.fulfill(); await gate.wait(); return true }) })
        model.hostKind = .phone; model.certificateFeedText = "https://feed.example/cert.json"
        let session = try model.reserve(); let link = await upload(model, session); XCTAssertNotNil(link)
        model.hostKind = .server
        let finished = Task { await model.finishPhoneTransfer(session: session) }
        await fulfillment(of: [waiting], timeout: 5)
        XCTAssertTrue(model.owns(session)); XCTAssertEqual(stops, 0)
        await gate.release(); let delivered = await finished.value
        XCTAssertTrue(delivered); XCTAssertEqual(stops, 1); XCTAssertNil(model.activeSession)
    }
    func testStaleDeliveryCompletionDoesNotStopNewHost() async throws {
        let waiting = expectation(description: "old delivery"), gate = SessionGate()
        var stopCount = 0, prepared = 0
        let model = model(phone: { _ in
            prepared += 1
            if prepared == 1 { return .init(publisher: ImmediatePublisher(), stop: { stopCount += 1 }, wait: { _ in waiting.fulfill(); await gate.wait(); return true }) }
            return .init(publisher: ImmediatePublisher(), stop: { stopCount += 100 })
        })
        model.hostKind = .phone; model.certificateFeedText = "https://feed.example/cert.json"
        let old = try model.reserve(); _ = await upload(model, old)
        let finished = Task { await model.finishPhoneTransfer(session: old) }
        await fulfillment(of: [waiting], timeout: 5); model.cancel(old)
        let new = try model.reserve(); _ = await upload(model, new)
        await gate.release(); let delivered = await finished.value
        XCTAssertFalse(delivered); XCTAssertEqual(stopCount, 1); XCTAssertTrue(model.owns(new)); XCTAssertEqual(model.state, .handedToiOS)
        model.release(new); XCTAssertEqual(stopCount, 101); try assertArtifact()
    }
    func testStaleUploadProgressAndCompletionCannotReviveCanceledState() async throws {
        let entered = expectation(description: "old upload"), oldPublisher = SuspendedPublisher(entered)
        var count = 0
        let model = model(server: { _, _ in count += 1; return .init(publisher: count == 1 ? oldPublisher : ImmediatePublisher()) })
        let old = try model.reserve(), oldUpload = Task { await self.upload(model, old) }
        await fulfillment(of: [entered], timeout: 5); model.cancel(old)
        let new = try model.reserve(); _ = await upload(model, new)
        await oldPublisher.emit(0.2); await oldPublisher.finish()
        let stale = await oldUpload.value; XCTAssertNil(stale)
        XCTAssertEqual(model.state, .handedToiOS); XCTAssertTrue(model.owns(new)); try assertArtifact()
        model.release(new)
    }
    func testLateCleanupNoteCannotReplaceEditedConfigurationAndFailedRecordIsKept() async throws {
        let entered = expectation(description: "old destination cleanup"), gate = SessionGate()
        let storage = BucketCleanupStore(file: root.appendingPathComponent("journal"))
        let credentials = S3Credentials(accessKey: "fixture", secretKey: "fixture", region: "auto", endpoint: URL(string: "https://old.example")!)
        let record = try BucketCleanupRecord(sessionID: "ABCDEFGHIJKLMNOPQRSTUV", scope: BucketCleanupScope(credentials: credentials, bucket: "old"))
        try storage.put(record)
        let model = OTAInstallModel(store: SessionSecrets(), bucketStore: SessionSecrets(), cleanupStore: storage, sweepOnStart: false,
            cleanup: { _, _, _ in entered.fulfill(); await gate.wait(); throw CancellationError() })
        let task = Task { await model.sweepBucket(credentials: credentials, bucket: "old") }
        await fulfillment(of: [entered], timeout: 5)
        model.bucketName = "new"; XCTAssertNil(model.bucketNote)
        await gate.release(); await task.value
        XCTAssertNil(model.bucketNote); XCTAssertEqual(try storage.records(), [record]); try assertArtifact()
    }
    func testOnlyOneUploadAndOneCompletionAreAllowedPerSession() async throws {
        let model = model(), session = try model.reserve()
        _ = await upload(model, session)
        let repeated = await upload(model, session); XCTAssertNil(repeated)
        let first = await model.finishPhoneTransfer(session: session)
        let second = await model.finishPhoneTransfer(session: session)
        XCTAssertTrue(first); XCTAssertFalse(second); XCTAssertEqual(model.state, .handedToiOS)
    }
    func testIdentityReservationBlocksRealInstallDuringSigningAndCancelRetainsOutput() async throws {
        let model = model(), tester = IdentityTester(), entered = expectation(description: "signing"), gate = SessionGate()
        let signed = artifact
        let task = Task { await tester.run(identityID: UUID(), fingerprint: "fixture", ota: model, sign: {
            entered.fulfill(); await gate.wait(); return signed
        }, detected: { false }, record: { _, _ in XCTFail("canceled tests cannot record results") }, open: { _ in XCTFail("cannot open a canceled test") }) }
        await fulfillment(of: [entered], timeout: 5)
        let realInstall = await upload(model); XCTAssertNil(realInstall)
        XCTAssertEqual(tester.state, .signing)
        tester.cancel(); XCTAssertFalse(tester.isRunning); XCTAssertNil(model.activeSession)
        let new = try model.reserve()
        await gate.release(); await task.value
        XCTAssertTrue(model.owns(new)); XCTAssertEqual(tester.retainedArtifacts, [artifact])
        guard case .problem(let text) = tester.state else { return XCTFail("expected cancellation") }
        XCTAssertTrue(text.contains("canceled")); try assertArtifact(); model.release(new)
    }
    func testCancelDuringProbePollingSuppressesRecordAndReleasesOnlyItsSession() async throws {
        let model = model(), tester = IdentityTester(), entered = expectation(description: "poll"), gate = SessionGate(), signed = artifact
        var opens = 0
        let task = Task { await tester.run(identityID: UUID(), fingerprint: "fixture", ota: model, sign: { signed }, detected: { false },
            record: { _, _ in XCTFail("canceled poll cannot write result") }, pause: { entered.fulfill(); await gate.wait() }, open: { _ in opens += 1 }) }
        await fulfillment(of: [entered], timeout: 5); XCTAssertEqual(opens, 1)
        tester.cancel(); let new = try model.reserve()
        await gate.release(); await task.value
        XCTAssertTrue(model.owns(new)); XCTAssertFalse(tester.isRunning); try assertArtifact(); model.release(new)
    }
    func testFailedProbeUploadRetainsSignedArtifactAndCannotRecordOrOpen() async throws {
        struct Offline: LocalizedError { var errorDescription: String? { "Fixture offline" } }
        let model = model(server: { _, _ in throw Offline() }), tester = IdentityTester(), signed = artifact
        await tester.run(identityID: UUID(), fingerprint: "fixture", ota: model, sign: { signed }, detected: { false },
            record: { _, _ in XCTFail() }, open: { _ in XCTFail() })
        guard case .problem(let text) = tester.state else { return XCTFail("expected upload failure") }
        XCTAssertTrue(text.contains("offline")); XCTAssertEqual(tester.retainedArtifacts, [artifact]); XCTAssertNil(model.activeSession); try assertArtifact()
    }
    func testProbeDetectionIsRecordedForItsOwnIdentityAndReservationIsReleased() async throws {
        let model = model(), tester = IdentityTester(), signed = artifact
        var checks = 0, observations: [String] = []
        await tester.run(identityID: UUID(), fingerprint: "own-fingerprint", ota: model, sign: { signed }, detected: { checks += 1; return checks > 1 },
            record: { result, fingerprint in XCTAssertEqual(result, .installed); observations.append(fingerprint) }, open: { _ in })
        XCTAssertEqual(observations, ["own-fingerprint"]); XCTAssertNil(model.activeSession); XCTAssertFalse(tester.isRunning)
        guard case .finished(_, let message) = tester.state else { return XCTFail("expected observation") }
        XCTAssertTrue(message.contains("detected")); try assertArtifact()
    }
}
