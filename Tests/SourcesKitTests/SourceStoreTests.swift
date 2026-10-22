import XCTest
@testable import SourcesKit

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))!
    static var seen: [URLRequest] = []
    /// When set, every request fails with this error (a dropped connection).
    static var failure: Error?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.seen.append(request)
        if let failure = StubProtocol.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let (code, headers, data) = StubProtocol.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SourceStoreTests: XCTestCase {
    private var dir: URL!
    private let sourceURL = URL(string: "https://repo.example.test/source.json")!
    private let good = Data("""
    {"name":"Test Repo","apps":[{"name":"Alpha","bundleIdentifier":"com.a","versions":[{"version":"1","downloadURL":"https://e.test/a.ipa"}]}]}
    """.utf8)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sources-\(UUID().uuidString)")
        StubProtocol.seen = []
        StubProtocol.failure = nil
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func makeStore() -> SourceStore {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]
        return SourceStore(directory: dir, session: URLSession(configuration: c))
    }

    func testAddDownloadsParsesAndCaches() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "\"v1\""], self.good) }
        let store = makeStore()
        let repo = try await store.add(url: sourceURL)
        XCTAssertEqual(repo.apps.count, 1)
        let saved = try XCTUnwrap(store.sources.first)
        XCTAssertEqual(saved.name, "Test Repo"); XCTAssertEqual(saved.appCount, 1)
        XCTAssertEqual(store.cached(saved.id)?.apps.first?.name, "Alpha")
    }

    func testNotModifiedUsesTheCacheAndKeepsItIntact() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "\"v1\""], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id
        StubProtocol.handler = { _ in (304, [:], Data()) }
        let repo = try await store.refresh(id)
        XCTAssertEqual(repo.apps.first?.name, "Alpha")
        XCTAssertEqual(StubProtocol.seen.last?.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertEqual(store.cached(id)?.apps.count, 1)
    }

    func testHTMLResponseThrowsAndLeavesTheCacheUntouched() async throws {
        StubProtocol.handler = { _ in (200, [:], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id
        StubProtocol.handler = { _ in (200, [:], Data("<html>login</html>".utf8)) }
        do { _ = try await store.refresh(id); XCTFail("should throw") } catch { XCTAssertEqual(error as? SourceError, .notJSON) }
        XCTAssertEqual(store.cached(id)?.apps.first?.name, "Alpha")
    }
    func testOverComplexRefreshPreservesCachedSourceAndETag() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "\"good\""], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let saved = try XCTUnwrap(store.sources.first)
        let cache = dir.appendingPathComponent("cache-\(saved.id.uuidString).json")
        let tag = dir.appendingPathComponent("cache-\(saved.id.uuidString).etag")
        let before = try Data(contentsOf: cache), previousTag = try Data(contentsOf: tag)
        let nested = Data((#"{"apps":[],"ignored":"# + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}").utf8)
        StubProtocol.handler = { _ in (200, ["ETag": "\"bad\""], nested) }
        do { _ = try await store.refresh(saved.id); XCTFail("must reject before cache publication") }
        catch { XCTAssertEqual(error as? SourceError, .resourceLimit("JSON nesting limit")) }
        XCTAssertEqual(try Data(contentsOf: cache), before); XCTAssertEqual(try Data(contentsOf: tag), previousTag)
        XCTAssertEqual(store.sources, [saved]); XCTAssertEqual(store.cached(saved.id)?.apps.first?.name, "Alpha")
    }
    func testRejectedBudgetRefreshCannotReauthorizeOlderResponseCommit() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "\"good\""], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let saved = try XCTUnwrap(store.sources.first), older = try store.beginRefresh(saved.id)
        let nested = Data((#"{"apps":[],"ignored":"# + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}").utf8)
        StubProtocol.handler = { _ in (200, ["ETag": "\"bad\""], nested) }
        do { _ = try await store.refresh(saved.id); XCTFail("must reject the newer input") }
        catch { XCTAssertEqual(error as? SourceError, .resourceLimit("JSON nesting limit")) }
        XCTAssertThrowsError(try store.finishRefresh(older, repo: SourceRepo(name: "stale", apps: []), etag: "stale")) {
            XCTAssertEqual($0 as? SourceStoreError, .refreshSuperseded)
        }
        XCTAssertEqual(store.sources, [saved]); XCTAssertEqual(store.cached(saved.id)?.name, "Test Repo")
    }

    func testFailedAddSavesNothing() async throws {
        StubProtocol.handler = { _ in (404, [:], Data("nope".utf8)) }
        let store = makeStore()
        do { _ = try await store.add(url: sourceURL); XCTFail("should throw") } catch {}
        XCTAssertTrue(store.sources.isEmpty)
    }

    func testHTTPURLIsRefused() async throws {
        let store = makeStore()
        do { _ = try await store.add(url: URL(string: "http://repo.example.test/s.json")!); XCTFail("should throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("https")) }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
    }

    func testSourcesSurviveReloadAndCanBeRemoved() async throws {
        StubProtocol.handler = { _ in (200, [:], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sources.count, 1)
        XCTAssertNotNil(reloaded.cached(reloaded.sources[0].id))
        try reloaded.remove(reloaded.sources[0].id)
        XCTAssertTrue(makeStore().sources.isEmpty)
    }

    func testAddingTheSameURLTwiceDoesNotDuplicateIt() async throws {
        StubProtocol.handler = { _ in (200, [:], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL); _ = try await store.add(url: sourceURL)
        XCTAssertEqual(store.sources.count, 1)
    }

    func testRemoveKeepsSourceAndCacheWhenIndexWriteFails() async throws {
        StubProtocol.handler = { _ in (200, [:], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let source = try XCTUnwrap(store.sources.first)
        let indexURL = dir.appendingPathComponent("sources.json")
        let indexData = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: indexURL)
            try? indexData.write(to: indexURL)
        }

        XCTAssertThrowsError(try store.remove(source.id))
        XCTAssertEqual(store.sources, [source])
        XCTAssertNotNil(store.cached(source.id))
    }

    /// The size cap is the only thing stopping a hostile source filling the phone's disk. A probe that fails must
    /// not read as "zero bytes", which would wave any size through.
    func testSizeProbeFailureIsRefusedRatherThanReadAsZero() {
        let missing = dir.appendingPathComponent("not-here.json")
        XCTAssertThrowsError(try SourceStore.measuredSize(of: missing),
                             "an unmeasurable file must be refused, not assumed empty")
    }

    func testMeasuredSizeMatchesTheFileOnDisk() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("s.json")
        try Data(repeating: 0x41, count: 4096).write(to: f)
        XCTAssertEqual(try SourceStore.measuredSize(of: f), 4096)
    }

    func testOversizedSourceIsRefusedAndNothingIsCached() async throws {
        StubProtocol.handler = { _ in (200, [:], Data(repeating: 0x41, count: SourceStore.maxBytes + 1)) }
        let store = makeStore()
        do { _ = try await store.add(url: sourceURL); XCTFail("an oversized source was accepted") }
        catch { XCTAssertEqual(error as? SourceStoreError, .tooLarge) }
        XCTAssertTrue(store.sources.isEmpty)
    }
}

extension SourceStoreTests {
    func testNew200WithoutETagClearsTheOldValidator() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "\"old\""], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id
        StubProtocol.handler = { _ in (200, [:], self.good) }
        _ = try await store.refresh(id)
        _ = try await store.refresh(id)
        XCTAssertNil(StubProtocol.seen.last?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cache-\(id.uuidString).etag").path))
    }

    func testRemovedSourceCannotBeResurrectedByAnInflightRefresh() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "old"], self.good) }
        let store = makeStore(); let repo = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id, refresh = try store.beginRefresh(id)
        try store.remove(id)
        XCTAssertThrowsError(try store.finishRefresh(refresh, repo: repo, etag: "late")) {
            XCTAssertEqual($0 as? SourceStoreError, .refreshSuperseded)
        }
        XCTAssertNil(store.cached(id)); XCTAssertTrue(makeStore().sources.isEmpty)
    }

    func testLateOldRefreshCannotOverwriteANewerCommit() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "old"], self.good) }
        let store = makeStore(); let original = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id
        let old = try store.beginRefresh(id), new = try store.beginRefresh(id)
        let fresh = try SourceParser.parse(Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "Test Repo", with: "Fresh Repo").utf8))
        _ = try store.finishRefresh(new, repo: fresh, etag: "new")
        XCTAssertThrowsError(try store.finishRefresh(old, repo: original, etag: "old")) {
            XCTAssertEqual($0 as? SourceStoreError, .refreshSuperseded)
        }
        XCTAssertEqual(store.cached(id)?.name, "Fresh Repo")
        XCTAssertEqual(store.sources.first?.name, "Fresh Repo")
        XCTAssertEqual(try store.beginRefresh(id).etag, "new")
    }

    func testCacheWriteFailureCannotLeaveAnOldETagForNewContent() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "old"], self.good) }
        let store = makeStore(); let original = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id, refresh = try store.beginRefresh(id)
        let cache = dir.appendingPathComponent("cache-\(id.uuidString).json")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.finishRefresh(refresh, repo: original, etag: "new"))
        XCTAssertNil(try store.beginRefresh(id).etag)
        XCTAssertEqual(store.sources.count, 1)
    }

    func testIndexWriteFailureReportsFailureAndPreservesCoherentCacheValidator() async throws {
        StubProtocol.handler = { _ in (200, ["ETag": "old"], self.good) }
        let store = makeStore(); _ = try await store.add(url: sourceURL)
        let id = try XCTUnwrap(store.sources.first).id, refresh = try store.beginRefresh(id)
        let fresh = try SourceParser.parse(Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "Test Repo", with: "Fresh Repo").utf8))
        let index = dir.appendingPathComponent("sources.json")
        try FileManager.default.removeItem(at: index); try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.finishRefresh(refresh, repo: fresh, etag: "new"))
        XCTAssertEqual(store.sources.first?.name, "Test Repo")
        XCTAssertEqual(store.cached(id)?.name, "Fresh Repo")
        XCTAssertEqual(try store.beginRefresh(id).etag, "new")
    }
}
