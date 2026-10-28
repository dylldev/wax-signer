import XCTest
@testable import SourcesKit

final class IPADownloaderTests: XCTestCase {
    private var dir: URL!
    private let ipaBytes = Data("PK\u{03}\u{04}".utf8) + Data(repeating: 7, count: 4096)

    private func app(_ url: String = "https://e.test/a.ipa") -> SourceApp {
        SourceApp(id: "com.a@1", name: "Alpha", bundleID: "com.a", version: "1", size: nil, iconURL: nil,
                  downloadURL: URL(string: url)!, date: nil, summary: "", developer: "")
    }
    private var downloader: IPADownloader {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]
        return IPADownloader(session: URLSession(configuration: c))
    }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StubProtocol.seen = []; StubProtocol.failure = nil
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func files() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] }

    func testReservingTheSameNameTwiceReturnsDistinctFiles() throws {
        let first = try IPADownloader.reserveDestination(in: dir, name: "Alpha", version: "1")
        let second = try IPADownloader.reserveDestination(in: dir, name: "Alpha", version: "1")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "Alpha-1.ipa")
        XCTAssertEqual(second.lastPathComponent, "Alpha-1-2.ipa")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testSuccessWritesAnIPAAndReportsProgress() async throws {
        StubProtocol.handler = { _ in (200, ["Content-Length": "\(self.ipaBytes.count)"], self.ipaBytes) }
        let last = LockedBox(0.0)
        let url = try await downloader.download(app(), to: dir, refetch: { self.app() }, progress: { last.value = $0 })
        XCTAssertEqual(try Data(contentsOf: url), ipaBytes)
        XCTAssertEqual(url.pathExtension, "ipa")
        XCTAssertEqual(last.value, 1.0, accuracy: 0.001)
        XCTAssertEqual(files().count, 1)
    }

    func testExpiredLink403TriggersOneRefetchThenSucceeds() async throws {
        let n = LockedBox(0)
        StubProtocol.handler = { r in
            if r.url!.absoluteString.contains("old") { return (403, [:], Data()) }
            return (200, ["Content-Length": "\(self.ipaBytes.count)"], self.ipaBytes)
        }
        let refetched = LockedBox(0)
        _ = try await downloader.download(app("https://e.test/old.ipa"), to: dir,
                                          refetch: { refetched.value += 1; return self.app("https://e.test/fresh.ipa") }, progress: { _ in _ = n })
        XCTAssertEqual(refetched.value, 1)
        XCTAssertEqual(files().count, 1)
    }

    func testSecond403AfterRefetchFailsAndLeavesNothing() async throws {
        StubProtocol.handler = { _ in (403, [:], Data()) }
        do {
            _ = try await downloader.download(app(), to: dir, refetch: { self.app("https://e.test/again.ipa") }, progress: { _ in })
            XCTFail("should throw")
        } catch { XCTAssertEqual(error as? DownloadError, .linkExpired) }
        XCTAssertTrue(files().isEmpty)
    }

    func testInterruptedDownloadLeavesNoFileBehind() async throws {
        StubProtocol.failure = URLError(.networkConnectionLost)
        do { _ = try await downloader.download(app(), to: dir, refetch: { self.app() }, progress: { _ in }); XCTFail("should throw") }
        catch {}
        XCTAssertTrue(files().isEmpty)
    }

    func testResponseThatIsNotAnIPAIsRejected() async throws {
        StubProtocol.handler = { _ in (200, [:], Data("<html>Please log in</html>".utf8)) }
        do { _ = try await downloader.download(app(), to: dir, refetch: { self.app() }, progress: { _ in }); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? DownloadError, .notAnIPA) }
        XCTAssertTrue(files().isEmpty)
    }

    func testHTTPErrorIsReportedWithItsStatus() async throws {
        StubProtocol.handler = { _ in (500, [:], Data()) }
        do { _ = try await downloader.download(app(), to: dir, refetch: { self.app() }, progress: { _ in }); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? DownloadError, .http(500)) }
    }

    /// The download succeeded -- the server answered 200 and the IPA is valid. Failing to move the system temp file
    /// somewhere we own is a local filesystem problem, and reporting it as "HTTP 200" (or "HTTP 0") sends the user
    /// looking at the source instead of at their own storage.
    func testFailureToKeepTheDownloadIsReportedAsSuchNotAsAnHTTPError() async throws {
        StubProtocol.handler = { _ in (200, ["Content-Length": "\(self.ipaBytes.count)"], self.ipaBytes) }
        let badStaging = dir.appendingPathComponent("no-such-parent")
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]
        let d = IPADownloader(session: URLSession(configuration: c), stagingDirectory: { badStaging })
        do {
            _ = try await d.download(app(), to: dir, refetch: { self.app() }, progress: { _ in })
            XCTFail("a download we could not keep must not report success")
        } catch {
            XCTAssertEqual(error as? DownloadError, .notSaved, "got \(error)")
        }
        XCTAssertTrue(files().isEmpty)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var _v: T
    init(_ v: T) { _v = v }
    var value: T { get { lock.withLock { _v } } set { lock.withLock { _v = newValue } } }
}
