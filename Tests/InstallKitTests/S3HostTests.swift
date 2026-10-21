import XCTest
@testable import InstallKit

private final class S3Stub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!
    static var seen: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        S3Stub.seen.append(request)
        if let s = request.httpBodyStream { s.open(); let b = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { b.deallocate() }
            while s.hasBytesAvailable, s.read(b, maxLength: 4096) > 0 {}; s.close() }
        let (code, data) = S3Stub.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class CleanupRedirectStub: URLProtocol {
    static var destinations: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.destinations.append(request.url!.host!)
        if request.url!.host == "acct.r2.example" {
            let target = URL(string: "https://other.example/not-our-artifact")!
            var forwarded = request; forwarded.url = target
            client?.urlProtocol(self, wasRedirectedTo: forwarded,
                redirectResponse: HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": target.absoluteString])!)
        } else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class S3HostTests: XCTestCase {
    private var ipa: URL!
    private let creds = S3Credentials(accessKey: "AK", secretKey: "SK", region: "auto", endpoint: URL(string: "https://acct.r2.example")!)
    private let plist = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)
    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [S3Stub.self]; return URLSession(configuration: c)
    }
    private func host(id: String = "ABCDEFGHIJKLMNOPQRSTUV") throws -> S3Host {
        try S3Host(credentials: creds, bucket: "wax", session: session, id: id, now: { Date(timeIntervalSince1970: 1369353600) })
    }
    private func publish(_ h: S3Host) async throws -> URL {
        try await h.publish(ipa: ipa, bundleIdentifier: "a.b", version: "1", build: "7", title: "T", progress: { _ in })
    }
    override func setUpWithError() throws {
        S3Stub.seen = []
        S3Stub.handler = { [plist] r in r.httpMethod == "GET" ? (200, plist) : (200, Data()) }
        ipa = FileManager.default.temporaryDirectory.appendingPathComponent("s3-\(UUID().uuidString).ipa")
        try Data(repeating: 1, count: 3000).write(to: ipa)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: ipa) }

    func testPublishPutsIPAAndManifestThenReturnsAnItmsLinkWithSignedURLs() async throws {
        let link = try await publish(host())
        XCTAssertEqual(S3Stub.seen.map { $0.httpMethod ?? "" }, ["PUT", "PUT", "GET"], "IPA, manifest, then the link check")
        XCTAssertEqual(S3Stub.seen[0].url?.path, "/wax/ota/ABCDEFGHIJKLMNOPQRSTUV/app.ipa")
        XCTAssertEqual(S3Stub.seen[1].url?.path, "/wax/ota/ABCDEFGHIJKLMNOPQRSTUV/manifest.plist")
        XCTAssertTrue(S3Stub.seen[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=AK/20130524/auto/s3/") == true)
        XCTAssertNil(S3Stub.seen[2].value(forHTTPHeaderField: "Authorization"), "the link check uses the presigned URL alone, like iOS")
        XCTAssertTrue(link.absoluteString.hasPrefix("itms-services://?action=download-manifest&url=https://acct.r2.example/wax/ota/"))
        XCTAssertTrue(link.absoluteString.contains("X-Amz-Signature"))
    }

    func testSignedLinksExpireAfterSixHours() async throws {
        _ = try await publish(host())
        let check = S3Stub.seen[2].url!.absoluteString
        XCTAssertTrue(check.contains("X-Amz-Expires=21600"), check)
    }

    func testExpiredKeysSurfaceAsAMessageNamingTheKeys() async {
        S3Stub.handler = { _ in (403, Data("<Error><Code>ExpiredToken</Code></Error>".utf8)) }
        do { _ = try await publish(host()); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("keys"), error.localizedDescription) }
    }

    func testWrongRegionSurfacesTheRegionMessage() async {
        S3Stub.handler = { _ in (400, Data("<Error><Code>AuthorizationHeaderMalformed</Code><Message>the region 'auto' is wrong; expecting 'eu-west-1'</Message></Error>".utf8)) }
        do { _ = try await publish(host()); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("eu-west-1"), error.localizedDescription) }
    }

    func testFailedManifestPutDeletesBothObjects() async {
        var puts = 0
        S3Stub.handler = { r in
            if r.httpMethod == "PUT" { puts += 1; return (puts == 1 ? 200 : 500, Data()) }
            return (204, Data())
        }
        do { _ = try await publish(host()); XCTFail("expected throw") } catch {}
        let deleted = S3Stub.seen.filter { $0.httpMethod == "DELETE" }.map { $0.url!.lastPathComponent }
        XCTAssertEqual(Set(deleted), ["app.ipa", "manifest.plist"], "a half-written session leaves nothing behind")
    }

    func testCleanupDeletesBothObjects() async throws {
        S3Stub.handler = { _ in (204, Data()) }
        try await host().cleanup()
        XCTAssertEqual(S3Stub.seen.map { $0.httpMethod ?? "" }, ["DELETE", "DELETE"])
        XCTAssertEqual(Set(S3Stub.seen.map { $0.url!.lastPathComponent }), ["app.ipa", "manifest.plist"])
    }

    func testCheckAccessListsOneKeyAndExplainsARejection() async throws {
        try await host().checkAccess()
        XCTAssertEqual(S3Stub.seen[0].url?.path, "/wax")
        XCTAssertTrue(S3Stub.seen[0].url?.query?.contains("max-keys=1") == true)
        S3Stub.handler = { _ in (403, Data("<Error><Code>SignatureDoesNotMatch</Code></Error>".utf8)) }
        do { try await host().checkAccess(); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("secret key"), error.localizedDescription) }
    }
    func testConfirmedCleanupDoesNotHideHTTPFailureAndStillAttemptsBothObjects() async throws {
        S3Stub.handler = { r in (r.url!.lastPathComponent == "app.ipa" ? 403 : 204, Data()) }
        do { try await host().cleanupConfirmed(); XCTFail("expected cleanup rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("403")) }
        XCTAssertEqual(S3Stub.seen.map { $0.httpMethod ?? "" }, ["DELETE", "DELETE"])
        XCTAssertTrue(S3Stub.seen.allSatisfy { $0.timeoutInterval == 20 })
    }
    func testConfirmedCleanupAcceptsAlreadyAbsentObjects() async throws {
        S3Stub.handler = { _ in (404, Data()) }
        try await host().cleanupConfirmed()
        XCTAssertEqual(S3Stub.seen.count, 2)
    }
    func testConfirmedCleanupDoesNotTreatRedirectAsSuccess() async throws {
        S3Stub.handler = { _ in (307, Data()) }
        do { try await host().cleanupConfirmed(); XCTFail("expected redirect rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("307")) }
        XCTAssertTrue(S3Stub.seen.allSatisfy { $0.url?.host == "acct.r2.example" })
    }

    func testCleanupRedirectDelegateStopsRealRedirectCallback() async throws {
        CleanupRedirectStub.destinations = []
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CleanupRedirectStub.self]
        let network = URLSession(configuration: config); defer { network.invalidateAndCancel() }
        let target = try S3Host(credentials: creds, bucket: "wax", session: network, id: "ABCDEFGHIJKLMNOPQRSTUV")
        do { try await target.cleanupConfirmed(); XCTFail("redirect must fail cleanup") } catch {}
        XCTAssertEqual(CleanupRedirectStub.destinations, ["acct.r2.example", "acct.r2.example"], "neither destructive request may reach the redirect destination")
    }

}
