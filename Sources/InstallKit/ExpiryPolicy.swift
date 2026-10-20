import Foundation

/// When to nudge the user that a provisioning profile is about to stop working (free ones last 7 days).
public enum ExpiryPolicy {
    /// 09:00 local time on the day before `profileExpiry`, or nil when that moment has already passed.
    public static func reminderDate(profileExpiry: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard profileExpiry > now,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: profileExpiry),
              let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) else { return nil }
        return nine > now ? nine : nil
    }

    public static func message(profileName: String, expiry: Date) -> String {
        "The profile “\(profileName)” expires \(expiry.formatted(.dateTime.weekday(.wide).month().day())). Sign your apps again before then."
    }
}
