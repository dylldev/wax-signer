import XCTest
@testable import InstallKit

/// The melt must travel with the job: 0 when it starts, the measured signing share in the middle, and 1 only
/// when the host really has the app. A fresh run has signed nothing, even though its install session is already
/// reserved and the job already counts as installing, so those two facts must not push the melt to the end.
final class SignProgressTests: XCTestCase {
    private func phone(_ sign: Double, signed: Bool = false, uploading: Bool = false,
                       upload: Double? = nil, handed: Bool = false) -> Double {
        SignProgress.fraction(signFraction: sign, signed: signed, uploading: uploading,
                              uploadFraction: upload, handedToHost: handed,
                              exportOnly: false, remoteHost: false)
    }

    func testAFreshRunStartsAtZero() {
        XCTAssertEqual(phone(0), 0)
    }

    func testTheMeltFollowsTheMeasuredSigningShare() {
        XCTAssertEqual(phone(0.4), 0.4 * 0.92, accuracy: 0.0001)
        XCTAssertEqual(phone(0.75), 0.75 * 0.92, accuracy: 0.0001)
    }

    /// Signing alone is not the end: on this iPhone the last stretch is the handoff, which is the only 100.
    func testTheMeltReachesOneOnlyAtHandoff() {
        XCTAssertEqual(phone(1), 0.92, accuracy: 0.0001)
        XCTAssertEqual(phone(1, signed: true), 0.92, accuracy: 0.0001)
        XCTAssertEqual(phone(1, signed: true, handed: true), 1)
        XCTAssertEqual(phone(0, handed: true), 1)
    }

    func testARemoteHostSplitsTheMeltBetweenSigningAndUpload() {
        let remote = { (sign: Double, signed: Bool, uploading: Bool, upload: Double?) in
            SignProgress.fraction(signFraction: sign, signed: signed, uploading: uploading,
                                  uploadFraction: upload, handedToHost: false,
                                  exportOnly: false, remoteHost: true)
        }
        XCTAssertEqual(remote(0, false, false, nil), 0)
        XCTAssertEqual(remote(0.5, false, false, nil), 0.25, accuracy: 0.0001)
        XCTAssertEqual(remote(1, true, false, nil), 0.5, accuracy: 0.0001)
        XCTAssertEqual(remote(1, true, true, 0.5), 0.75, accuracy: 0.0001)
        XCTAssertEqual(remote(1, true, true, 1), 1)
    }

    /// A sign-only export never uploads or hands off, so its signing share is the whole melt.
    func testAnExportNeverWaitsForAnUpload() {
        let exported = { (sign: Double, signed: Bool) in
            SignProgress.fraction(signFraction: sign, signed: signed, uploading: false,
                                  uploadFraction: nil, handedToHost: false,
                                  exportOnly: true, remoteHost: true)
        }
        XCTAssertEqual(exported(0, false), 0)
        XCTAssertEqual(exported(0.5, false), 0.5, accuracy: 0.0001)
        XCTAssertEqual(exported(1, true), 1)
    }

    func testOutOfRangeInputCannotPushTheMeltOutsideZeroToOne() {
        XCTAssertEqual(phone(-1), 0)
        XCTAssertEqual(phone(.infinity), 0.92, accuracy: 0.0001)
        XCTAssertEqual(phone(.nan), 0)
        XCTAssertEqual(SignProgress.fraction(signFraction: 1, signed: true, uploading: true, uploadFraction: 2,
                                             handedToHost: false, exportOnly: false, remoteHost: true), 1)
        XCTAssertEqual(SignProgress.fraction(signFraction: 1, signed: true, uploading: true, uploadFraction: -1,
                                             handedToHost: false, exportOnly: false, remoteHost: true), 0.5, accuracy: 0.0001)
    }
}
