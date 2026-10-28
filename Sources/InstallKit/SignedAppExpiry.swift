import Foundation

/// When a signed app stops opening because its profile or certificate expires, in calendar days, for the shelf pill:
/// free 7-day development profiles, one-year enterprise profiles and everything between. It says nothing about the
/// certificate being revoked (enterprise certificates often die that way, long before any expiry) or about the device
/// being listed, which Wax cannot see.
public enum SignedAppExpiry: Equatable, Sendable {
    public enum Severity: Equatable, Sendable { case ok, warn, bad }
    public enum Subject: Equatable, Sendable { case profile, certificate }

    /// The earlier of the two deadlines; the profile wins a tie. Nil when neither is known.
    public static func deadline(profile: Date?, certificate: Date?) -> (date: Date, subject: Subject)? {
        switch (profile, certificate) {
        case let (p?, c?): return c < p ? (c, .certificate) : (p, .profile)
        case let (p?, nil): return (p, .profile)
        case let (nil, c?): return (c, .certificate)
        case (nil, nil): return nil
        }
    }

    /// From Wax's own signing record: the earliest profile (an extension's can end first) against the certificate.
    public static func deadline(record: SigningRecord) -> (date: Date, subject: Subject)? {
        deadline(profile: record.profiles.map(\.expires).min(), certificate: record.certificateExpires)
    }
    case unknown
    case expired
    case within(days: Int)          // 0 = today, 1 = tomorrow
    case later(Date, otherYear: Bool)

    public static func status(expiration: Date?, now: Date = Date(), calendar: Calendar = .current) -> SignedAppExpiry {
        guard let expiration else { return .unknown }
        if expiration <= now { return .expired }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiration)).day ?? 0
        return days < 30 ? .within(days: max(0, days))
            : .later(expiration, otherYear: calendar.component(.year, from: expiration) != calendar.component(.year, from: now))
    }

    /// Nil when nothing trustworthy is known: the shelf then shows no pill rather than a guess.
    public var label: String? { label(for: .profile) }

    public func label(for subject: Subject) -> String? {
        let name = subject == .profile ? "Profile" : "Certificate"
        switch self {
        case .unknown: return nil
        case .expired: return "\(name) expired"
        case .within(let days):
            switch days {
            case 0: return "\(name) expires today"
            case 1: return "\(name) expires tomorrow"
            default: return "\(name) expires in \(days) days"
            }
        case .later(let date, let otherYear):
            // A year-long profile ends on today's month and day next year: without the year that reads as today.
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(name) expires " + date.formatted(otherYear ? style.year() : style)
        }
    }

    public var severity: Severity {
        switch self {
        case .expired: return .bad
        case .within(let days): return days <= 1 ? .bad : (days <= 3 ? .warn : .ok)
        case .unknown, .later: return .ok
        }
    }
}
