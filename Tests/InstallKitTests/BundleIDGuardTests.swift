import XCTest
@testable import InstallKit

final class BundleIDGuardTests: XCTestCase {
    func testAnotherAppUnderTheRunningWaxIDWouldReplaceWax() {
        XCTAssertTrue(BundleIDGuard.replacesRunningWax(originalID: "com.example.thirdparty", finalID: "app.example.profile",
                                                       runningID: "app.example.profile"))
    }

    func testWaxUpdatingItselfIsFine() {
        XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: "dev.localsigner.app", finalID: "com.example.renamed",
                                                        runningID: "com.example.renamed"))
        XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: "dev.localsigner.wax.dev", finalID: "x.y", runningID: "x.y"))
    }

    func testTheCurrentWaxIDUpdatingItselfIsFine() {
        XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: "io.github.dylankirkgirg.wax", finalID: "x.y", runningID: "x.y"))
    }

    func testTheRenamedWaxIDAndEveryOlderIDCountAsWax() {
        for id in ["io.github.dylldev.wax", "io.github.dylankirkgirg.wax", "dev.localsigner.app", "dev.localsigner.wax.dev"] {
            XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: id, finalID: "x.y", runningID: "x.y"), id)
        }
    }

    func testAThirdPartyAppUsingTheWaxNamespaceStillCountsAsReplacingWax() {
        XCTAssertTrue(BundleIDGuard.replacesRunningWax(originalID: "dev.localsigner.otherapp", finalID: "x.y", runningID: "x.y"))
    }

    func testDifferentIDsAreFine() {
        XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: "com.example.thirdparty", finalID: "app.other.id", runningID: "app.example.profile"))
        XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: "com.example.thirdparty", finalID: "com.example.thirdparty", runningID: nil))
    }

    func testExplanationSaysWhatToDo() {
        XCTAssertTrue(BundleIDGuard.explanation.contains("replace Wax"))
        XCTAssertTrue(BundleIDGuard.explanation.localizedCaseInsensitiveContains("wildcard"))
    }
}
