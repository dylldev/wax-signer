import UserNotifications
import XCTest
@testable import LocalIPASigner

@MainActor
final class NotificationPermissionTests: XCTestCase {
    func testOverlappingEnableCallsRequestPermissionOnlyOnce() async {
        var reads: [CheckedContinuation<UNAuthorizationStatus, Never>] = []
        var requests = 0
        let model = NotificationPermissionModel(readStatus: {
            await withCheckedContinuation { reads.append($0) }
        }, request: { requests += 1 })
        let first = Task { await model.enable() }
        while reads.isEmpty { await Task.yield() }
        let second = Task { await model.enable() }
        for _ in 0..<20 { await Task.yield() }
        let initial = reads; reads = []
        for continuation in initial { continuation.resume(returning: .notDetermined) }
        while requests == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        let final = reads; reads = []
        for continuation in final { continuation.resume(returning: .authorized) }
        await first.value; await second.value
        XCTAssertEqual(requests, 1)
    }

    func testRefreshNeverRequestsPermissionAndExplicitEnableRefreshesActualState() async {
        var requests = 0
        var actual = UNAuthorizationStatus.notDetermined
        let model = NotificationPermissionModel(readStatus: { actual }, request: { requests += 1; actual = .denied })
        await model.refresh()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.status, .notDetermined)
        await model.enable()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.status, .denied)
        await model.enable()
        XCTAssertEqual(requests, 1)
    }

    func testPermissionMappingAndRequestErrorDoNotClaimAuthorization() async {
        XCTAssertTrue(NotificationPermissionModel.allowsNotifications(.authorized))
        XCTAssertTrue(NotificationPermissionModel.allowsNotifications(.provisional))
        XCTAssertTrue(NotificationPermissionModel.allowsNotifications(.ephemeral))
        XCTAssertFalse(NotificationPermissionModel.allowsNotifications(.denied))
        XCTAssertFalse(NotificationPermissionModel.allowsNotifications(.notDetermined))
        XCTAssertEqual(NotificationPermissionModel.stateLabel(.authorized), "On")
        XCTAssertEqual(NotificationPermissionModel.stateLabel(.provisional), "Quiet")
        XCTAssertEqual(NotificationPermissionModel.stateLabel(.ephemeral), "Temporary")
        XCTAssertEqual(NotificationPermissionModel.stateLabel(.denied), "Off")
        XCTAssertNil(NotificationPermissionModel.stateLabel(.notDetermined))
        let model = NotificationPermissionModel(readStatus: { .notDetermined }, request: { throw CocoaError(.fileReadUnknown) })
        await model.enable()
        XCTAssertFalse(model.canNotify)
        XCTAssertNotNil(model.errorMessage)
    }
}
