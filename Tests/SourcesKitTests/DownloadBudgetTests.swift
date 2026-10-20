import XCTest
@testable import SourcesKit

private final class SilentProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {} // no bytes at all: a body-loop-only deadline would never fire
    override func stopLoading() {}
}

final class DownloadBudgetTests: XCTestCase {
    private var directory: URL!
    private let payload = Data([0x50, 0x4b, 0x03, 0x04]) + Data(repeating: 7, count: 4096)
    private func app(_ address: String = "https://example.test/app.ipa") -> SourceApp {
        SourceApp(id: "example@1", name: "App", bundleID: "com.example.app", version: "1", size: nil,
                  iconURL: nil, downloadURL: URL(string: address)!, date: nil, summary: "", developer: "")
    }
    private func session(_ protocolType: URLProtocol.Type = StubProtocol.self) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [protocolType]
        return URLSession(configuration: configuration)
    }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        StubProtocol.seen = []; StubProtocol.failure = nil
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func download(budget: DownloadBudget, session: URLSession? = nil, address: String = "https://example.test/app.ipa") async throws -> URL {
        let staging = directory!
        let downloader = IPADownloader(session: session ?? self.session(), stagingDirectory: { staging }, budget: budget)
        return try await downloader.download(app(address), to: directory, refetch: { self.app() }, progress: { _ in })
    }
    func testKnownUnknownAndLyingLengthsCannotBypassActualByteLimit() async throws {
        for headers in [["Content-Length": "\(payload.count)"], [:], ["Content-Length": "16"]] {
            StubProtocol.handler = { _ in (200, headers, self.payload) }
            do { _ = try await download(budget: DownloadBudget(maxBytes: 1024)); XCTFail("oversized IPA accepted") }
            catch { XCTAssertEqual(error as? DownloadError, .tooLarge) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }
    func testExactLimitIsAcceptedAndMatchesActualBytes() async throws {
        StubProtocol.handler = { _ in (200, [:], self.payload) }
        let file = try await download(budget: DownloadBudget(maxBytes: Int64(payload.count)))
        XCTAssertEqual(try Data(contentsOf: file), payload)
    }
    func testInsufficientFreeSpaceRejectsBeforeNetworkOrPartialCreation() async throws {
        do { _ = try await download(budget: DownloadBudget(minimumFreeBytes: Int64.max)); XCTFail("disk budget ignored") }
        catch { XCTAssertEqual(error as? DownloadError, .insufficientStorage) }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    func testDeadlineFiresEvenWhenNoResponseOrBodyEverArrives() async throws {
        let network = session(SilentProtocol.self); defer { network.invalidateAndCancel() }
        do { _ = try await download(budget: DownloadBudget(deadline: 0.05), session: network); XCTFail("deadline ignored") }
        catch { XCTAssertEqual(error as? DownloadError, .tooSlow) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    func testAlreadyCancelledTaskDoesNotStartAnOrphanDownload() async throws {
        StubProtocol.handler = { _ in (200, [:], self.payload) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await self.download(budget: DownloadBudget())
        }
        do { _ = try await task.value; XCTFail("cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    func testUnsafeInitialURLIsRejectedBeforeNetwork() async throws {
        do { _ = try await download(budget: DownloadBudget(), address: "http://example.test/app.ipa"); XCTFail("HTTP accepted") }
        catch { XCTAssertEqual(error as? DownloadError, .notHTTPS) }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
    }
    func testInvalidBudgetsReturnControlledErrors() async throws {
        for budget in [DownloadBudget(maxBytes: 0), DownloadBudget(deadline: .infinity), DownloadBudget(deadline: -1), DownloadBudget(minimumFreeBytes: -1)] {
            do { _ = try await download(budget: budget); XCTFail("invalid budget accepted") }
            catch { guard case .invalidBudget = error as? BoundedDownloadError else { return XCTFail("\(error)") } }
        }
    }
    func testSourceBudgetFailsWithoutCachingOversizedResponse() async throws {
        StubProtocol.handler = { _ in (200, [:], self.payload) }
        let store = SourceStore(directory: directory, session: session(), budget: DownloadBudget(maxBytes: 128))
        do { _ = try await store.add(url: URL(string: "https://example.test/source.json")!); XCTFail("source budget ignored") }
        catch { XCTAssertEqual(error as? SourceStoreError, .tooLarge) }
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

private final class DowngradeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "http://example.test/insecure.ipa"])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "http://example.test/insecure.ipa")!), redirectResponse: response)
    }
    override func stopLoading() {}
}

extension DownloadBudgetTests {
    func testHTTPSRedirectCannotDowngradeTransport() async throws {
        let network = session(DowngradeProtocol.self); defer { network.invalidateAndCancel() }
        do { _ = try await download(budget: DownloadBudget(deadline: 2), session: network); XCTFail("downgrade accepted") }
        catch { XCTAssertEqual(error as? DownloadError, .notHTTPS) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

private final class CustomSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {}

extension DownloadBudgetTests {
    func testCustomTrustDelegateIsNeverSilentlyDropped() async throws {
        let network = URLSession(configuration: .ephemeral, delegate: CustomSessionDelegate(), delegateQueue: nil)
        defer { network.invalidateAndCancel() }
        do { _ = try await download(budget: DownloadBudget(), session: network); XCTFail("custom trust policy was dropped") }
        catch { guard case .unsupportedDelegate = error as? BoundedDownloadError else { return XCTFail("\(error)") } }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
    }
}
