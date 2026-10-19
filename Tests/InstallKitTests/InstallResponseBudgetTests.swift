import XCTest
@testable import InstallKit

private final class ResponseBudgetProtocol: URLProtocol {
    static var begin: ((ResponseBudgetProtocol) -> Void)?
    static var stopped: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.begin?(self) }
    override func stopLoading() { Self.stopped?() }
    func headers(_ headers: [String: String] = [:], status: Int = 200) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    }
    func chunk(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func finish() { client?.urlProtocolDidFinishLoading(self) }
}

final class InstallResponseBudgetTests: XCTestCase {
    private var session: URLSession!
    private var root: URL!
    private let url = URL(string: "https://budget.example/reply")!
    override func setUpWithError() throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ResponseBudgetProtocol.self]
        session = URLSession(configuration: config)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("response-budget-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        session.invalidateAndCancel(); ResponseBudgetProtocol.begin = nil; ResponseBudgetProtocol.stopped = nil
        try? FileManager.default.removeItem(at: root)
    }
    private func send(max: Int = 8, deadline: TimeInterval = 5) async throws -> (body: Data, code: Int) {
        try await InstallTransport.send(URLRequest(url: url), session: session, budget: .init(maxBytes: max, deadline: deadline))
    }
    func testSmallResponseAtExactCapIsAccepted() async throws {
        ResponseBudgetProtocol.begin = { p in p.headers(); p.chunk(Data([1,2,3,4])); p.chunk(Data([5,6,7,8])); p.finish() }
        let response = try await send(); XCTAssertEqual(response.body, Data(1...8)); XCTAssertEqual(response.code, 200)
    }
    func testNoLengthAndLyingLengthAreBothLimitedByActualChunks() async throws {
        for headers in [[:], ["Content-Length": "1"]] {
            ResponseBudgetProtocol.begin = { p in p.headers(headers); p.chunk(Data(repeating: 1, count: 4)); p.chunk(Data(repeating: 2, count: 5)); p.finish() }
            do { _ = try await send(); XCTFail("must reject actual decoded body exceeding cap") }
            catch { guard case InstallTransport.Failure.tooLarge = error else { return XCTFail("wrong error: \(error)") } }
        }
    }
    func testDeclaredOversizeIsRefusedWithoutWaitingForBody() async throws {
        ResponseBudgetProtocol.begin = { p in p.headers(["Content-Length": "9000"]) }
        do { _ = try await send(); XCTFail() }
        catch { guard case InstallTransport.Failure.tooLarge = error else { return XCTFail("wrong error: \(error)") } }
    }
    func testDeadlineStopsCompletelySilentResponse() async throws {
        let stopped = expectation(description: "network task stopped")
        ResponseBudgetProtocol.stopped = { stopped.fulfill() }; ResponseBudgetProtocol.begin = { _ in }
        do { _ = try await send(deadline: 0.05); XCTFail() }
        catch { guard case InstallTransport.Failure.deadline = error else { return XCTFail("wrong error: \(error)") } }
        await fulfillment(of: [stopped], timeout: 5)
    }
    func testDeadlineAlsoStopsSilentBodyAfterHeaders() async throws {
        ResponseBudgetProtocol.begin = { p in p.headers(); p.chunk(Data([1])) }
        do { _ = try await send(deadline: 0.05); XCTFail() }
        catch { guard case InstallTransport.Failure.deadline = error else { return XCTFail("wrong error: \(error)") } }
    }
    func testCancellationAfterHeadersStopsUnderlyingRequest() async throws {
        let started = expectation(description: "started"), stopped = expectation(description: "stopped")
        ResponseBudgetProtocol.begin = { p in p.headers(); started.fulfill() }; ResponseBudgetProtocol.stopped = { stopped.fulfill() }
        let task = Task { try await self.send() }
        await fulfillment(of: [started], timeout: 5); task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 5)
    }
    func testCancellationBeforeRegistrationCannotStartUnboundedWork() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await self.send()
        }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testUploadReplyIsBoundedAndSourceIsPreserved() async throws {
        let file = root.appendingPathComponent("upload.ipa"), bytes = Data([1,2,3]); try bytes.write(to: file)
        ResponseBudgetProtocol.begin = { p in p.headers(); p.chunk(Data(repeating: 5, count: 9)); p.finish() }
        var request = URLRequest(url: url); request.httpMethod = "PUT"
        do { _ = try await InstallTransport.sendUpload(request, file: file, session: session, budget: .init(maxBytes: 8), progress: { _ in }); XCTFail() }
        catch { guard case InstallTransport.Failure.tooLarge = error else { return XCTFail("wrong error: \(error)") } }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testUnsafeSchemeAndInvalidBudgetsAreRefusedBeforeNetwork() async throws {
        ResponseBudgetProtocol.begin = { _ in XCTFail("invalid request must never start") }
        for budget in [InstallTransport.Budget(maxBytes: 0), .init(deadline: .infinity), .init(deadline: -1)] {
            do { _ = try await InstallTransport.send(URLRequest(url: url), session: session, budget: budget); XCTFail() }
            catch { guard case InstallTransport.Failure.invalidBudget = error else { return XCTFail("wrong error: \(error)") } }
        }
        do { _ = try await InstallTransport.send(URLRequest(url: URL(string: "http://unsafe.example")!), session: session); XCTFail() }
        catch { guard case InstallTransport.Failure.unsafeURL = error else { return XCTFail("wrong error: \(error)") } }
    }
    func testCustomSessionTrustDelegateIsNeverSilentlyDropped() async throws {
        final class Delegate: NSObject, URLSessionDelegate {}
        let custom = URLSession(configuration: session.configuration, delegate: Delegate(), delegateQueue: nil)
        defer { custom.invalidateAndCancel() }
        do { _ = try await InstallTransport.send(URLRequest(url: url), session: custom); XCTFail() }
        catch { guard case InstallTransport.Failure.unsupportedSession = error else { return XCTFail("wrong error: \(error)") } }
    }
    func testFeedCancellationCannotReturnCachedCertificate() async throws {
        let now = Date(), cached = try JSONSerialization.data(withJSONObject: ["name": "fixture.example", "notAfter": ISO8601DateFormatter().string(from: now.addingTimeInterval(86400)), "p12": "AQ==", "password": "fixture"])
        let cache = root.appendingPathComponent("install-certificate-\(CertificateFeed.cacheKey(url)).json")
        try cached.write(to: cache)
        let started = expectation(description: "feed refresh")
        ResponseBudgetProtocol.begin = { p in p.headers(); started.fulfill() }
        let task = Task { try await CertificateFeed.load(feed: self.url, cacheDirectory: self.root, session: self.session, now: now, verify: { _, _ in }) }
        await fulfillment(of: [started], timeout: 5); task.cancel()
        do { _ = try await task.value; XCTFail("cancellation must not silently return cached success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: cache), cached)
    }
    func testOversizedCacheDoesNotPreventFetchingValidReplacement() async throws {
        let now = Date(), fresh = try JSONSerialization.data(withJSONObject: ["name": "fixture.example", "notAfter": ISO8601DateFormatter().string(from: now.addingTimeInterval(60*86400)), "p12": "AQ==", "password": "fixture"])
        try Data(repeating: 65, count: CertificateFeed.maxBytes + 1).write(to: root.appendingPathComponent("install-certificate-\(CertificateFeed.cacheKey(url)).json"))
        ResponseBudgetProtocol.begin = { p in p.headers(); p.chunk(fresh); p.finish() }
        let result = try await CertificateFeed.load(feed: url, cacheDirectory: root, session: session, now: now, verify: { _, _ in })
        XCTAssertEqual(result.name, "fixture.example")
    }
}
