import XCTest
@testable import InstallKit

final class SignStageTests: XCTestCase {
    func testTheStepBeingWorkedOnWins() {
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: true), .uploading)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: false), .signing)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: false, uploading: false), .reading)
        XCTAssertNil(SignStage.resolve(reading: false, signing: false, uploading: false))
    }

    func testTheStagesRunInOrderAndSaySoInTwoWords() {
        XCTAssertEqual(SignStage.allCases, [.reading, .signing, .uploading])
        XCTAssertEqual(SignStage.allCases.map(\.title), ["Reading", "Signing", "Uploading"])
    }

    func testEveryStageBeforeTheCurrentOneIsTicked() {
        XCTAssertFalse(SignStage.reading.isDone(current: .reading))
        XCTAssertTrue(SignStage.reading.isDone(current: .signing))
        XCTAssertTrue(SignStage.reading.isDone(current: .uploading))
        XCTAssertFalse(SignStage.signing.isDone(current: .signing))
        XCTAssertTrue(SignStage.signing.isDone(current: .uploading))
        XCTAssertFalse(SignStage.uploading.isDone(current: .uploading))
    }

    func testTheSpokenLineSaysWhereInTheJobItIs() {
        XCTAssertEqual(SignStage.reading.spoken, "Stage 1 of 3, Reading")
        XCTAssertEqual(SignStage.signing.spoken, "Stage 2 of 3, Signing")
        XCTAssertEqual(SignStage.uploading.spoken, "Stage 3 of 3, Uploading")
    }
}

final class SignSetupChecklistTests: XCTestCase {
    func testTheChecklistIsAnAppAnIdentityAndAnInstallHost() {
        XCTAssertEqual(SignSetupChecklist.steps.map(\.icon), ["shippingbox", "key", "icloud.and.arrow.up"])
        for step in SignSetupChecklist.steps {
            XCTAssertFalse(step.title.isEmpty); XCTAssertFalse(step.detail.isEmpty)
        }
    }

    func testTheFirstRunIsOnlyWhenNothingIsSetUp() {
        XCTAssertTrue(SignSetupChecklist.isFirstRun(hasApp: false, hasIdentity: false, hostReady: false))
        XCTAssertFalse(SignSetupChecklist.isFirstRun(hasApp: true, hasIdentity: false, hostReady: false))
        XCTAssertFalse(SignSetupChecklist.isFirstRun(hasApp: false, hasIdentity: true, hostReady: false))
        XCTAssertFalse(SignSetupChecklist.isFirstRun(hasApp: false, hasIdentity: false, hostReady: true))
    }
}