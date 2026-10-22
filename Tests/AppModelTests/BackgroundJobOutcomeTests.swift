import UIKit
import SigningKit
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
    var inBackground = true
    var system: BackgroundJob.System {
        BackgroundJob.System(beginGrace: { _, expired in
            self.issued += 1; self.expiration.append(expired)
            if self.expireImmediately { expired() }
            return UIBackgroundTaskIdentifier(rawValue: self.issued)
        }, endGrace: { self.ended.append($0) }, requestContinued: { self.requests.append($0) }, cancelContinued: { self.canceled += 1 },
        isInBackground: { self.inBackground })
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

    func testGraceExpirationCancelsOnlyItsWorkerOnceAndIgnoresLateProgress() throws {
        let (model, system) = model(), aToken = SigningCancellation(), bToken = SigningCancellation()
        var calls = 0
        let a = model.begin(title: "A", onExpiration: { calls += 1; aToken.cancel() })
        let b = model.begin(title: "B", onExpiration: { bToken.cancel() })
        system.expiration[0](); system.expiration[0]()
        XCTAssertEqual(calls, 1); XCTAssertThrowsError(try aToken.check()); XCTAssertNoThrow(try bToken.check())
        model.update(a, fraction: 0.9, subtitle: "stale"); XCTAssertTrue(system.halfway.isEmpty)
        XCTAssertEqual(model.activeCount, 2) // resource expiry requests cancellation, not imaginary worker completion
        model.end(a, success: false); model.end(b, success: true)
    }
    func testGraceExpirationDoesNotCancelForegroundOrContinuedWork() {
        let (model, system) = model(), handle = FakeContinuedJob()
        var canceled = 0
        system.inBackground = false
        let a = model.begin(title: "foreground", onExpiration: { canceled += 1 })
        system.expiration[0](); XCTAssertEqual(canceled, 0)
        system.inBackground = true; model.adopt(handle)
        let b = model.begin(title: "continued", onExpiration: { canceled += 1 })
        system.expiration[1](); XCTAssertEqual(canceled, 0)
        model.end(a, success: true); model.end(b, success: true); XCTAssertEqual(handle.completions, [true])
    }
    func testContinuedExpirationCancelsAllOwnedWorkersEvenInForegroundExactlyOnce() {
        let (model, system) = model(), handle = FakeContinuedJob()
        system.inBackground = false
        var canceled: [String] = []
        let a = model.begin(title: "A", onExpiration: { canceled.append("A") })
        let b = model.begin(title: "B", onExpiration: { canceled.append("B") })
        model.adopt(handle); let expiry = handle.expiration; expiry?(); expiry?()
        XCTAssertEqual(canceled.sorted(), ["A", "B"]); XCTAssertEqual(system.ended.count, 2)
        XCTAssertEqual(handle.completions, [false]); XCTAssertEqual(model.activeCount, 2)
        model.end(a, success: true); model.end(b, success: true)
        XCTAssertEqual(handle.completions, [false]); XCTAssertEqual(system.ended.count, 2)
    }
    func testSynchronousExpirationReachesLateTaskRegistrationOnce() {
        let (model, system) = model(); system.expireImmediately = true
        var calls = 0
        let id = model.begin(title: "A")
        model.onExpiration(of: id) { calls += 1 }; model.onExpiration(of: id) { calls += 1 }
        system.expiration[0](); XCTAssertEqual(calls, 1); XCTAssertTrue(system.requests.isEmpty)
        let late = FakeContinuedJob(); model.adopt(late); XCTAssertEqual(late.completions, [false])
        model.end(id, success: false)
    }
    func testStaleGraceExpirationCannotCancelReplacementJob() {
        let (model, system) = model(); var calls = 0
        let old = model.begin(title: "old", onExpiration: { XCTFail("ended job") })
        model.end(old, success: true)
        let fresh = model.begin(title: "new", onExpiration: { calls += 1 })
        system.expiration[0](); XCTAssertEqual(calls, 0)
        system.expiration[1](); XCTAssertEqual(calls, 1); model.end(fresh, success: false)
    }
    func testExpirationCallbackCanFinishJobAndAdmitReplacementWithoutCancelingIt() {
        let (model, _) = model(), handle = FakeContinuedJob(), fresh = FakeContinuedJob()
        var id: UUID!, replacement: UUID?, replacementCanceled = false
        id = model.begin(title: "old", onExpiration: {
            model.end(id, success: false)
            replacement = model.begin(title: "replacement", onExpiration: { replacementCanceled = true })
            model.adopt(fresh)
        })
        model.adopt(handle); let expiry = handle.expiration; expiry?(); expiry?()
        XCTAssertFalse(replacementCanceled); XCTAssertTrue(fresh.completions.isEmpty)
        XCTAssertEqual(handle.completions, [false]); XCTAssertEqual(model.activeCount, 1)
        model.end(replacement!, success: true); XCTAssertEqual(fresh.completions, [true])
    }
    func testCanceledWorkersSettlingDoNotPreventNewBackgroundAdmission() {
        let (model, system) = model(); let old = model.begin(title: "old")
        system.expiration[0]()
        let fresh = model.begin(title: "new"), handle = FakeContinuedJob()
        XCTAssertEqual(system.requests.count, 2); model.adopt(handle); XCTAssertTrue(handle.completions.isEmpty)
        model.end(old, success: false); model.end(fresh, success: true); XCTAssertEqual(handle.completions, [false])
    }

}
