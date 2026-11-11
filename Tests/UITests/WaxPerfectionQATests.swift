import XCTest

/// Visual QA harness: same device (iPhone 17 simulator), same launch state,
/// assertable geometry. Tolerances ignore anti-aliasing noise and fail on real drift.
final class WaxPerfectionQATests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-firstRun.completed", "YES"]
    }

    override func tearDown() {
        if app.state == .runningForeground { app.terminate() }
        super.tearDown()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tabFrame(_ title: String) -> CGRect {
        app.buttons[title].firstMatch.frame
    }

    func testTabBarEqualWidths() {
        app.launch()
        XCTAssertTrue(app.buttons["Sign"].waitForExistence(timeout: 5))
        let titles = ["Sources", "IPA", "Sign", "Settings"]
        let widths = titles.map { tabFrame($0).width }
        let first = widths.first ?? 0
        for w in widths {
            XCTAssertEqual(w, first, accuracy: 1.5, "Tab widths must match: \(widths)")
        }
        capture("qa-tab-bar-light-default")
    }

    func testPrimaryButtonMeetsTouchTarget() {
        app.launch()
        let title = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Sign empty primary must exist at default size")
        XCTAssertGreaterThanOrEqual(title.frame.height, 54 - 1.5)
        XCTAssertGreaterThanOrEqual(title.frame.width, 200)
        capture("qa-sign-primary-light-default")
    }

    func testNoOverlapBetweenContentAndTabBar() {
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        let tabTop = tabFrame("Settings").minY
        // The first visible content header must sit above the bar, not under it.
        let header = app.staticTexts["Sign"].firstMatch
        if header.exists {
            XCTAssertLessThanOrEqual(header.frame.maxY, tabTop + 1.5)
        }
        capture("qa-no-overlap-light-default")
    }

    func testAccessibilityLabelsOnEveryTab() {
        app.launch()
        for title in ["Sources", "IPA", "Sign", "Settings"] {
            let button = app.buttons[title].firstMatch
            XCTAssertTrue(button.exists, title)
            XCTAssertFalse(button.label.isEmpty, "\(title) label must be visible")
        }
        capture("qa-tab-labels-light-default")
    }
}
