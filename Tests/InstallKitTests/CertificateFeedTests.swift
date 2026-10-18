import XCTest
@testable import InstallKit

private final class FeedStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        FeedStub.calls += 1
        let (code, data) = FeedStub.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CertificateFeedTests: XCTestCase {
    private var dir: URL!
    private let feed = URL(string: "https://feed.example.test/cert.json")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [FeedStub.self]; return URLSession(configuration: c)
    }
    private func json(notAfter: Date, name: String = "wax.example.test", p12: String? = nil) -> Data {
        let f = ISO8601DateFormatter()
        return try! JSONSerialization.data(withJSONObject: ["name": name, "notAfter": f.string(from: notAfter),
                                                            "p12": p12 ?? TestTLS.p12.base64EncodedString(), "password": "wax"])
    }
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("feed-\(UUID().uuidString)")
        FeedStub.calls = 0
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func load() async throws -> CertificateBundle {
        try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now)
    }

    func testFirstUseFetchesAndCaches() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400))) }
        let b = try await load()
        XCTAssertEqual(b.name, "wax.example.test"); XCTAssertEqual(b.password, "wax")
        XCTAssertEqual(FeedStub.calls, 1)
        _ = try await load()
        XCTAssertEqual(FeedStub.calls, 1, "a certificate with plenty of life left is not fetched again")
    }

    func testACertificateNearExpiryIsRefreshed() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(3 * 86400))) }
        _ = try await load()
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(80 * 86400))) }
        let b = try await load()
        XCTAssertEqual(FeedStub.calls, 2)
        XCTAssertGreaterThan(b.notAfter, now.addingTimeInterval(60 * 86400))
    }

    func testAnOfflineFeedFallsBackToAStillValidCachedCertificate() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(3 * 86400))) }
        _ = try await load()
        FeedStub.handler = { _ in (503, Data()) }
        let b = try await load()
        XCTAssertEqual(b.name, "wax.example.test")
    }

    func testAnExpiredCertificateIsNeverUsed() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(-86400))) }
        do { _ = try await load(); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("expired"), error.localizedDescription) }
    }

    func testGarbageAndNonHTTPSFeedsAreRefusedWithAMessage() async throws {
        FeedStub.handler = { _ in (200, Data("not json".utf8)) }
        do { _ = try await load(); XCTFail("expected throw") } catch {}
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), p12: "!!!")) }
        do { _ = try await load(); XCTFail("expected throw") } catch {}
        do { _ = try await CertificateFeed.load(feed: URL(string: "http://x.test/c.json")!, cacheDirectory: dir, session: session, now: now); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("https")) }
    }

    func testABundleBuildsAHostForItsName() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: "localhost")) }
        let b = try await load()
        let host = try LoopbackHost(p12: b.p12Data, password: b.password, host: b.name)
        host.stop()
    }

    func testAnOversizedFeedIsRefused() async throws {
        let big = json(notAfter: now.addingTimeInterval(60 * 86400), p12: String(repeating: "A", count: 200_000))
        FeedStub.handler = { _ in (200, big) }
        do { _ = try await load(); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("too large"), error.localizedDescription) }
    }

    func testEachFeedHasItsOwnCache() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: "a.example.test")) }
        _ = try await load()
        FeedStub.handler = { _ in (503, Data()) }
        let other = URL(string: "https://other.example.test/cert.json")!
        do { _ = try await CertificateFeed.load(feed: other, cacheDirectory: dir, session: session, now: now); XCTFail("expected throw") } catch {}
    }

    func testANameOutsideTheAllowListIsRefusedAndNotCached() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: "evil.example.test")) }
        do { _ = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now, allowedNames: ["wax.example.test"]); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("evil.example.test"), error.localizedDescription) }
        FeedStub.handler = { _ in (503, Data()) }
        do { _ = try await load(); XCTFail("a refused certificate must not be cached") } catch {}
    }

    func testOddNamesAndAbsurdLifetimesAreRefused() async throws {
        for name in ["a b.test", "x.test/../y", "", "UPPER..test", "-bad.test"] {
            FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: name)) }
            do { _ = try await load(); XCTFail("expected throw for \(name)") } catch {}
        }
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(900 * 86400))) }
        do { _ = try await load(); XCTFail("expected throw") } catch {}
    }

    func testTheOfficialFeedIsRecognisedWhateverTheSpelling() {
        let official = URL(string: LoopbackConfig.defaultFeed)!
        XCTAssertEqual(LoopbackConfig.allowedNames(for: official), LoopbackConfig.officialNames)
        for spelled in ["HTTPS://DYLLDEV.github.io/wax-signer/cert.json", "https://dylldev.github.io:443/wax-signer/cert.json?x=1",
                        "https://dylldev.github.io/wax-signer/cert.json/", "https://dylldev.github.io/wax-signer/cert.json#frag"] {
            XCTAssertEqual(LoopbackConfig.allowedNames(for: URL(string: spelled)!), LoopbackConfig.officialNames, spelled)
        }
        XCTAssertNil(LoopbackConfig.allowedNames(for: URL(string: "https://dylldev.github.io/other/cert.json")!))
        XCTAssertNil(LoopbackConfig.allowedNames(for: URL(string: "https://example.test/wax-signer/cert.json")!))
    }

    func testACachedCertificateIsRefreshedOnceADayHasPassed() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400))) }
        _ = try await load()
        _ = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now.addingTimeInterval(3600))
        XCTAssertEqual(FeedStub.calls, 1, "within a day the cache is used")
        _ = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now.addingTimeInterval(2 * 86400))
        XCTAssertEqual(FeedStub.calls, 2, "a day later the feed is asked again, so a re-issued certificate reaches the phone")
    }

    func testTheChainCheckRefusesACertificateThatIsNotTrustedForItsName() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: "localhost")) }
        do { _ = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now, verifyChain: true); XCTFail("a self-signed certificate is not trusted") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("certificate"), error.localizedDescription) }
        FeedStub.handler = { _ in (503, Data()) }
        do { _ = try await load(); XCTFail("a refused certificate must not be cached") } catch {}
    }

    func testACachedCertificateIsCheckedTooWhenTheChainCheckIsOn() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400), name: "localhost")) }
        _ = try await load()                                    // cached without the chain check (an older build)
        FeedStub.handler = { _ in (503, Data()) }
        do { _ = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now, verifyChain: true); XCTFail("an untrusted cached certificate must not be used") }
        catch {}
    }

    func testAnUppercaseSchemeIsStillHTTPS() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400))) }
        let b = try await CertificateFeed.load(feed: URL(string: "HTTPS://feed.example.test/cert.json")!, cacheDirectory: dir, session: session, now: now)
        XCTAssertEqual(b.name, "wax.example.test")
    }

    func testAPortMakesItAnotherFeed() {
        XCTAssertNil(LoopbackConfig.allowedNames(for: URL(string: "https://dylldev.github.io:8443/wax-signer/cert.json")!))
    }

    func testAFeedThatAnswersInTimeStillLoadsWithABodyDeadline() async throws {
        FeedStub.handler = { [self] _ in (200, json(notAfter: now.addingTimeInterval(60 * 86400))) }
        // ponytail: the trickle-too-slow branch is not unit-tested (needs a slow URLProtocol); upgrade if the deadline logic grows
        let b = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, session: session, now: now, bodyDeadline: 5)
        XCTAssertEqual(b.name, "wax.example.test")
    }
}
