import XCTest
import CryptoKit
@testable import InstallKit

final class OTAManifestTests: XCTestCase {
    func testContainsRequiredKeysAndEscapes() throws {
        let xml = OTAManifest.build(bundleIdentifier: "com.example.app", bundleVersion: "1.2.3",
                                    title: "Fish & <Chips> \"x\"", ipaURL: URL(string: "https://h.example/ota/ID/app.ipa")!)
        let plist = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as! [String: Any]
        let item = (plist["items"] as! [[String: Any]])[0]
        let asset = (item["assets"] as! [[String: Any]])[0]
        XCTAssertEqual(asset["kind"] as? String, "software-package")
        XCTAssertEqual(asset["url"] as? String, "https://h.example/ota/ID/app.ipa")
        let meta = item["metadata"] as! [String: Any]
        XCTAssertEqual(meta["bundle-identifier"] as? String, "com.example.app")
        XCTAssertEqual(meta["bundle-version"] as? String, "1.2.3")
        XCTAssertEqual(meta["kind"] as? String, "software")
        XCTAssertEqual(meta["title"] as? String, "Fish & <Chips> \"x\"")
    }

    func testEmptyVersionFallsBackSoIOSAcceptsIt() {
        let xml = OTAManifest.build(bundleIdentifier: "a.b", bundleVersion: "", title: "", ipaURL: URL(string: "https://h/x.ipa")!)
        XCTAssertTrue(xml.contains("<string>1</string>") || xml.contains("<string>1.0</string>"))
        XCTAssertTrue(xml.contains("<key>title</key><string>a.b</string>"), "empty title falls back to the bundle id")
    }
}

final class OTAEndpointTests: XCTestCase {
    func testAcceptsHTTPSBaseAndBuildsURLs() throws {
        let e = try OTAEndpoint("https://ota.example.test/")
        XCTAssertEqual(e.uploadURL(id: "ID", name: "app.ipa").absoluteString, "https://ota.example.test/ota-up/u/ID/app.ipa")
        XCTAssertEqual(e.publicURL(id: "ID", name: "manifest.plist").absoluteString, "https://ota.example.test/ota/ID/manifest.plist")
    }
    func testRejectsInsecureOrOddBases() {
        for bad in ["http://h.example", "ftp://h", "h.example", "", "https://", "https://u:p@h.example", "https://h.example/?a=1", "https://h.example/#x"] {
            XCTAssertThrowsError(try OTAEndpoint(bad), bad)
        }
    }
    func testInstallLinkShape() throws {
        let link = OTALink.installURL(manifest: URL(string: "https://h.example/ota/ID/manifest.plist")!)
        XCTAssertEqual(link.absoluteString, "itms-services://?action=download-manifest&url=https://h.example/ota/ID/manifest.plist")
    }
}

final class OTASessionIDTests: XCTestCase {
    func testLengthAlphabetAndUniqueness() throws {
        let ids = try (0..<200).map { _ in try OTASessionID.make() }
        XCTAssertEqual(Set(ids).count, 200)
        for id in ids {
            XCTAssertGreaterThanOrEqual(id.count, 22)
            XCTAssertNil(id.range(of: "[^A-Za-z0-9_-]", options: .regularExpression))
        }
    }

