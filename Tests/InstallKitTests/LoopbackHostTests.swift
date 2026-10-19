import XCTest
import Security
@testable import InstallKit

/// A throwaway self-signed certificate for "localhost" (password "wax"), valid 100 years. Test use only.
enum TestTLS {
    static let p12 = Data(base64Encoded: "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")!
    static let password = "wax"
}

private final class TrustingDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard c.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = c.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

final class LoopbackHostTests: XCTestCase {
    private var ipa: URL!
    private var payload: Data!
    private var session: URLSession!
    private var host: LoopbackHost!

    override func setUpWithError() throws {
        payload = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        ipa = FileManager.default.temporaryDirectory.appendingPathComponent("lb-\(UUID().uuidString).ipa")
        try payload.write(to: ipa)
        session = URLSession(configuration: .ephemeral, delegate: TrustingDelegate(), delegateQueue: nil)
        host = try LoopbackHost(p12: TestTLS.p12, password: TestTLS.password, host: "localhost")
    }
    override func tearDownWithError() throws { host.stop(); try? FileManager.default.removeItem(at: ipa) }

    private func manifestURL(from link: URL) throws -> URL {
        let value = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value)
        return try XCTUnwrap(URL(string: value))
    }
    private func publish() async throws -> (link: URL, manifest: URL, ipa: URL) {
        let link = try await host.publish(ipa: ipa, bundleIdentifier: "a.b", version: "1", build: "3", title: "T", progress: { _ in })
        let manifest = try manifestURL(from: link)
        return (link, manifest, manifest.deletingLastPathComponent().appendingPathComponent("app.ipa"))
    }

    func testLinkNamesTheManifestOnTheLoopbackHostWithAPort() async throws {
        let r = try await publish()
        XCTAssertTrue(r.link.absoluteString.hasPrefix("itms-services://?action=download-manifest&url=https://localhost:"))
        XCTAssertNotNil(r.manifest.port)
    }

    func testServesTheManifestAndTheWholeIPAOverTLS() async throws {
        let r = try await publish()
        let (m, mr) = try await session.data(from: r.manifest)
        XCTAssertEqual((mr as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: m, as: UTF8.self)
        XCTAssertTrue(text.contains("<key>bundle-identifier</key><string>a.b</string>"))
        XCTAssertTrue(text.contains(r.ipa.absoluteString), "the manifest points at this server's IPA")
        XCTAssertTrue(text.contains("<string>3</string>"), "the build number is the advertised bundle version")
        let (body, br) = try await session.data(from: r.ipa)
        XCTAssertEqual((br as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(body, payload)
    }

    func testServedIPAIsTrueOnlyOnceIOSHasFetchedTheFileFromThisPhone() async throws {
        let r = try await publish()
        XCTAssertFalse(host.servedIPA, "a link that was opened but never fetched here would mean the install came from elsewhere")
        _ = try await session.data(from: r.ipa)
        XCTAssertTrue(host.servedIPA)
    }

    func testHeadReportsTheLengthWithoutABody() async throws {
        let r = try await publish()
        var req = URLRequest(url: r.ipa); req.httpMethod = "HEAD"
        let (body, resp) = try await session.data(for: req)
        XCTAssertFalse(host.servedIPA, "a HEAD request fetches nothing, so it does not count as the IPA being served")
        let http = try XCTUnwrap(resp as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), String(payload.count))
        XCTAssertTrue(body.isEmpty)
    }

    func testAByteRangeIsAnswered206WithTheRightBytes() async throws {
        let r = try await publish()
        var req = URLRequest(url: r.ipa); req.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        let (body, resp) = try await session.data(for: req)
        let http = try XCTUnwrap(resp as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 10-19/\(payload.count)")
        XCTAssertEqual(body, payload.subdata(in: 10..<20))
        var open = URLRequest(url: r.ipa); open.setValue("bytes=\(payload.count - 5)-", forHTTPHeaderField: "Range")
        let (tail, _) = try await session.data(for: open)
        XCTAssertEqual(tail, payload.suffix(5))
    }

    func testARangePastTheEndIs416() async throws {
        let r = try await publish()
        var req = URLRequest(url: r.ipa); req.setValue("bytes=\(payload.count + 10)-", forHTTPHeaderField: "Range")
        let (_, resp) = try await session.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 416)
    }

    func testAnyOtherPathIs404AndOtherMethodsAre405() async throws {
        let r = try await publish()
        var wrong = URLComponents(url: r.ipa, resolvingAgainstBaseURL: false)!; wrong.path = "/not-the-id/app.ipa"
        let (_, resp) = try await session.data(from: try XCTUnwrap(wrong.url))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 404)
        var post = URLRequest(url: r.ipa); post.httpMethod = "POST"
        let (_, p) = try await session.data(for: post)
        XCTAssertEqual((p as? HTTPURLResponse)?.statusCode, 405)
    }

    func testWaitForTransferTimesOutWhenNothingIsFetched() async throws {
        _ = try await publish()
        let done = await host.waitForTransfer(timeout: 0.4)
        XCTAssertFalse(done)
    }

    func testWaitForTransferSeesTheWholeFileGoOutButNotAMiddleSlice() async throws {
        let r = try await publish()
        var slice = URLRequest(url: r.ipa); slice.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        _ = try await session.data(for: slice)
        let partial = await host.waitForTransfer(timeout: 0.4)
        XCTAssertFalse(partial, "a slice from the middle is not the end of the file")
        _ = try await session.data(from: r.ipa)
        let whole = await host.waitForTransfer(timeout: 2)
        XCTAssertTrue(whole)
    }

    func testASuffixOnlyRangeDoesNotCountAsTheWholeFile() async throws {
        let r = try await publish()
        var tail = URLRequest(url: r.ipa); tail.setValue("bytes=-1", forHTTPHeaderField: "Range")
        _ = try await session.data(for: tail)
        let done = await host.waitForTransfer(timeout: 0.4)
        XCTAssertFalse(done)
    }

    func testRangesInAnyOrderThatCoverTheFileCountAsTheWholeFile() async throws {
        let r = try await publish()
        let mid = payload.count / 2
        for spec in ["bytes=\(mid)-", "bytes=0-\(mid - 1)"] {
            var req = URLRequest(url: r.ipa); req.setValue(spec, forHTTPHeaderField: "Range")
            _ = try await session.data(for: req)
        }
        let done = await host.waitForTransfer(timeout: 2)
        XCTAssertTrue(done)
    }

    func testPublishingAgainStartsTheTransferCountOver() async throws {
        let r = try await publish()
        _ = try await session.data(from: r.ipa)
        let first = await host.waitForTransfer(timeout: 2)
        XCTAssertTrue(first)
        _ = try await publish()
        let second = await host.waitForTransfer(timeout: 0.3)
        XCTAssertFalse(second, "a new link has not been fetched yet")
    }

    func testWaitingAfterStopReturnsFalseAndForgetsWhatWasSent() async throws {
        let r = try await publish()
        _ = try await session.data(from: r.ipa)
        host.stop()
        let done = await host.waitForTransfer(timeout: 0.3)
        XCTAssertFalse(done, "a closed host has delivered nothing anyone can rely on")
    }

    func testMergingRanges() {
        XCTAssertEqual(LoopbackHost.merged([0...4], adding: 5...9), [0...9])
        XCTAssertEqual(LoopbackHost.merged([0...4], adding: 7...9), [0...4, 7...9])
        XCTAssertEqual(LoopbackHost.merged([5...9], adding: 0...2), [0...2, 5...9])
        XCTAssertEqual(LoopbackHost.merged([0...2, 5...9], adding: 3...4), [0...9])
    }

    func testTheTimeoutMessageSaysWhatHappenedAndWhatToTry() {
        let never = LoopbackHost.transferFailureMessage(served: false)
        XCTAssertTrue(never.contains("never asked this phone"), never)
        XCTAssertTrue(never.contains("My server"), never)
        let cut = LoopbackHost.transferFailureMessage(served: true)
        XCTAssertTrue(cut.contains("stopped before the end"), cut)
    }

    func testStopClosesTheListener() async throws {
        let r = try await publish()
        host.stop()
        do { _ = try await session.data(from: r.manifest); XCTFail("expected the connection to fail") } catch {}
    }

    func testABadCertificateIsRefusedUpFront() {
        XCTAssertThrowsError(try LoopbackHost(p12: Data([1, 2, 3]), password: "x", host: "localhost"))
        XCTAssertThrowsError(try LoopbackHost(p12: TestTLS.p12, password: "wrong", host: "localhost"))
    }

    func testTheListenerStopsItselfAfterItsLifetime() async throws {
        let short = try LoopbackHost(p12: TestTLS.p12, password: TestTLS.password, host: "localhost", lifetime: 0.5)
        let link = try await short.publish(ipa: ipa, bundleIdentifier: "a.b", version: "1", build: "1", title: "T", progress: { _ in })
        let manifest = try manifestURL(from: link)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        do { _ = try await session.data(from: manifest); XCTFail("expected the connection to fail") } catch {}
        short.stop()
    }

    func testOnlyANameThatResolvesToLoopbackIsAccepted() {
        XCTAssertTrue(LoopbackHost.resolvesOnlyToLoopback("localhost"))
        XCTAssertTrue(LoopbackHost.resolvesOnlyToLoopback("127.0.0.1"))
        XCTAssertFalse(LoopbackHost.resolvesOnlyToLoopback("8.8.8.8"), "a public address would send the install link off the phone")
        XCTAssertFalse(LoopbackHost.resolvesOnlyToLoopback("name-that-does-not-exist.invalid"))
    }

    func testPublishRefusesANameThatIsNotLoopback() async throws {
        let bad = try LoopbackHost(p12: TestTLS.p12, password: TestTLS.password, host: "8.8.8.8")
        do { _ = try await bad.publish(ipa: ipa, bundleIdentifier: "a.b", version: "1", build: "1", title: "T", progress: { _ in }); XCTFail("expected throw") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("this iphone"), error.localizedDescription) }
    }
    func testIncompleteDeliveryNeverClaimsToObserveTheOSInstallOutcome() {
        for served in [true, false] {
            let text = LoopbackHost.transferFailureMessage(served: served)
            XCTAssertFalse(text.contains("nothing was installed"))
            XCTAssertFalse(text.contains("installation failed"))
            XCTAssertTrue(text.contains("could not confirm installation") || text.contains("outcome is unknown"))
        }
    }

}
