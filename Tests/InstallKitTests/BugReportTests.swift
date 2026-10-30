import XCTest
@testable import InstallKit

final class BugReportTests: XCTestCase {
    private let about = BugReport.About(appVersion: "0.16.3", build: "109", osVersion: "iOS 27.1")

    func testDraftPreviewAndGitHubUseExactlyTheSameText() throws {
        var draft = BugReport.Draft(about: about)
        draft.whatHappened = "Import stopped & showed ?"
        draft.expectedBehavior = "Import finishes."
        XCTAssertTrue(draft.text.contains("Import stopped & showed ?"))
        XCTAssertTrue(draft.text.contains("Import finishes."))
        let url = BugReport.issueURL(report: draft.text)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "body" }?.value, draft.text)
        draft.reset()
        XCTAssertEqual(draft.whatHappened, "")
        XCTAssertEqual(draft.expectedBehavior, "")
        XCTAssertFalse(draft.text.contains("Import stopped"))
    }

    func testIssueFormOpensOnGitHubWithOnlyTheVersionsFilledIn() throws {
        let url = BugReport.issueURL(about: about)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/dylldev/wax-signer/issues/new")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Set(items.map(\.name)), ["labels", "body"])
        XCTAssertEqual(items.first { $0.name == "labels" }?.value, "bug")
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("Wax 0.16.3 (109) · iOS 27.1"))
        XCTAssertTrue(body.contains("What happened"))
    }

    func testAboutLineComesFromTheBundleKeysOnly() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7",
                                   "CFBundleIdentifier": "io.github.dylldev.wax", "WAX_DEFAULT_FEED": "https://secret.example"]
        let about = BugReport.About(infoDictionary: info, osVersion: "iOS 27.1")
        XCTAssertEqual(about, BugReport.About(appVersion: "1.2", build: "7", osVersion: "iOS 27.1"))
        let link = BugReport.issueURL(about: about).absoluteString.removingPercentEncoding ?? ""
        XCTAssertFalse(link.contains("secret.example"))
        XCTAssertFalse(link.contains("io.github.dylldev"))
        XCTAssertEqual(BugReport.About(infoDictionary: [:], osVersion: "iOS 27.1").appVersion, "unknown")
    }

    func testShakeAsksOnlyWhenNothingElseIsGoingOn() {
        let calm = ShakeGate.Context(presenting: false, somethingOnTop: false, editingText: false, busy: false)
        XCTAssertTrue(ShakeGate.shouldOpen(calm))
        var c = calm; c.presenting = true; XCTAssertFalse(ShakeGate.shouldOpen(c), "A second shake must not stack a second prompt")
        c = calm; c.somethingOnTop = true; XCTAssertFalse(ShakeGate.shouldOpen(c), "Never cover a picker, password sheet, alert or the guide")
        c = calm; c.editingText = true; XCTAssertFalse(ShakeGate.shouldOpen(c), "Never interrupt typing, such as a password")
        c = calm; c.busy = true; XCTAssertFalse(ShakeGate.shouldOpen(c), "Never interrupt signing or installing")
    }
}
