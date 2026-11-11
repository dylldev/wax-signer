import XCTest

final class SigningFieldLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-firstRun.completed", "YES"]
        app.launch()
    }

    private func openSettings() {
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSigningFieldsUseFullReadableWidth() {
        openSettings()
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Signing options")).firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(name.frame.width, app.frame.width * 0.7, "The input should have its own row instead of sharing a narrow row with its label")
        name.tap()
        name.typeText("A longer app name that needs room")
        XCTAssertEqual(name.value as? String, "A longer app name that needs room")
        capture("signing-field-readable-width-and-keyboard")
    }

    func testFeedFieldUsesFullReadableWidthAtLargestText() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-installHost", "phone"]
        app.launch()
        openSettings()
        let host = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Install host")).firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        let feed = app.textFields["Certificate feed"]
        for _ in 0..<8 where !feed.isHittable { app.swipeUp() }
        XCTAssertTrue(feed.isHittable)
        XCTAssertGreaterThan(feed.frame.width, app.frame.width * 0.7, "Long URLs need a full-width field at large text sizes")
        capture("install-feed-largest-text-readable-width")
    }
}
