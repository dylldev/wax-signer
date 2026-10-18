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
}
