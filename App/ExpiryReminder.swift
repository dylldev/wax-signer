import CredentialKit
import Foundation
import InstallKit
import UserNotifications

/// Schedules one local notification per profile, the day before it expires (a week before for long-lived profiles).
enum ExpiryReminder {
    private static let prefix = "wax.expiry."

    /// Replaces every earlier reminder with the current set. Does nothing visible when notifications are not allowed.
    /// `signed` lets the message say how many shelf apps the profile signed.
    static func reschedule(profiles: [ProfileInfo], signed: [LibraryEntry], enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard enabled else { return }
            for profile in profiles {
                guard let when = ExpiryPolicy.reminderDate(profileExpiry: profile.expirationDate, created: profile.creationDate, now: Date()) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "A signing profile is about to expire"
                content.body = ExpiryPolicy.message(profileName: profile.name, expiry: profile.expirationDate,
                                                    affectedApps: ExpiryPolicy.affectedApps(profileID: profile.id, in: signed))
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: prefix + profile.id.uuidString, content: content, trigger: trigger))
            }
        }
    }
}
