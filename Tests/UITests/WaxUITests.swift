import XCTest
import Vision

final class WaxUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-firstRun.completed", "YES"]
        if let style = ProcessInfo.processInfo.environment["WAX_AUDIT_STYLE"] {
            app.launchArguments += ["-AppleInterfaceStyle", style]
        }
        if let category = ProcessInfo.processInfo.environment["WAX_AUDIT_TEXT"] {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ title: String) {
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), title)
        button.tap()
    }

    func testNavigationAndReportPreview() throws {
        capture("01-sign-empty")
        tap("Sources")
        capture("02-sources-empty")
        tap("IPA")
        capture("03-library-empty")
        tap("Settings")
        capture("04-settings-top")
        tap("Signing options")
        app.swipeUp()
        capture("05-signing-options")
        tap("Back")
        app.swipeUp()
        capture("06-settings-bottom")
        tap("Report a problem")
        capture("07-report-empty")
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Describe the problem")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Synthetic audit report")
        capture("08-report-keyboard")
        tap("Cancel")
        tap("Report a problem")
        XCTAssertEqual(field.value as? String, "")
        capture("09-report-reset")
        tap("Cancel")
        tap("Replay guide")
        capture("10-guide-replay")
        tap("Skip")
        tap("Settings")
        tap("Certificates & profiles, None yet")
        capture("11-credentials-empty")
    }

    func testAdaptiveScreens() throws {
        capture("adaptive-sign")
        tap("IPA")
        capture("adaptive-library")
        tap("Settings")
        capture("adaptive-settings-top")
        for _ in 0..<16 {
            if app.buttons["Report a problem"].firstMatch.isHittable { break }
            app.swipeUp()
        }
        capture("adaptive-settings-help")
        tap("Report a problem")
        capture("adaptive-report")
    }

    func testTabTitlesRemainVisibleAtAccessibilitySizes() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        capture("largest-text-tab-labels")
        let screenshot = app.screenshot().image
        let image = try XCTUnwrap(screenshot.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let tabs = ["Sources", "IPA", "Sign", "Settings"].map { app.buttons[$0].firstMatch.frame }
        let top = try XCTUnwrap(tabs.map(\.minY).min())
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: top * scale, width: CGFloat(image.width), height: CGFloat(image.height) - top * scale)))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: crop).perform([request])
        let visibleText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        for title in ["Sources", "IPA", "Sign", "Settings"] {
            XCTAssertTrue(visibleText.localizedCaseInsensitiveContains(title), "Visible tab title: \(title); OCR: \(visibleText)")
        }
        XCTAssertLessThan(tabs.map(\.height).max() ?? 0, 100, "Navigation must leave room for page content")
    }

    func testDeleteConfirmationCanBeCancelled() throws {
        tap("IPA")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Cancel,")).firstMatch
        try XCTSkipIf(!row.exists, "Requires the synthetic Wax UI Cancel library fixture")
        row.tap()
        capture("delete-actions")
        tap("Delete")
        XCTAssertTrue(app.buttons["Delete IPA"].waitForExistence(timeout: 5))
        capture("delete-confirmation")
        tap("Cancel")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture("delete-cancel-preserves-file")
    }

    func testDeleteConfirmationRemovesOnlySelectedFixture() throws {
        tap("IPA")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Delete,")).firstMatch
        try XCTSkipIf(!row.exists, "Requires the synthetic Wax UI Delete library fixture")
        row.tap()
        tap("Delete")
        tap("Delete IPA")
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Cancel,")).firstMatch.exists)
        capture("delete-confirmed-only-fixture-removed")
    }

    func testAccessibilityAudit() throws {
        capture("accessibility-sign")
        try app.performAccessibilityAudit { issue in
            let attachment = XCTAttachment(string: issue.detailedDescription)
            attachment.name = "accessibility-issue"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return false
        }
    }
}
