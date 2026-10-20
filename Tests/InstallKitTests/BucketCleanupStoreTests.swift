import XCTest
@testable import InstallKit

final class BucketCleanupStoreTests: XCTestCase {
    private var root: URL!
    private var file: URL { root.appendingPathComponent("cleanup.json") }
    private var store: BucketCleanupStore { BucketCleanupStore(file: file) }
    private var credentials: S3Credentials { S3Credentials(accessKey: "public-access-id", secretKey: "never-persist-this-secret", region: "auto", endpoint: URL(string: "https://old.example/api")!) }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bucket-journal-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func record() throws -> BucketCleanupRecord {
        try BucketCleanupRecord(sessionID: "ABCDEFGHIJKLMNOPQRSTUV", scope: BucketCleanupScope(credentials: credentials, bucket: "wax"))
    }
    func testPreparationAndExpirySurviveRestartWithoutCredentialsInJournal() throws {
        var entry = try record(); try store.put(entry)
        XCTAssertEqual(try store.records(), [entry]); XCTAssertNil(try store.records()[0].expiresAt)
        entry.expiresAt = Date(timeIntervalSince1970: 123456); try store.put(entry)
        XCTAssertEqual(try store.records(), [entry])
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(json.contains(credentials.secretKey)); XCTAssertFalse(json.contains(credentials.accessKey))
        XCTAssertTrue(json.contains("old.example"))
    }
    func testDifferentHostBucketRegionAndAccessKeyNeverMatchScope() throws {
        let expected = try record().scope
        for variant in [S3Credentials(accessKey: credentials.accessKey, secretKey: "x", region: "auto", endpoint: URL(string: "https://new.example/api")!),
                        S3Credentials(accessKey: credentials.accessKey, secretKey: "x", region: "other", endpoint: credentials.endpoint),
                        S3Credentials(accessKey: "new-access", secretKey: "x", region: "auto", endpoint: credentials.endpoint)] {
            XCTAssertNotEqual(try BucketCleanupScope(credentials: variant, bucket: "wax"), expected)
        }
        XCTAssertNotEqual(try BucketCleanupScope(credentials: credentials, bucket: "another"), expected)
    }
    func testCorruptIndexIsPreservedAndCannotBeOverwrittenByNewRecord() throws {
        let damaged = Data("{interrupted".utf8); try damaged.write(to: file)
        XCTAssertThrowsError(try store.records()); XCTAssertThrowsError(try store.put(record()))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }
    func testIndexPublicationFailureIsAnErrorNotSuccess() throws {
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.put(record()))
        XCTAssertTrue((try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true)
    }
    func testCompletedCleanupDoesNotRemoveAnUpdatedExpiry() throws {
        let previous = try record(); try store.put(previous)
        var current = previous; current.expiresAt = Date(timeIntervalSince1970: 500); try store.put(current)
        try store.remove(previous); XCTAssertEqual(try store.records(), [current])
        try store.remove(current); XCTAssertTrue(try store.records().isEmpty)
        try store.remove(current); XCTAssertTrue(try store.records().isEmpty)
    }
    func testConcurrentUpdatesKeepAllRecords() throws {
        let shared = store, scope = try record().scope
        let entries = try (0..<20).map { index in try BucketCleanupRecord(sessionID: "ABCDEFGHIJKLMNOPQRST" + String(format: "%02d", index), scope: scope) }
        DispatchQueue.concurrentPerform(iterations: entries.count) { index in
            do { try shared.put(entries[index]) } catch { XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(Set(try shared.records().map(\.id)), Set(entries.map(\.id)))
    }
    func testInvalidPersistedSessionAndUnknownVersionFailClosed() throws {
        let entry = try record(); try store.put(entry)
        let json = try Data(contentsOf: file)
        for changed in [String(decoding: json, as: UTF8.self).replacingOccurrences(of: entry.sessionID, with: "../../not-contained"),
                        String(decoding: json, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":99")] {
            try Data(changed.utf8).write(to: file); XCTAssertThrowsError(try store.records())
        }
    }
    func testUnsafeScopeAndSessionIDsCannotBeCreated() throws {
        for id in ["", "../secret", String(repeating: "A", count: 23)] { XCTAssertThrowsError(try BucketCleanupRecord(sessionID: id, scope: record().scope)) }
        for bucket in ["", ".", "..", "a/b", "a\\b"] { XCTAssertThrowsError(try BucketCleanupScope(credentials: credentials, bucket: bucket)) }
        var unsafe = credentials; unsafe.endpoint = URL(string: "https://user:password@wrong.example")!
        XCTAssertThrowsError(try BucketCleanupScope(credentials: unsafe, bucket: "wax"))
    }
    func testDuplicateRemoteRouteWithDifferentRecordIDCannotRiskALiveLink() throws {
        let first = try record(), second = try record(); try store.put(first)
        XCTAssertThrowsError(try store.put(second)); XCTAssertEqual(try store.records(), [first])
    }

}
