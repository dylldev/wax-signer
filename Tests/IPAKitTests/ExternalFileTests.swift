import XCTest
@testable import IPAKit

/// Importing from Files / iCloud Drive: the file may be a placeholder, unreadable, or gone.
/// A fake `UbiquityProbe` stands in for iCloud, which cannot be driven from a unit test.
final class ExternalFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("extfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ bytes: String = "hello") throws -> URL {
        let url = dir.appendingPathComponent("f.bin")
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// Fake iCloud: reports `notDownloaded` until `startDownload` was called and `polls` polls have passed.
    private final class FakeCloud {
        var started = 0
        var polls = 0
        let pollsUntilCurrent: Int?
        let startError: Error?
        let failure: Error?
        init(pollsUntilCurrent: Int?, startError: Error? = nil, failure: Error? = nil) {
            self.pollsUntilCurrent = pollsUntilCurrent; self.startError = startError; self.failure = failure
        }
        var probe: UbiquityProbe {
            let me = self
            return UbiquityProbe(
                status: { _ in
                    guard me.started > 0 else { return .notDownloaded }
                    me.polls += 1
                    if let n = me.pollsUntilCurrent, me.polls > n { return .current }
                    return .notDownloaded
                },
                startDownload: { _ in
                    me.started += 1
                    if let error = me.startError { throw error }
                },
                downloadError: { _ in me.failure })
        }
    }

    func testReadsAnOrdinaryFile() throws {
        let url = try file("abc")
        let text = try ExternalFile.withReadAccess(to: url) { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(text, "abc")
    }

    func testPlaceholderIsDownloadedBeforeTheBodyRuns() throws {
        let url = try file()
        let cloud = FakeCloud(pollsUntilCurrent: 3)
        var messages: [String] = []
        var bodyRanAfterDownload = false
        try ExternalFile.withReadAccess(to: url, probe: cloud.probe, timeout: 5, pollInterval: 0.01,
                                        progress: { messages.append($0) }) { _ in
            bodyRanAfterDownload = cloud.started == 1 && cloud.polls > 3
        }
        XCTAssertTrue(bodyRanAfterDownload)
        XCTAssertEqual(cloud.started, 1, "download requested exactly once")
        XCTAssertTrue(messages.contains { $0.localizedCaseInsensitiveContains("download") }, "\(messages)")
    }

    func testNeverDownloadedTimesOutAndDoesNotRunTheBody() throws {
        let url = try file()
        var ran = false
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url, probe: FakeCloud(pollsUntilCurrent: nil).probe,
                                                             timeout: 0.3, pollInterval: 0.02) { _ in ran = true }) {
            guard case .downloadTimedOut(let name, _) = $0 as? ExternalFileError else { return XCTFail("\($0)") }
            XCTAssertEqual(name, "f.bin")
        }
        XCTAssertFalse(ran)
    }

    func testDownloadErrorIsReportedWithItsDetail() throws {
        let url = try file()
        let failure = NSError(domain: NSCocoaErrorDomain, code: 4353, userInfo: [NSLocalizedDescriptionKey: "no network"])
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url, probe: FakeCloud(pollsUntilCurrent: nil, failure: failure).probe,
                                                             timeout: 2, pollInterval: 0.01) { _ in }) {
            guard case .downloadFailed(_, let detail) = $0 as? ExternalFileError else { return XCTFail("\($0)") }
            XCTAssertTrue(detail.contains("no network"), detail)
        }
    }

    func testStartDownloadFailureIsReported() throws {
        let url = try file()
        let cloud = FakeCloud(pollsUntilCurrent: 1, startError: NSError(domain: "x", code: 9, userInfo: [NSLocalizedDescriptionKey: "refused"]))
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url, probe: cloud.probe, timeout: 1, pollInterval: 0.01) { _ in }) {
            guard case .downloadFailed(_, let detail) = $0 as? ExternalFileError else { return XCTFail("\($0)") }
            XCTAssertTrue(detail.contains("refused"), detail)
        }
    }

    func testMissingFileIsNotFound() {
        let url = dir.appendingPathComponent("gone.p12")
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url) { try Data(contentsOf: $0) }) {
            XCTAssertEqual($0 as? ExternalFileError, .notFound("gone.p12"))
        }
    }

    func testUnreadableFileIsAccessDenied() throws {
        let url = try file()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url) { try Data(contentsOf: $0) }) {
            XCTAssertEqual($0 as? ExternalFileError, .accessDenied("f.bin"))
        }
    }

    func testErrorsFromTheBodyAreNotRewrapped() throws {
        let url = try file()
        struct Boom: Error, Equatable {}
        XCTAssertThrowsError(try ExternalFile.withReadAccess(to: url) { _ in throw Boom() }) {
            XCTAssertEqual($0 as? Boom, Boom())
        }
    }

    func testDescriptionsNameTheFileAndTheCause() {
        let all: [ExternalFileError] = [
            .accessDenied("a.p12"), .notFound("a.p12"), .downloadTimedOut("a.p12", seconds: 60),
            .downloadFailed("a.p12", detail: "offline"), .unreadable("a.p12", domain: "D", code: 7, detail: "odd"),
        ]
        for e in all {
            let text = e.errorDescription ?? ""
            XCTAssertTrue(text.contains("a.p12"), text)
            XCTAssertGreaterThan(text.count, 25, text)
        }
        XCTAssertTrue(ExternalFileError.unreadable("a", domain: "D", code: 7, detail: "odd").errorDescription!.contains("D 7"))
    }

    // MARK: whole IPA import

    func testInspectExternalReportsATimedOutDownloadAsAnUnreadableFileNotAnArchiveError() throws {
        let url = dir.appendingPathComponent("app.ipa")
        try Data("PK".utf8).write(to: url)
        XCTAssertThrowsError(try IPAInspector.inspect(externalURL: url, probe: FakeCloud(pollsUntilCurrent: nil).probe,
                                                      timeout: 0.2, pollInterval: 0.02)) {
            guard case .unreadable(let text) = $0 as? IPAError else { return XCTFail("\($0)") }
            XCTAssertTrue(text.contains("app.ipa"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("not a valid zip"), "must not blame the archive: \(text)")
        }
    }

    func testInspectExternalStillValidatesTheArchive() throws {
        let url = dir.appendingPathComponent("junk.ipa")
        try Data("not a zip at all".utf8).write(to: url)
        XCTAssertThrowsError(try IPAInspector.inspect(externalURL: url)) {
            XCTAssertEqual($0 as? IPAError, .notAZip)
        }
    }

    func testInspectExternalReadsAValidIPAAfterDownload() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/Info.plist", try infoPlist([
            "CFBundleIdentifier": "com.example.demo", "CFBundleExecutable": "Demo", "CFBundleDisplayName": "Demo",
            "CFBundleShortVersionString": "2.0", "CFBundleVersion": "9",
        ]))
        z.add("Payload/Demo.app/Demo", Data([1]))
        let url = dir.appendingPathComponent("demo.ipa")
        try z.write(to: url)
        let cloud = FakeCloud(pollsUntilCurrent: 2)
        let m = try IPAInspector.inspect(externalURL: url, probe: cloud.probe, timeout: 5, pollInterval: 0.01)
        XCTAssertEqual(m.bundleIdentifier, "com.example.demo")
        XCTAssertEqual(m.displayName, "Demo")
        XCTAssertEqual(m.version, "2.0")
        XCTAssertEqual(m.build, "9")
        XCTAssertEqual(cloud.started, 1)
    }

    func testInspectExternalOfADirectoryIsReportedNotSilentlyAccepted() throws {
        XCTAssertThrowsError(try IPAInspector.inspect(externalURL: dir)) {
            guard case .unreadable = $0 as? IPAError else { return XCTFail("\($0)") }
        }
    }
}
