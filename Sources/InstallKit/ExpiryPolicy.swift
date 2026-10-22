import Foundation

/// When to nudge the user that a provisioning profile is about to stop working (free ones last 7 days, enterprise ones a year).
public enum ExpiryPolicy {
    /// 09:00 local time, a week before expiry for long-lived profiles (enterprise ones last a year and replacing a
    /// certificate takes time), otherwise the day before. When the preferred moment has passed, the day-before moment is
    /// used; nil when that has passed too.
    public static func reminderDate(profileExpiry: Date, created: Date? = nil, now: Date, calendar: Calendar = .current) -> Date? {
        guard profileExpiry > now else { return nil }
        let longLived = created.map { profileExpiry.timeIntervalSince($0) >= 60 * 86_400 } ?? false
        for lead in (longLived ? [7, 1] : [1]) {
            guard let day = calendar.date(byAdding: .day, value: -lead, to: profileExpiry),
                  let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            if nine > now { return nine }
        }
        return nil
    }

    public static func message(profileName: String, expiry: Date) -> String {
        "The profile “\(profileName)” expires \(expiry.formatted(.dateTime.weekday(.wide).month().day())). Sign your apps again before then."
    }
}
