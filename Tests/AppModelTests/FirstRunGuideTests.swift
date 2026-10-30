import XCTest
@testable import LocalIPASigner

@MainActor
final class FirstRunGuideTests: XCTestCase {
    func testSkipPersistsAndReplayDoesNotEraseCompletion() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = FirstRunGuideModel(defaults: defaults, hasLegacyState: false)
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.stage, .permissions)
        model.continueToGuide()
        XCTAssertEqual(model.stage, .tutorial)
        model.skip()
        XCTAssertFalse(model.isPresented)
        let next = FirstRunGuideModel(defaults: defaults, hasLegacyState: false)
        XCTAssertFalse(next.isPresented)
        next.replay()
        XCTAssertTrue(next.isPresented)
        XCTAssertEqual(next.stage, .tutorial)
        XCTAssertTrue(defaults.bool(forKey: FirstRunGuideModel.completedKey))
        next.finish()
        XCTAssertFalse(next.isPresented)
    }

    func testLegacyDecisionIsRecordedBeforeStorageAppears() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(FirstRunGuideModel.detectLegacyState(savedPreferences: [:], storageURLs: [url]))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertTrue(FirstRunGuideModel.detectLegacyState(savedPreferences: [:], storageURLs: [url]))
        XCTAssertTrue(FirstRunGuideModel.detectLegacyState(savedPreferences: ["expiryReminders": true], storageURLs: []))
        let old = FirstRunGuideModel(defaults: defaults, hasLegacyState: true)
        XCTAssertFalse(old.isPresented)
        XCTAssertFalse(FirstRunGuideModel(defaults: defaults, hasLegacyState: false).isPresented)
    }

    func testAFirstRunClosedBeforeSkipShowsTheGuideAgain() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(FirstRunGuideModel(defaults: defaults, hasLegacyState: false).isPresented)
        // By the next launch the models have created their folders; the earlier decision still stands.
        let relaunch = FirstRunGuideModel(defaults: defaults, hasLegacyState: true)
        XCTAssertTrue(relaunch.isPresented)
        relaunch.finish()
        XCTAssertFalse(FirstRunGuideModel(defaults: defaults, hasLegacyState: false).isPresented)
    }

    func testReducedMotionKeepsExamplesStatic() {
        XCTAssertFalse(FirstRunGuideModel.animatesExamples(reduceMotion: true))
        XCTAssertTrue(FirstRunGuideModel.animatesExamples(reduceMotion: false))
    }
}
