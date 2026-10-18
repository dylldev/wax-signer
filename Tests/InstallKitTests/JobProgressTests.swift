import XCTest
@testable import InstallKit

final class JobProgressTests: XCTestCase {
    func testOverallStartsAtZeroAndEndsAtOne() {
        let p = JobProgress(signSeconds: 10, uploadSeconds: 30)
        XCTAssertEqual(p.overall(sign: 0, upload: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(p.overall(sign: 1, upload: 1), 1, accuracy: 1e-9)
    }

    func testStagesAreWeightedByTheirExpectedTime() {
        let p = JobProgress(signSeconds: 10, uploadSeconds: 30)
        XCTAssertEqual(p.overall(sign: 1, upload: 0), 0.25, accuracy: 1e-9)       // signing is a quarter of the job
        XCTAssertEqual(p.overall(sign: 1, upload: 0.5), 0.625, accuracy: 1e-9)
    }

    func testExportOnlyJobIsAllSigning() {
        let p = JobProgress(signSeconds: 10, uploadSeconds: 0)
        XCTAssertEqual(p.overall(sign: 0.5, upload: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.overall(sign: 1, upload: 0), 1, accuracy: 1e-9)
    }

    func testValuesOutsideZeroToOneAreClamped() {
        let p = JobProgress(signSeconds: 5, uploadSeconds: 5)
        XCTAssertEqual(p.overall(sign: -1, upload: 7), 0.5, accuracy: 1e-9)
    }

    func testNeverGoesBackwardsAsEitherStageAdvances() {
        let p = JobProgress(signSeconds: 8, uploadSeconds: 12)
        var last = -1.0
        for i in 0...20 { let v = p.overall(sign: min(1, Double(i) / 10), upload: max(0, Double(i - 10) / 10)); XCTAssertGreaterThanOrEqual(v, last); last = v }
    }

    func testEstimatorStartsWithDefaultsAndLearnsFromRuns() {
        let store = InMemoryEstimateStore()
        var e = JobEstimator(store: store)
        let first = e.estimate(megabytes: 100)
        XCTAssertGreaterThan(first.sign, 0); XCTAssertGreaterThan(first.upload, 0)

        e.record(megabytes: 100, signSeconds: 20, uploadSeconds: 5)      // 0.2 s/MB signing, 0.05 s/MB upload
        let learned = e.estimate(megabytes: 50)
        XCTAssertGreaterThan(learned.sign, 5, "should move toward 0.2 s/MB")
        XCTAssertLessThan(learned.upload, first.upload / 2 + 50 * 0.2, "upload estimate follows the measured speed")
        // a new estimator on the same store remembers
        XCTAssertEqual(JobEstimator(store: store).estimate(megabytes: 50).sign, learned.sign, accuracy: 1e-9)
    }

    func testNonsenseMeasurementsAreIgnored() {
        let store = InMemoryEstimateStore()
        var e = JobEstimator(store: store)
        let before = e.estimate(megabytes: 100)
        e.record(megabytes: 0, signSeconds: 5, uploadSeconds: 5)
        e.record(megabytes: 100, signSeconds: -1, uploadSeconds: .nan)
        XCTAssertEqual(e.estimate(megabytes: 100).sign, before.sign, accuracy: 1e-9)
        XCTAssertEqual(e.estimate(megabytes: 100).upload, before.upload, accuracy: 1e-9)
    }
}
