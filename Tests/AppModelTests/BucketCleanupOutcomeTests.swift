import InstallKit
import XCTest
@testable import LocalIPASigner

private struct EmptySecrets: SecretStore {
    func load() -> Data? { nil }; func save(_ data: Data) throws {}; func delete() {}
}
private actor CleanupCalls {
    var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
    func snapshot() -> [String] { ids }
}
private struct BucketTestSecrets: SecretStore {
    func load() -> Data? { try? JSONEncoder().encode(["a": "public-id", "s": "synthetic-key"]) }
    func save(_ data: Data) throws {}; func delete() {}
}
private final class BucketTransactionProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            try Self.handler?(request)
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.read(&bytes, maxLength: bytes.count) > 0 {}
            }
            let body = request.httpMethod == "GET" ? Data("<plist><dict/></plist>".utf8) : Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class BucketCleanupOutcomeTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var savedDefaults: [String: Any] = [:]
    private let settingKeys = ["installHost", "s3Endpoint", "s3Bucket", "s3Region"]
    private var journal: BucketCleanupStore { BucketCleanupStore(file: root.appendingPathComponent("journal.json")) }
    private var credentials: S3Credentials { S3Credentials(accessKey: "public-id", secretKey: "synthetic-key", region: "auto", endpoint: URL(string: "https://original.example")!) }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bucket-outcome-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for key in settingKeys { if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value } }
        suite = "bucket-tests-" + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws { for key in settingKeys { UserDefaults.standard.set(savedDefaults[key], forKey: key) }; defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    private func record(expires: Date? = nil) throws -> BucketCleanupRecord {
        var record = try BucketCleanupRecord(sessionID: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(22)), scope: BucketCleanupScope(credentials: credentials, bucket: "wax"))
        record.expiresAt = expires; return record
    }
    private func model(_ action: @escaping @Sendable (S3Credentials, String, String) async throws -> Void) -> OTAInstallModel {
        OTAInstallModel(store: EmptySecrets(), bucketStore: EmptySecrets(), cleanupStore: journal, defaults: defaults, sweepOnStart: false, cleanup: action)
    }
    func testCleanupFailureRetainsRecordAndRetryRemovesIt() async throws {
        let entry = try record(); try journal.put(entry)
        struct Rejected: Error {}
        let failed = model { _, _, _ in throw Rejected() }
        await failed.sweepBucket(credentials: credentials, bucket: "wax")
        XCTAssertEqual(try journal.records(), [entry]); XCTAssertTrue(failed.bucketNote?.contains("kept") == true)
        let calls = CleanupCalls(), retry = model { _, _, id in await calls.record(id) }
        await retry.sweepBucket(credentials: credentials, bucket: "wax")
        let ids = await calls.snapshot(); XCTAssertEqual(ids, [entry.sessionID]); XCTAssertTrue(try journal.records().isEmpty)
    }
    func testChangedDestinationAndAccessKeyNeverReceiveOldDeletion() async throws {
        let entry = try record(); try journal.put(entry)
        let model = model { _, _, _ in XCTFail("wrong destination must never receive DELETE") }
        var other = credentials; other.endpoint = URL(string: "https://new.example")!
        await model.sweepBucket(credentials: other, bucket: "wax")
        other = credentials; other.accessKey = "changed-access"
        await model.sweepBucket(credentials: other, bucket: "wax")
        await model.sweepBucket(credentials: credentials, bucket: "other-bucket")
        XCTAssertEqual(try journal.records(), [entry]); XCTAssertTrue(model.bucketNote?.contains("preserved") == true)
    }
    func testUnexpiredLinksAreKeptAndInterruptedPreparationIsRecovered() async throws {
        let live = try record(expires: Date().addingTimeInterval(3600)), interrupted = try record()
        try journal.put(live); try journal.put(interrupted)
        let calls = CleanupCalls(), model = model { _, _, id in await calls.record(id) }
        await model.sweepBucket(credentials: credentials, bucket: "wax")
        let ids = await calls.snapshot(); XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(try journal.records(), [live])
    }
    func testLegacyUnknownDestinationIsRetainedWithoutGuessing() async throws {
        let legacy = ["ABCDEFGHIJKLMNOPQRSTUV": 1.0]; defaults.set(legacy, forKey: "s3Pending")
        let model = model { _, _, _ in XCTFail("legacy destination is unknown") }
        await model.sweepBucket(credentials: credentials, bucket: "wax")
        XCTAssertEqual(defaults.dictionary(forKey: "s3Pending") as? [String: Double], legacy)
        XCTAssertTrue(model.bucketNote?.contains("no destination") == true)
    }
    func testCorruptedJournalNeverTriggersRemoteDeletionOrEmptyRewrite() async throws {
        let file = root.appendingPathComponent("journal.json"), data = Data("corrupt".utf8); try data.write(to: file)
        let model = model { _, _, _ in XCTFail("no trusted routing metadata") }
        await model.sweepBucket(credentials: credentials, bucket: "wax")
        XCTAssertEqual(try Data(contentsOf: file), data); XCTAssertTrue(model.bucketNote?.contains("preserved") == true)
    }
    private func uploadingModel() -> (OTAInstallModel, URLSession) {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BucketTransactionProtocol.self]
        let network = URLSession(configuration: config)
        let model = OTAInstallModel(store: EmptySecrets(), bucketStore: BucketTestSecrets(), cleanupStore: journal, defaults: defaults,
            sweepOnStart: false, bucketHost: { try S3Host(credentials: $0, bucket: $1, session: network) }, cleanup: { _, _, _ in })
        model.hostKind = .bucket; model.bucketEndpoint = credentials.endpoint.absoluteString; model.bucketName = "wax"; model.bucketRegion = "auto"
        return (model, network)
    }
    private func upload(_ model: OTAInstallModel) async throws -> URL? {
        let file = root.appendingPathComponent("synthetic.ipa"); try Data([1, 2, 3]).write(to: file)
        // Transport/transaction test, not a valid signed IPA or device-installation fixture.
        return await model.upload(ipa: file, bundleIdentifier: "test", version: "1", title: "Test")
    }
    func testUploadCannotStartIfPreparationRecordCannotCommit() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("journal.json"), withIntermediateDirectories: true)
        BucketTransactionProtocol.handler = { _ in XCTFail("no PUT before preparation record commits") }
        let (model, network) = uploadingModel(); defer { network.invalidateAndCancel() }
        let link = try await upload(model); XCTAssertNil(link)
        guard case .failed = model.state else { return XCTFail("failed local storage must not report handed to iOS") }
    }
    func testPreparationPrecedesPUTAndExpiryPrecedesInstallerLink() async throws {
        let storage = journal
        BucketTransactionProtocol.handler = { request in
            if request.httpMethod == "PUT" { XCTAssertEqual(try storage.records().count, 1); XCTAssertNil(try storage.records()[0].expiresAt) }
        }
        let (model, network) = uploadingModel(); defer { network.invalidateAndCancel() }
        let link = try await upload(model); XCTAssertNotNil(link); XCTAssertEqual(model.state, .handedToiOS)
        XCTAssertNotNil(try journal.records().first?.expiresAt)
    }
    func testFailedExpiryCommitNeverReturnsInstallerLink() async throws {
        let file = root.appendingPathComponent("journal.json")
        BucketTransactionProtocol.handler = { request in
            if request.httpMethod == "GET" { try Data("injected index damage".utf8).write(to: file) }
        }
        let (model, network) = uploadingModel(); defer { network.invalidateAndCancel() }
        let link = try await upload(model); XCTAssertNil(link)
        guard case .failed(let message) = model.state else { return XCTFail("must report the local retention failure") }
        XCTAssertTrue(message.contains("IPA was uploaded")); XCTAssertTrue(message.contains("installer was not opened"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("synthetic.ipa").path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "injected index damage")
    }

}
