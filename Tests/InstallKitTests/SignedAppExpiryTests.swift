import XCTest
@testable import InstallKit

final class SignedAppExpiryTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c }
    private let utc = "UTC"
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, zone: String = "UTC") -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func status(_ exp: Date?, now: Date, zone: String = "UTC") -> SignedAppExpiry {
        SignedAppExpiry.status(expiration: exp, now: now, calendar: calendar(zone))
    }

    func testExpiredWhenTheMomentHasPassed() {
        let s = status(at(2026, 10, 20, 11, 59), now: at(2026, 10, 20, 12))
        XCTAssertEqual(s, .expired)
        XCTAssertEqual(s.label, "Profile expired")
    }

    func testTodayTomorrowAndCalendarDayCounts() {
        let now = at(2026, 10, 20, 9)
        XCTAssertEqual(status(at(2026, 10, 20, 18), now: now).label, "Profile expires today")
        XCTAssertEqual(status(at(2026, 10, 21, 2), now: now).label, "Profile expires tomorrow")
        XCTAssertEqual(status(at(2026, 10, 23, 8), now: now).label, "Profile expires in 3 days")
        XCTAssertEqual(status(at(2026, 10, 26, 23), now: now).label, "Profile expires in 6 days")
    }

    func testLateEveningNowAndEarlyMorningExpiryIsTomorrowNotToday() {
        // 23:00 -> 01:00 next day is two elapsed hours but a different calendar day.
        XCTAssertEqual(status(at(2026, 10, 21, 1), now: at(2026, 10, 20, 23)).label, "Profile expires tomorrow")
    }

    func testDaylightSavingDoesNotShiftTheDay() {
        let ny = "America/New_York"          // clocks go forward on 2026-03-08, so the night is only 23 hours long
        XCTAssertEqual(status(at(2026, 3, 8, 22, zone: ny), now: at(2026, 3, 7, 23, zone: ny), zone: ny).label, "Profile expires tomorrow")
        XCTAssertEqual(status(at(2026, 3, 10, 12, zone: ny), now: at(2026, 3, 7, 12, zone: ny), zone: ny).label, "Profile expires in 3 days")
    }

    func testSeverityRisesAsTheDeadlineApproaches() {
        let now = at(2026, 10, 20, 9)
        XCTAssertEqual(status(at(2026, 10, 19), now: now).severity, .bad)
        XCTAssertEqual(status(at(2026, 10, 20, 18), now: now).severity, .bad)
        XCTAssertEqual(status(at(2026, 10, 22, 12), now: now).severity, .warn)
        XCTAssertEqual(status(at(2026, 11, 20), now: now).severity, .ok)
    }

    func testUnknownWhenThereIsNoDateAndNoPillIsShown() {
        let s = status(nil, now: at(2026, 10, 20))
        XCTAssertEqual(s, .unknown)
        XCTAssertNil(s.label, "an unreadable profile shows no pill rather than a made-up date")
    }

    func testADateInAnotherYearNamesTheYear() {
        // An enterprise profile issued today expires on this same month and day next year: without the year it reads as today.
        let label = status(at(2027, 10, 22, 12), now: at(2026, 10, 22, 9)).label
        XCTAssertEqual(label?.contains("2027"), true, label ?? "nil")
        XCTAssertEqual(status(at(2026, 12, 20), now: at(2026, 10, 20)).label?.contains("2026"), false)
    }

    func testLongLivedEnterpriseProfilesNameTheDateNotAHugeDayCount() {
        let label = status(at(2027, 8, 14), now: at(2026, 10, 20)).label
        XCTAssertEqual(label?.hasPrefix("Profile expires "), true)
        XCTAssertFalse(label!.contains("days"), label!)
        XCTAssertEqual(status(at(2027, 8, 14), now: at(2026, 10, 20)).severity, .ok)
    }

    func testTheEarlierOfProfileAndCertificateDecides() {
        let profile = at(2026, 11, 20), cert = at(2026, 11, 2)
        XCTAssertEqual(SignedAppExpiry.deadline(profile: profile, certificate: cert)?.subject, .certificate)
        XCTAssertEqual(SignedAppExpiry.deadline(profile: profile, certificate: cert)?.date, cert)
        XCTAssertEqual(SignedAppExpiry.deadline(profile: profile, certificate: nil)?.subject, .profile)
        XCTAssertEqual(SignedAppExpiry.deadline(profile: cert, certificate: profile)?.subject, .profile)
        XCTAssertNil(SignedAppExpiry.deadline(profile: nil, certificate: nil))
    }

    func testCertificateLabelsNameTheCertificate() {
        let now = at(2026, 10, 20, 9)
        XCTAssertEqual(status(at(2026, 10, 23, 8), now: now).label(for: .certificate), "Certificate expires in 3 days")
        XCTAssertEqual(status(at(2026, 10, 19), now: now).label(for: .certificate), "Certificate expired")
        XCTAssertEqual(status(at(2026, 10, 23, 8), now: now).label(for: .profile), status(at(2026, 10, 23, 8), now: now).label)
    }

    func testTheRecordGivesTheDeadlineWithoutReadingTheFile() {
        let record = SigningRecord(signedAt: at(2026, 10, 1), originalBundleID: "a", finalBundleID: "a", teamID: nil, appIDPrefix: nil,
                                   certificateSHA1: nil, certificateExpires: at(2027, 5, 1),
                                   profiles: [.init(id: UUID(), name: "Main", kind: "Development", expires: at(2026, 10, 27)),
                                              .init(id: UUID(), name: "Widget", kind: "Development", expires: at(2026, 10, 25))])
        let d = SignedAppExpiry.deadline(record: record)
        XCTAssertEqual(d?.date, at(2026, 10, 25), "an extension's profile can expire first")
        XCTAssertEqual(d?.subject, .profile)
    }
}
