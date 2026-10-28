import Foundation

/// Compares a planned signing with the last copy Wax signed of the same app, from Wax's own records only. It cannot see
/// what is installed on the phone; it says what the records imply and leaves the final decision to iOS.
public enum IdentityContinuity {
    public struct Assessment: Equatable, Sendable {
        public let isWarning: Bool
        public let title: String
        public let detail: String
    }

    /// The newest record of an earlier signing of this app, matched by its original or its signed bundle ID.
    public static func previous(for bundleID: String, in entries: [LibraryEntry]) -> SigningRecord? {
        entries.compactMap { $0.kind == .signed ? $0.record : nil }
            .filter { $0.originalBundleID == bundleID || $0.finalBundleID == bundleID }
            .max { $0.signedAt < $1.signedAt }
    }

    /// Nil when Wax has no record of an earlier signing of this app.
    public static func assess(originalBundleID: String, finalBundleID: String, teamID: String?, appIDPrefix: String?,
                              entries: [LibraryEntry]) -> Assessment? {
        // A different app already signed to the same final ID (a one-app-ID profile with Rename to fit) gets replaced.
        let sameApp: (SigningRecord) -> Bool = { $0.originalBundleID == originalBundleID || $0.finalBundleID == originalBundleID }
        if let other = entries.filter({ $0.kind == .signed && $0.record.map { $0.finalBundleID == finalBundleID && !sameApp($0) } == true })
            .max(by: { $0.record!.signedAt < $1.record!.signedAt }) {
            let when = other.record!.signedAt.formatted(date: .abbreviated, time: .omitted)
            return Assessment(isWarning: true, title: "Replaces another app",
                              detail: "Wax signed \(other.name) with the same bundle ID (\(finalBundleID)) on \(when). Installing this app replaces \(other.name) and its data on this iPhone. To keep both, use a profile that allows more than one app ID.")
        }
        guard let old = previous(for: originalBundleID, in: entries) else { return nil }
        let when = old.signedAt.formatted(date: .abbreviated, time: .omitted)
        if old.finalBundleID != finalBundleID {
            return Assessment(isWarning: true, title: "Installs as a separate app",
                              detail: "The copy Wax signed on \(when) used the bundle ID \(old.finalBundleID). This one will use \(finalBundleID), so iOS installs it next to the old copy, with its own empty data. To update the old copy instead, sign with the profile and Bundle ID setting you used then.")
        }
        func changed(_ a: String?, _ b: String?) -> Bool { a != nil && b != nil && a != b }
        if changed(old.teamID, teamID) || changed(old.appIDPrefix, appIDPrefix) {
            return Assessment(isWarning: true, title: "Signed by a different team than the earlier copy",
                              detail: "The copy Wax signed on \(when) used team \(old.teamID ?? "unknown") and app ID prefix \(old.appIDPrefix ?? "unknown"). This one uses team \(teamID ?? "unknown") and prefix \(appIDPrefix ?? "unknown"). "
                                + (changed(old.appIDPrefix, appIDPrefix)
                                   ? "iOS rejects an update whose app ID prefix differs from the installed copy's, so delete the old copy first, which also deletes its data."
                                   : "iOS may refuse to install it over the old copy; deleting the old copy first also deletes its data.")
                                + " Keychain items such as saved logins do not carry over to a new app ID prefix.")
        }
        return Assessment(isWarning: false, title: "Updates the copy Wax signed on \(when)",
                          detail: "Same bundle ID (\(finalBundleID)) and team as that copy, so iOS should treat this as an update and keep the app's data. Only iOS makes the final decision.")
    }
}
