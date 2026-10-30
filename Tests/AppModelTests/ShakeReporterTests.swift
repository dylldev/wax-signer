import XCTest
@testable import LocalIPASigner

@MainActor
final class ShakeReporterTests: XCTestCase {
    func testPreferencePersistsAndManualReportRemainsAvailable() {
        let name = "ShakeReporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reporter = ShakeReporter(defaults: defaults, somethingPresented: { false })
        XCTAssertTrue(reporter.shakeEnabled)
        reporter.shakeEnabled = false
        reporter.shaken(busy: false, guideShowing: false, editingText: false)
        XCTAssertFalse(reporter.isPresenting)
        XCTAssertFalse(ShakeReporter(defaults: defaults).shakeEnabled)
        reporter.present()
        XCTAssertTrue(reporter.isPresenting)
    }

    func testCancellationDiscardsDraftAndRepeatedShakePreservesCurrentDraft() {
        let name = "ShakeReporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reporter = ShakeReporter(defaults: defaults, somethingPresented: { false })
        reporter.shakeEnabled = true
        reporter.shaken(busy: false, guideShowing: false, editingText: false)
        reporter.draft.whatHappened = "Draft"
        reporter.shaken(busy: false, guideShowing: false, editingText: false)
        reporter.present()
        XCTAssertEqual(reporter.draft.whatHappened, "Draft")
        reporter.dismiss()
        XCTAssertFalse(reporter.isPresenting)
        XCTAssertEqual(reporter.draft.whatHappened, "")
        reporter.shaken(busy: true, guideShowing: false, editingText: false)
        XCTAssertFalse(reporter.isPresenting)
        reporter.shaken(busy: false, guideShowing: true, editingText: false)
        XCTAssertFalse(reporter.isPresenting)
        reporter.shaken(busy: false, guideShowing: false, editingText: true)
        XCTAssertFalse(reporter.isPresenting)
    }
}
