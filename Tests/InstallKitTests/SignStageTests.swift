import XCTest
@testable import InstallKit

final class SignStageTests: XCTestCase {
    func testTheStepBeingWorkedOnWins() {
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: true), .uploading)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: false), .signing)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: false, uploading: false), .reading)
        XCTAssertNil(SignStage.resolve(reading: false, signing: false, uploading: false))
    }

    /// A reservation stays preparing while signing runs; uploading and handoff happen later.
    func testLaterStepsWinOverEarlierOnes() {
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: true, preparing: true), .uploading)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: true, uploading: true, preparing: true, handed: true), .handed)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: false, uploading: false, preparing: true), .preparing)
        XCTAssertNil(SignStage.resolve(reading: false, signing: false, uploading: false, preparing: false, handed: false))
    }

    func testReservationDoesNotMarkActiveSigningOrReadingComplete() {
        XCTAssertEqual(SignStage.resolve(reading: false, signing: true, uploading: false, preparing: true), .signing)
        XCTAssertEqual(SignStage.resolve(reading: true, signing: false, uploading: false, preparing: true), .reading)
    }

    func testTheStagesRunInOrderAndSayWhereTheyAre() {
        XCTAssertEqual(SignStage.allCases, [.reading, .signing, .preparing, .uploading, .handed])
        XCTAssertEqual(SignStage.allCases.map(\.title), ["Reading", "Signing", "Preparing", "Uploading", "Handed to iOS"])
    }

    /// A sign-only export never uploads or hands off, so it must not show five steps it will never reach.
    func testASignOnlyRunShowsTwoSteps() {
        XCTAssertEqual(SignStage.sequence(exportOnly: true), [.reading, .signing])
        XCTAssertEqual(SignStage.sequence(exportOnly: false), SignStage.allCases)
        XCTAssertEqual(SignStage.signing.spoken(in: SignStage.sequence(exportOnly: true)), "Stage 2 of 2, Signing")
    }

    func testEveryStageBeforeTheCurrentOneIsTicked() {
        XCTAssertFalse(SignStage.reading.isDone(current: .reading))
        XCTAssertTrue(SignStage.reading.isDone(current: .preparing))
        XCTAssertFalse(SignStage.preparing.isDone(current: .preparing))
        XCTAssertTrue(SignStage.signing.isDone(current: .preparing))
        XCTAssertFalse(SignStage.signing.isDone(current: .signing))
        XCTAssertTrue(SignStage.signing.isDone(current: .uploading))
        XCTAssertFalse(SignStage.uploading.isDone(current: .uploading))
        XCTAssertFalse(SignStage.uploading.isDone(current: .preparing))
        XCTAssertTrue(SignStage.preparing.isDone(current: .uploading))
        XCTAssertTrue(SignStage.preparing.isDone(current: .handed))
        XCTAssertFalse(SignStage.handed.isDone(current: .handed))
    }

    func testTheSpokenLineSaysWhereInTheJobItIs() {
        XCTAssertEqual(SignStage.reading.spoken(), "Stage 1 of 5, Reading")
        XCTAssertEqual(SignStage.signing.spoken(), "Stage 2 of 5, Signing")
        XCTAssertEqual(SignStage.uploading.spoken(), "Stage 4 of 5, Uploading")
        XCTAssertEqual(SignStage.preparing.spoken(), "Stage 3 of 5, Preparing")
        XCTAssertEqual(SignStage.handed.spoken(), "Stage 5 of 5, Handed to iOS")
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
