import XCTest
@testable import InstallKit

final class ExpiryPolicyTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d, hour: h))!
    }

    func testReminderIsOneDayBeforeExpiryAtNineLocal() {
        let expiry = date(2026, 10, 24, 12)
        let r = ExpiryPolicy.reminderDate(profileExpiry: expiry, now: date(2026, 10, 17), calendar: cal)
        XCTAssertEqual(r.map { cal.component(.hour, from: $0) }, 9)
        let days = cal.dateComponents([.day], from: r!, to: expiry).day
        XCTAssertEqual(days, 1)
        XCTAssertLessThan(r!, expiry)
    }

    func testNoReminderWhenAlreadyWithinADay() {
        XCTAssertNil(ExpiryPolicy.reminderDate(profileExpiry: date(2026, 10, 18, 3), now: date(2026, 10, 17, 12), calendar: cal))
    }

    func testNoReminderForAnExpiredProfile() {
        XCTAssertNil(ExpiryPolicy.reminderDate(profileExpiry: date(2026, 10, 1), now: date(2026, 10, 17), calendar: cal))
    }

    func testMessageNamesTheProfileAndTheDay() {
        let m = ExpiryPolicy.message(profileName: "Dev Profile", expiry: date(2026, 10, 24, 12))
        XCTAssertTrue(m.contains("Dev Profile"))
        XCTAssertTrue(m.lowercased().contains("expire"))
    }
}
