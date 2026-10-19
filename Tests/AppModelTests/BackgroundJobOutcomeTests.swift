import UIKit
import XCTest
@testable import LocalIPASigner

@MainActor
private final class FakeContinuedJob: ContinuedJobHandle {
    var expiration: (@MainActor () -> Void)?
    var completions: [Bool] = []
    var updates: [(Double, String, String)] = []
    func update(fraction: Double, title: String, subtitle: String) { updates.append((fraction, title, subtitle)) }
    func complete(success: Bool) { completions.append(success) }
}
@MainActor
private final class JobSystemState {
    var issued = 0, canceled = 0
    var ended: [UIBackgroundTaskIdentifier] = []
    var requests: [String] = [], halfway: [String] = []
    var expiration: [@MainActor () -> Void] = []
    var expireImmediately = false
    var system: BackgroundJob.System {
        BackgroundJob.System(beginGrace: { _, expired in
            self.issued += 1; self.expiration.append(expired)
            if self.expireImmediately { expired() }
            return UIBackgroundTaskIdentifier(rawValue: self.issued)
        }, endGrace: { self.ended.append($0) }, requestContinued: { self.requests.append($0) }, cancelContinued: { self.canceled += 1 })
    }
}
@MainActor
final class BackgroundJobOutcomeTests: XCTestCase {
    private func model() -> (BackgroundJob, JobSystemState) {
        let state = JobSystemState()
        return (BackgroundJob(system: state.system, halfway: { state.halfway.append($0) }), state)
    }
    func testOverlappingJobsEndOnlyTheirOwnGraceAndCompleteAggregateOnce() {
        let (model, system) = model(), task = FakeContinuedJob()
        let a = model.begin(title: "Download A"), b = model.begin(title: "Sign B")
        XCTAssertEqual(system.requests.count, 1); model.adopt(task)
        model.end(a, success: true)
        XCTAssertEqual(model.activeCount, 1); XCTAssertEqual(system.ended, [UIBackgroundTaskIdentifier(rawValue: 1)])
        XCTAssertTrue(task.completions.isEmpty); XCTAssertEqual(system.canceled, 0)
        model.end(b, success: true); model.end(a, success: false); model.end(b, success: false)
        XCTAssertEqual(system.ended.count, 2); XCTAssertEqual(task.completions, [true]); XCTAssertEqual(system.canceled, 1)
    }
    func testFailureIsNotOverwrittenByAnotherSuccessfulCompletion() {
        let (model, _) = model(), task = FakeContinuedJob()
        let a = model.begin(title: "A"), b = model.begin(title: "B"); model.adopt(task)
        model.end(a, success: false); model.end(b, success: true)
        XCTAssertEqual(task.completions, [false])
    }
    func testLateQueuedTaskAfterForegroundCompletionIsCompletedNotAdopted() {
        let (model, _) = model(), task = FakeContinuedJob(), id = model.begin(title: "A")
        model.end(id, success: true); model.adopt(task)
        XCTAssertEqual(task.completions, [false]); XCTAssertTrue(task.updates.isEmpty)
    }
    func testStaleExpirationCannotCompleteNewAggregateTask() {
        let (model, _) = model(), old = FakeContinuedJob(), fresh = FakeContinuedJob()
        let a = model.begin(title: "A"); model.adopt(old); let expired = old.expiration
        model.end(a, success: true)
        let b = model.begin(title: "B"); model.adopt(fresh); expired?()
        XCTAssertEqual(old.completions, [true]); XCTAssertTrue(fresh.completions.isEmpty)
        model.end(b, success: true); XCTAssertEqual(fresh.completions, [true])
    }
    func testExpirationAndEndCompleteEachSystemTaskExactlyOnce() {
        let (model, system) = model(), task = FakeContinuedJob(), id = model.begin(title: "A")
        model.adopt(task); let expiry = task.expiration; expiry?(); expiry?()
        model.end(id, success: true)
        XCTAssertEqual(task.completions, [false]); XCTAssertEqual(system.ended.count, 1)
    }
    func testUnexpectedSecondAdoptionCannotReplaceOwnedTask() {
        let (model, _) = model(), first = FakeContinuedJob(), unexpected = FakeContinuedJob(), id = model.begin(title: "A")
        model.adopt(first); model.adopt(unexpected)
        XCTAssertTrue(first.completions.isEmpty); XCTAssertEqual(unexpected.completions, [false])
        model.end(id, success: true); XCTAssertEqual(first.completions, [true])
    }
    func testGraceExpiryDoesNotEndAnotherJobAndIsNotEndedTwice() {
        let (model, system) = model(), a = model.begin(title: "A"), b = model.begin(title: "B")
        system.expiration[0](); system.expiration[0]()
        XCTAssertEqual(model.activeCount, 2); XCTAssertEqual(system.ended.count, 1)
        model.end(a, success: true); XCTAssertEqual(system.ended.count, 1)
        model.end(b, success: true); XCTAssertEqual(system.ended.count, 2)
    }
    func testHalfwayNotificationsArePerOperationAndIgnoreLateProgress() {
        let (model, system) = model(), a = model.begin(title: "A"), b = model.begin(title: "B")
        model.update(a, fraction: 0.6, subtitle: "A"); model.update(a, fraction: 0.9, subtitle: "A")
        model.end(a, success: true); model.update(a, fraction: 1, subtitle: "stale")
        model.update(b, fraction: 0.7, subtitle: "B"); XCTAssertEqual(system.halfway, ["A", "B"])
        model.end(b, success: true)
    }
    func testAggregateProgressIncludesCompletedJobsAndRejectsNonfiniteFractions() {
        let (model, _) = model(), task = FakeContinuedJob(), a = model.begin(title: "A"), b = model.begin(title: "B")
        model.adopt(task); model.update(a, fraction: 0.5, subtitle: "A")
        XCTAssertEqual(task.updates.last!.0, 0.25)
        model.end(a, success: true); XCTAssertEqual(task.updates.last!.0, 0.5)
        let before = task.updates.count; model.update(b, fraction: .nan, subtitle: "invalid")
        model.update(b, fraction: .infinity, subtitle: "invalid"); XCTAssertEqual(task.updates.count, before)
        model.end(b, success: true)
    }
    func testSynchronousGraceExpiryAtAdmissionStillReleasesReturnedResource() {
        let state = JobSystemState(); state.expireImmediately = true
        let model = BackgroundJob(system: state.system), id = model.begin(title: "A")
        XCTAssertEqual(state.ended, [UIBackgroundTaskIdentifier(rawValue: 1)])
        model.end(id, success: true); XCTAssertEqual(state.ended.count, 1)
    }
    func testRepeatedAdoptionOfOwnedHandleDoesNotCompleteItPrematurely() {
        let (model, _) = model(), task = FakeContinuedJob(), id = model.begin(title: "A")
        model.adopt(task); model.adopt(task); XCTAssertTrue(task.completions.isEmpty)
        model.end(id, success: true); XCTAssertEqual(task.completions, [true])
    }

}
