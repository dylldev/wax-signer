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

    /// Every bundle ID Wax has ever shipped must stay in `waxIDs`, in the order project.yml used them:
    /// `dev.localsigner.app` -> `io.github.dylankirkgirg.wax` (shipped as 0.11.0 through 0.13.0) ->
    /// `io.github.dylldev.wax` (current), plus the dev ID `dev.localsigner.wax.dev`.
    ///
    /// Do not prune these. A phone running an old Wax build is still running that old ID, and this set is the only
    /// thing telling the guard "that install is Wax replacing itself" rather than "a stranger is replacing Wax".
    /// Dropping a shipped ID lets a relabelled app silently take over Wax on those devices.
    func testEveryBundleIDWaxHasShippedCountsAsWax() {
        for id in ["io.github.dylldev.wax", "io.github.dylankirkgirg.wax", "dev.localsigner.app", "dev.localsigner.wax.dev"] {
            XCTAssertFalse(BundleIDGuard.replacesRunningWax(originalID: id, finalID: "x.y", runningID: "x.y"), id)
            XCTAssertTrue(BundleIDGuard.waxIDs.contains(id), "\(id) is missing from the set of IDs Wax has shipped")
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