    /// The 128 random bits are the only thing protecting a download link. When the generator fails, an install must
    /// fail with something the user can retry -- the app must not trap.
    func testRandomnessFailureThrowsInsteadOfCrashing() {
        let saved = OTASessionID.fillRandom
        defer { OTASessionID.fillRandom = saved }
        OTASessionID.fillRandom = { _ in errSecUnimplemented }
        XCTAssertThrowsError(try OTASessionID.make()) { error in
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }

    /// A generator that reports success but writes nothing must not produce a link every device can guess.
    func testAllZeroRandomnessIsRefused() {
        let saved = OTASessionID.fillRandom
        defer { OTASessionID.fillRandom = saved }
        OTASessionID.fillRandom = { _ in errSecSuccess }
        XCTAssertThrowsError(try OTASessionID.make(), "all-zero entropy must be refused, not shipped as a link secret")
    }
}

private final class Stub: URLProtocol {
    static var handler: ((URLRequest, Data) -> (Int, Data))!
    /// GET requests (the link check, the token check) answer from here; by default a reachable manifest.
    static var getHandler: (URLRequest) -> (Int, Data) = { _ in
        (200, Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8))
    }
    static var seen: [(method: String, path: String, auth: String?, bytes: Int)] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        var body = Data()
        if let s = request.httpBodyStream {
            s.open(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buf.deallocate() }
            while s.hasBytesAvailable { let n = s.read(buf, maxLength: 4096); if n <= 0 { break }; body.append(buf, count: n) }
            s.close()
        } else if let b = request.httpBody { body = b }
        Stub.seen.append((request.httpMethod ?? "", request.url!.path, request.value(forHTTPHeaderField: "Authorization"), body.count))
        let (code, data) = request.httpMethod == "GET" ? Stub.getHandler(request) : Stub.handler(request, body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OTAUploaderTests: XCTestCase {
    private var ipa: URL!
    private let endpoint = try! OTAEndpoint("https://h.example")
    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [Stub.self]; return URLSession(configuration: c)
    }
    override func setUpWithError() throws {
        Stub.seen = []
        Stub.getHandler = { _ in (200, Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)) }
        ipa = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).ipa")
        try Data(repeating: 7, count: 5000).write(to: ipa)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: ipa) }

    func testUploadsIPAThenManifestWithTokenAndReturnsInstallLink() async throws {
        Stub.handler = { _, _ in (201, Data("{}".utf8)) }
        let up = OTAUploader(endpoint: endpoint, token: "TOKEN", session: session)
        let link = try await up.upload(ipa: ipa, bundleIdentifier: "com.x.y", version: "2.0", title: "Y")
        XCTAssertEqual(Stub.seen.map(\.method), ["GET", "PUT", "PUT", "GET"], "hash lookup, IPA, manifest, then the link check")
        XCTAssertTrue(Stub.seen[0].path.contains("/has/"))
        XCTAssertTrue(Stub.seen[1].path.hasSuffix("/app.ipa") && Stub.seen[2].path.hasSuffix("/manifest.plist"))
        XCTAssertEqual(Stub.seen[1].bytes, 5000)
        XCTAssertTrue(Stub.seen.filter { $0.method == "PUT" }.allSatisfy { $0.auth == "Bearer TOKEN" })
        XCTAssertNil(Stub.seen[3].auth, "the link check fetches the public manifest like iOS does, without the token")
        XCTAssertTrue(link.absoluteString.hasPrefix("itms-services://?action=download-manifest&url=https://h.example/ota/"))
        XCTAssertTrue(link.absoluteString.hasSuffix("/manifest.plist"))
    }

    func testManifestAdvertisesTheBuildNumberWhenThereIsOne() async throws {
        var manifest = ""
        Stub.handler = { r, body in if r.url!.path.hasSuffix("manifest.plist") { manifest = String(decoding: body, as: UTF8.self) }; return (201, Data("{}".utf8)) }
        let up = OTAUploader(endpoint: endpoint, token: "TOKEN", session: session)
        _ = try await up.upload(ipa: ipa, bundleIdentifier: "com.x.y", version: "2.0", build: "54", title: "Y")
        XCTAssertTrue(manifest.contains("<key>bundle-version</key><string>54</string>"), manifest)
    }

    func testManifestFallsBackToTheVersionWhenTheBuildIsEmpty() async throws {
        var manifest = ""
        Stub.handler = { r, body in if r.url!.path.hasSuffix("manifest.plist") { manifest = String(decoding: body, as: UTF8.self) }; return (201, Data("{}".utf8)) }
        let up = OTAUploader(endpoint: endpoint, token: "TOKEN", session: session)
        _ = try await up.upload(ipa: ipa, bundleIdentifier: "com.x.y", version: "2.0", build: "", title: "Y")
        XCTAssertTrue(manifest.contains("<key>bundle-version</key><string>2.0</string>"), manifest)
    }

    func testStatusCodesMapToClearErrors() async throws {
        let cases: [(Int, String)] = [(401, "token"), (413, "too large"), (507, "full")]
        for (code, word) in cases {
            Stub.handler = { _, _ in (code, Data()) }
            do {
                _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session)
                    .upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
                XCTFail("expected throw for \(code)")
            } catch {
                XCTAssertTrue(error.localizedDescription.lowercased().contains(word), "\(code): \(error.localizedDescription)")
            }
        }
    }

    func testUnreachableInstallLinkIsReportedWithItsStatusAndCleansUp() async throws {
        Stub.handler = { req, _ in (req.httpMethod == "DELETE" ? 200 : 201, Data("{}".utf8)) }
        Stub.getHandler = { _ in (404, Data("not found".utf8)) }
        do {
            _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session).upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
            XCTFail("should have thrown")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404") && error.localizedDescription.contains("not reachable"), error.localizedDescription)
        }
        XCTAssertTrue(Stub.seen.contains { $0.method == "DELETE" }, "the uploaded files are removed again")
    }

    func testAPageThatIsNotAManifestCountsAsUnreachable() async throws {
        Stub.handler = { _, _ in (201, Data("{}".utf8)) }
        Stub.getHandler = { _ in (200, Data("<html>welcome</html>".utf8)) }
        do {
            _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session).upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
            XCTFail("should have thrown")
        } catch { XCTAssertTrue(error.localizedDescription.contains("not reachable"), error.localizedDescription) }
    }

    func testTokenCheckPassesOn204() async throws {
        Stub.getHandler = { _ in (204, Data()) }
        try await OTAUploader(endpoint: endpoint, token: "T", session: session).checkToken()
        XCTAssertEqual(Stub.seen.last?.path, "/ota-up/health")
        XCTAssertEqual(Stub.seen.last?.auth, "Bearer T")
    }

    func testTokenCheckReportsAWrongTokenOn401() async throws {
        Stub.getHandler = { _ in (401, Data()) }
        do { try await OTAUploader(endpoint: endpoint, token: "T", session: session).checkToken(); XCTFail("should have thrown") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("token"), error.localizedDescription) }
    }

    func testUploadSkipsThePutWhenTheServerAlreadyHasTheFile() async throws {
        Stub.handler = { _, _ in (201, Data("{}".utf8)) }
        Stub.getHandler = { req in
            req.url!.path.contains("/has/") ? (200, Data("{\"id\": \"EXISTINGEXISTINGEXISTING\"}".utf8))
                : (200, Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8))
        }
        let link = try await OTAUploader(endpoint: endpoint, token: "T", session: session)
            .upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
        XCTAssertEqual(Stub.seen.filter { $0.method == "PUT" }.map(\.path), ["/ota-up/u/EXISTINGEXISTINGEXISTING/manifest.plist"],
                       "only the small manifest is sent")
        XCTAssertTrue(link.absoluteString.contains("/ota/EXISTINGEXISTINGEXISTING/manifest.plist"))
    }

    func testAFailureAfterReusingAStoredIPADoesNotDeleteIt() async {
        Stub.handler = { _, _ in (500, Data()) }       // the manifest PUT fails
        Stub.getHandler = { req in
            req.url!.path.contains("/has/") ? (200, Data("{\"id\": \"EXISTINGEXISTINGEXISTING\"}".utf8)) : (200, Data())
        }
        do { _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session).upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t"); XCTFail("expected throw") } catch {}
        XCTAssertFalse(Stub.seen.contains { $0.method == "DELETE" }, "the IPA was there before this run; an earlier install link may still point at it")
    }

    func testTheIPAPutCarriesItsSHA256() async throws {
        var header: String?
        Stub.handler = { req, _ in if req.url!.lastPathComponent == "app.ipa" { header = req.value(forHTTPHeaderField: "X-Wax-SHA256") }; return (201, Data()) }
        _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session).upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
        XCTAssertEqual(header, SHA256.hash(data: Data(repeating: 7, count: 5000)).map { String(format: "%02x", $0) }.joined())
    }

    func testManifestFailureCleansUpTheUploadedIPA() async throws {
        var n = 0
        Stub.handler = { req, _ in
            if req.httpMethod == "DELETE" { return (200, Data()) }
            n += 1; return (n == 1 ? 201 : 500, Data())
        }
        do {
            _ = try await OTAUploader(endpoint: endpoint, token: "T", session: session)
                .upload(ipa: ipa, bundleIdentifier: "a.b", version: "1", title: "t")
            XCTFail("expected throw")
        } catch {}
        XCTAssertEqual(Stub.seen.last?.method, "DELETE")
    }
}
