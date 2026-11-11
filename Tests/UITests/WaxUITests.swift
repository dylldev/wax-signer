import XCTest
import Vision
import InstallKit
import CryptoKit

final class WaxUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureRoot: URL?
    private var fixtureEntries: [LibraryEntry] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        if name.contains("testDeleteConfirmation") || name.contains("testSettingsAndLibraryBottomRows")
            || name.contains("testDarkPopulatedLibrary") || name.contains("testLibraryCardsShareOneColumn") {
            if app.state != .notRunning { app.terminate() }
            try prepareDeletionFixtures()
        }
        app.launchArguments = ["-firstRun.completed", "YES"]
        app.launch()
    }

    /// UI tests run in fresh simulator containers. Seed only the owned app, before launching it.
    private func prepareDeletionFixtures() throws {
        #if targetEnvironment(simulator)
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let applications = home.deletingLastPathComponent()
        guard home.path.contains("/data/Containers/Data/Application/"), applications.lastPathComponent == "Application" else {
            throw XCTSkip("Cannot locate the simulator test app container")
        }
        let containers = try FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil)
        let matches = containers.filter { container in
            let metadata = container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let bytes = try? Data(contentsOf: metadata),
                  let values = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else { return false }
            return values["MCMMetadataIdentifier"] as? String == "io.github.dylldev.wax"
        }
        let container = try XCTUnwrap(matches.count == 1 ? matches.first : nil, "Expected one normal Wax simulator container")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TestApp", withExtension: "ipa"))
        var fixtures: [(name: String, bytes: Data)] = []
        for suffix in ["Cancel", "Delete"] {
            var bytes = try Data(contentsOf: fixture)
            let comment = Data(suffix.utf8)
            guard bytes.count >= 22, bytes.suffix(22).prefix(4) == Data([0x50, 0x4b, 0x05, 0x06]), bytes.suffix(2) == Data([0, 0]) else {
                return XCTFail("Expected the owned fixture's empty ZIP comment")
            }
            bytes[bytes.count - 2] = UInt8(comment.count); bytes.append(comment)
            fixtures.append(("Wax UI " + suffix, bytes))
        }
        let hashes = Dictionary(uniqueKeysWithValues: fixtures.map { fixture in
            (fixture.name, SHA256.hash(data: fixture.bytes).map { String(format: "%02x", $0) }.joined())
        })
        let library = IPALibrary(root: container.appendingPathComponent("Library/Application Support/Library", isDirectory: true))
        let existing = library.entries(.unsigned) + library.entries(.signed)
        guard library.issue == nil, existing.allSatisfy({ $0.kind == .unsigned && hashes[$0.name] != nil && hashes[$0.name] == $0.sha256 }) else {
            throw XCTSkip("Preserving a simulator library that contains other records")
        }
        for fixture in fixtures {
            let source = FileManager.default.temporaryDirectory.appendingPathComponent("wax-ui-\(UUID()).ipa")
            try fixture.bytes.write(to: source)
            defer { try? FileManager.default.removeItem(at: source) }
            _ = try library.save(file: source, kind: .unsigned, name: fixture.name, version: "1.0",
                                 bundleID: "io.github.dylldev.wax.uitest", provenance: .fileImport)
        }
        fixtureRoot = container.appendingPathComponent("Library/Application Support/Library", isDirectory: true)
        fixtureEntries = library.entries(.unsigned)
        #else
        throw XCTSkip("Synthetic deletion fixtures are simulator-only")
        #endif
    }

    private func verifyDeletionFiles(confirmed: Bool) throws {
        let library = IPALibrary(root: try XCTUnwrap(fixtureRoot))
        let expected = fixtureEntries.filter { !confirmed || $0.name == "Wax UI Cancel" }
        XCTAssertEqual(Set(library.entries(.unsigned).map(\.id)), Set(expected.map(\.id)))
        for entry in expected {
            let data = try Data(contentsOf: library.url(for: entry))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), entry.sha256)
        }
        if confirmed {
            let removed = try XCTUnwrap(fixtureEntries.first { $0.name == "Wax UI Delete" })
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(for: removed).path))
        }
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

    func testInactiveTabsStayOutOfAccessibilityTree() throws {
        capture("inactive-settings-baseline")
        XCTAssertFalse(app.staticTexts["Setup"].exists, "The inactive Settings Setup heading must not appear on Sign")
        tap("Settings")
        XCTAssertTrue(app.staticTexts["Setup"].exists)
        tap("Sign")
        XCTAssertFalse(app.staticTexts["Setup"].exists)
    }

    func testTabSwitchKeepsSettingsNavigationState() throws {
        tap("Settings")
        tap("Signing options")
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 5))
        tap("Sign")
        tap("Settings")
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 5), "Switching tabs must preserve Settings navigation")
        capture("settings-state-after-tab-switch")
    }

    func testOnlyWaxTabBarIsVisible() throws {
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "The native container must not show a second tab bar")
        for title in ["Sources", "IPA", "Sign", "Settings"] {
            XCTAssertEqual(app.buttons.matching(identifier: title).count, 1)
        }
        capture("single-wax-tab-bar")
    }

    func testSignSetupAvoidsRedundantHeading() {
        app.terminate()
        app.launchArguments += ["-installHost", "server", "-otaServer", ""]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Set up an install host")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Before you can sign"].exists)
        capture("sign-without-redundant-setup-heading")
    }

    func testInstallHostOpensDirectlyFromSign() {
        let host = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Install host")).firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        XCTAssertTrue(app.navigationBars["Install host"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Installability Passport"].exists)
        XCTAssertFalse(app.buttons["Prepare signing preview"].exists)
        capture("direct-install-host")
    }

    /// Run after building/installing WaxDev on this simulator; normal-only runs can select the other cases.
    func testDeveloperToolsStayInSettingsAndAnimationPreviewResponds() {
        app.terminate()
        app = XCUIApplication(bundleIdentifier: "io.github.dylldev.wax.dev")
        app.launchArguments = ["-firstRun.completed", "YES"]
        app.launch()
        XCTAssertFalse(app.buttons["Prepare signing preview"].exists)
        XCTAssertFalse(app.staticTexts["Installability Passport"].exists)
        tap("Settings")
        let developer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Developer")).firstMatch
        for _ in 0..<5 where !developer.isHittable { app.swipeUp() }
        XCTAssertTrue(developer.isHittable)
        developer.tap()
        XCTAssertTrue(app.navigationBars["Developer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Prepare signing preview"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Certificate tests")).firstMatch.exists)
        tap("Animation preview")
        let progress = app.sliders["Preview progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        progress.adjust(toNormalizedSliderPosition: 0.25)
        capture("developer-animation-quarter")
        progress.adjust(toNormalizedSliderPosition: 0.8)
        capture("developer-animation-eighty")
    }

    func testBottomOptionsStayAboveTabBarAtLargestText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Options")).firstMatch
        let sign = app.buttons["Sign"].firstMatch
        for _ in 0..<10 {
            if options.isHittable && options.frame.maxY <= sign.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(options.isHittable)
        XCTAssertLessThanOrEqual(options.frame.maxY, sign.frame.minY)
        capture("largest-text-options-above-tabs")
    }

    func testSettingsAndLibraryBottomRowsStayAboveTabsAtLargestText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("Settings")
        let lastSetting = app.descendants(matching: .any).matching(identifier: "Wax on GitHub").firstMatch
        for _ in 0..<16 {
            if lastSetting.isHittable && lastSetting.frame.maxY <= app.buttons["Settings"].firstMatch.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(lastSetting.isHittable)
        XCTAssertLessThanOrEqual(lastSetting.frame.maxY, app.buttons["Settings"].firstMatch.frame.minY)
        capture("largest-text-settings-bottom-above-tabs")
        tap("IPA")
        let lastName = try XCTUnwrap(fixtureEntries.last).name
        let lastApp = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", lastName + ",")).firstMatch
        // The list is a plain VStack now, so every row is laid out and reachable at this text size.
        for _ in 0..<16 {
            if lastApp.exists, lastApp.isHittable, lastApp.frame.maxY <= app.buttons["IPA"].firstMatch.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(lastApp.isHittable)
        XCTAssertLessThanOrEqual(lastApp.frame.maxY, app.buttons["IPA"].firstMatch.frame.minY)
        capture("largest-text-library-bottom-above-tabs")
    }

    /// A dark library with two saved apps: the state 05 could not capture. Also pins that both shelf rows render.
    /// Every library card shares one leading and one trailing edge, so the shelf reads as a column and not a stagger.
    /// The add row is included: it is the first card and the one a reader compares the rest against.
    func testLibraryCardsShareOneColumn() throws {
        tap("IPA")
        let cards = [
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add an IPA")).firstMatch,
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Cancel,")).firstMatch,
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Delete,")).firstMatch,
        ]
        for card in cards { XCTAssertTrue(card.waitForExistence(timeout: 5)) }
        let frames = cards.map(\.frame)
        for frame in frames.dropFirst() {
            XCTAssertEqual(frame.minX, frames[0].minX, accuracy: 0.5, "Card leading edges must match")
            XCTAssertEqual(frame.maxX, frames[0].maxX, accuracy: 0.5, "Card trailing edges must match")
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 0.5, "Card widths must match")
        }
        capture("library-card-column")
    }

    func testDarkPopulatedLibraryShowsEverySavedApp() throws {
        app.terminate()
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        app.launch()
        tap("IPA")
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Delete,")).firstMatch
        let second = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Cancel,")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertFalse(app.staticTexts["No unsigned apps yet"].exists)
        capture("dark-populated-library")
    }

    func testSigningOptionsKeyboardInput() throws {
        tap("Settings"); tap("Signing options")
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Synthetic UI name")
        XCTAssertEqual(name.value as? String, "Synthetic UI name")
        XCTAssertTrue(app.buttons["Back"].firstMatch.isHittable)
        capture("signing-options-keyboard")
    }

    func testPublicNavigation() throws {
        capture("01-sign")
        tap("Sources"); capture("02-sources")
        tap("IPA"); capture("03-library")
        tap("Settings"); capture("04-settings")
        tap("Signing options"); capture("05-signing-options")
        tap("Back"); tap("Sign"); capture("06-sign-return")
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

    func testCredentialImportSheetClearsDismissedPasswordAndSupportsKeyboard() throws {
        tap("Settings")
        tap("Certificates & profiles, None yet")
        tap("Import credentials")
        XCTAssertTrue(app.buttons["Choose .P12 Certificate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Mobile Provision"].exists)
        let password = app.secureTextFields["Certificate Password"]
        XCTAssertTrue(password.exists)
        let nickname = app.textFields["Custom Nickname"]
        XCTAssertEqual(password.frame.width, nickname.frame.width, accuracy: 1)
        XCTAssertEqual(password.frame.midX, nickname.frame.midX, accuracy: 1)
        // Native field frames describe the text line, excluding the padded touch area.
        password.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -8)).tap()
        app.typeText("temporary-password")
        XCTAssertFalse((password.value as? String ?? "").isEmpty, "The padded edge must focus the password field")
        XCTAssertTrue(app.buttons["Close credential import"].isHittable)
        capture("credential-import-keyboard")
        app.buttons["Close credential import"].tap()
        tap("Import credentials")
        XCTAssertEqual(app.secureTextFields["Certificate Password"].value as? String, "")
        XCTAssertEqual(app.textFields["Custom Nickname"].value as? String, "Optional")
        XCTAssertFalse(app.buttons["Done"].isEnabled)
        capture("credential-import-reset")
        app.buttons["Close credential import"].tap()
    }

    func testCredentialImportSheetLargestText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("Settings")
        tap("Certificates & profiles, None yet")
        tap("Import credentials")
        XCTAssertTrue(app.buttons["Close credential import"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close credential import"].isHittable)
        app.swipeUp()
        let nickname = app.textFields["Custom Nickname"]
        XCTAssertTrue(nickname.isHittable)
        nickname.tap(); nickname.typeText("My signing identity")
        XCTAssertTrue(app.buttons["Close credential import"].isHittable)
        capture("credential-import-largest-text-keyboard")
        app.buttons["Close credential import"].tap()
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
        if !row.exists {
            capture("missing-delete-fixture")
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "missing-fixture-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The prepared cancellation fixture must appear")
        row.tap()
        capture("delete-actions")
        tap("Delete")
        XCTAssertTrue(app.buttons["Delete IPA"].waitForExistence(timeout: 5))
        capture("delete-confirmation")
        tap("Cancel")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        try verifyDeletionFiles(confirmed: false)
        capture("delete-cancel-preserves-file")
    }

    func testDeleteConfirmationRemovesOnlySelectedFixture() throws {
        tap("IPA")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Delete,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The prepared deletion fixture must appear")
        row.tap()
        tap("Delete")
        tap("Delete IPA")
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wax UI Cancel,")).firstMatch.exists)
        try verifyDeletionFiles(confirmed: true)
        capture("delete-confirmed-only-fixture-removed")
    }

    func testAccessibilityAudit() throws {
        capture("accessibility-sign")
        try app.performAccessibilityAudit { issue in
            let attachment = XCTAttachment(string: issue.detailedDescription)
            attachment.name = "accessibility-issue"
            if let element = issue.element {
                let details = XCTAttachment(string: element.debugDescription)
                details.name = "accessibility-element"; details.lifetime = .keepAlways; self.add(details)
            }
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return false
        }
    }
    func testAccessibilityAuditAtLargestText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        try testAccessibilityAudit()
    }

}
