import CredentialKit
import XCTest
@testable import SigningKit

/// Passport wording must fit BOTH free development profiles and enterprise (In-House) profiles.
final class EligibilityFindingsTests: XCTestCase {
    private let dev = ProfileEligibility(kind: .development, provisionsAllDevices: false, deviceCount: 3)
    private let adHoc = ProfileEligibility(kind: .adHoc, provisionsAllDevices: false, deviceCount: 100)
    private let enterprise = ProfileEligibility(kind: .enterprise, provisionsAllDevices: true, deviceCount: nil)

    func testEnterpriseProfileHasNoDeviceListSoEveryIPhoneIsEligible() {
        let f = EligibilityFindings.deviceMembership(for: [enterprise])
        XCTAssertEqual(f.id, "device-membership")
        XCTAssertEqual(f.status, .pass)
        XCTAssertTrue(f.title.lowercased().contains("any iphone"), f.title)
        XCTAssertTrue(f.detail.contains("Enterprise"), f.detail)
    }

    func testProfilesWithADeviceListStayUnknownAndSayHowMany() {
        let f = EligibilityFindings.deviceMembership(for: [dev])
        XCTAssertEqual(f.status, .unknown)
        XCTAssertTrue(f.detail.contains("3 devices"), f.detail)
        XCTAssertEqual(EligibilityFindings.deviceMembership(for: [adHoc]).status, .unknown)
    }

    func testASingleListedDeviceIsSingular() {
        let one = ProfileEligibility(kind: .development, provisionsAllDevices: false, deviceCount: 1)
        let detail = EligibilityFindings.deviceMembership(for: [one]).detail
        XCTAssertTrue(detail.contains("lists 1 device."), detail)
    }

    func testEnterprisePassStillMentionsTrustingTheDeveloper() {
        let f = EligibilityFindings.deviceMembership(for: [enterprise])
        XCTAssertTrue(f.detail.contains("VPN & Device Management"), "an enterprise app does not open until its developer is trusted: \(f.detail)")
        XCTAssertFalse(f.title.lowercased().contains("can run"), "the device list is not the only gate: \(f.title)")
    }

    func testOneListedProfileAmongEnterpriseOnesKeepsTheWholeAppUnknown() {
        XCTAssertEqual(EligibilityFindings.deviceMembership(for: [enterprise, dev]).status, .unknown,
                       "an extension signed with a device-listed profile can still be refused")
    }

    func testNothingSelectedFallsBackToTheGenericUnknown() {
        XCTAssertEqual(EligibilityFindings.deviceMembership(for: []).status, .unknown)
    }

    func testEnterpriseRevocationWarningIsSpecificAndNeverClaimsAnythingIsKnown() {
        let f = EligibilityFindings.revocation(for: [enterprise])
        XCTAssertEqual(f.id, "revocation")
        XCTAssertEqual(f.status, .unknown)
        XCTAssertTrue(f.detail.lowercased().contains("revoked"), f.detail)
        XCTAssertTrue(f.detail.lowercased().contains("enterprise"), f.detail)
    }

    func testDevelopmentRevocationTextDoesNotMentionEnterprise() {
        let f = EligibilityFindings.revocation(for: [dev])
        XCTAssertEqual(f.status, .unknown)
        XCTAssertFalse(f.detail.lowercased().contains("enterprise"), f.detail)
    }
}
