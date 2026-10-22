import Foundation

/// When the profile embedded in a signed app expires, in calendar days, for the shelf pill. This is the PROFILE's deadline
/// only: free 7-day development profiles, one-year enterprise profiles and everything between. It says nothing about the
/// certificate being revoked (enterprise certificates often die that way, long before any expiry) or about the device
/// being listed, which Wax cannot see.
public enum SignedAppExpiry: Equatable, Sendable {
    public enum Severity: Equatable, Sendable { case ok, warn, bad }
    case unknown
    case expired
    case within(days: Int)          // 0 = today, 1 = tomorrow
    case later(Date)

    public static func status(expiration: Date?, now: Date = Date(), calendar: Calendar = .current) -> SignedAppExpiry {
        guard let expiration else { return .unknown }
        if expiration <= now { return .expired }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiration)).day ?? 0
        return days < 30 ? .within(days: max(0, days)) : .later(expiration)
    }

    /// Nil when nothing trustworthy is known: the shelf then shows no pill rather than a guess.
    public var label: String? {
        switch self {
        case .unknown: return nil
        case .expired: return "Profile expired"
        case .within(let days):
            switch days {
            case 0: return "Profile expires today"
            case 1: return "Profile expires tomorrow"
            default: return "Profile expires in \(days) days"
            }
        case .later(let date): return "Profile expires " + date.formatted(.dateTime.month(.abbreviated).day())
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
