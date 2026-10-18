import Foundation

extension ProfileInfo {
    public func listsCertificate(sha1: String) -> Bool { certificateSHA1s.contains(sha1) }
    /// True when the certificate's team is unknown or matches.
    public func teamMatches(_ team: String?) -> Bool { team == nil || team == teamID }
    public func runsOnIOS() -> Bool { platforms.isEmpty || platforms.contains("iOS") }
    public var isInstallableKind: Bool { kind != .appStore }
}

/// The one place the application-identifier pattern of a profile is interpreted.
public enum ProfileFitness {
    /// Whether `bundleIdentifier` sits inside this profile's own application identifier.
    public static func permits(bundleIdentifier: String, profileApplicationIdentifier appID: String, teamID: String) -> Bool {
        guard appID.hasPrefix(teamID + ".") else { return false }
        let pattern = appID.dropFirst(teamID.count + 1)
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") { return bundleIdentifier.hasPrefix(String(pattern.dropLast())) }
        return pattern == bundleIdentifier
    }

    /// The identifier the profile forces onto an app, or `original` when the wildcard allows keeping it.
    public static func rewrittenIdentifier(profileApplicationIdentifier appID: String, teamID: String, original: String) -> String {
        guard appID.hasPrefix(teamID + ".") else { return appID }
        let pattern = appID.dropFirst(teamID.count + 1)
        if pattern == "*" { return original }
        if pattern.hasSuffix(".*") {
            let last = original.split(separator: ".").last.map(String.init) ?? original
            return String(pattern.dropLast()) + last
        }
        return String(pattern)
    }
}
