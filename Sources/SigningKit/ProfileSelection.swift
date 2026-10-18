import CredentialKit
import Foundation

/// How requested entitlements the chosen profile does not grant are treated.
public enum EntitlementMismatchPolicy {
    /// Sign without them and report each one in `SigningResult.warnings`.
    case dropAndWarn
    /// A profile that cannot grant everything the bundle requested is rejected.
    case reject
}

/// Candidate profiles for a signing run. The engine picks, per signable bundle, among `pool`;
/// `overrides` pins a bundle (by path relative to the app, `"."` for the main app) to one profile
/// that is then checked and never replaced by another.
public struct ProfileSet {
    public var pool: [ProvisioningProfile]
    public var overrides: [String: ProvisioningProfile]

    public init(pool: [ProvisioningProfile] = [], overrides: [String: ProvisioningProfile] = [:]) {
        self.pool = pool
        self.overrides = overrides
    }

    public init(single profile: ProvisioningProfile) { self.init(pool: [profile]) }
}

/// Why a profile cannot be used for a bundle. Each case carries enough to explain itself.
public enum ProfileRejection: Equatable, CustomStringConvertible {
    case doesNotListCertificate
    case teamMismatch(profile: String, certificate: String)
    case expired(Date)
    case platformMismatch([String])
    case applicationIdentifierMismatch(profile: String, bundleIdentifier: String)
    case entitlementsNotGranted([String])
    case appStoreProfile

    public var description: String {
        switch self {
        case .doesNotListCertificate: return "does not list the signing certificate"
        case .teamMismatch(let p, let c): return "belongs to team \(p) but the certificate is team \(c)"
        case .expired(let d): return "expired on \(d.formatted(date: .abbreviated, time: .omitted))"
        case .platformMismatch(let p): return "is for \(p.joined(separator: ", ")), not iOS"
        case .applicationIdentifierMismatch(let p, let id): return "application identifier \(p) does not permit \(id)"
        case .entitlementsNotGranted(let keys): return "does not grant requested entitlements: \(keys.joined(separator: ", "))"
        case .appStoreProfile: return "is an App Store profile: apps signed with it cannot be installed outside the App Store"
        }
    }
}

public struct ProfileSelection: Equatable {
    public let bundlePath: String
    public let bundleIdentifier: String
    public let profileName: String
    public let profileID: UUID
    public let rejected: [(profile: String, reason: String)]
    /// Whether the profile's CMS signature chains to Apple. Never assumed from structural validity.
    public var signatureStatus: ProfileSignatureStatus = .invalid(reason: "not evaluated")

    public static func == (a: ProfileSelection, b: ProfileSelection) -> Bool {
        a.bundlePath == b.bundlePath && a.profileID == b.profileID && a.bundleIdentifier == b.bundleIdentifier
    }
}

enum ProfileSelector {
    struct Candidate {
        let profile: ProvisioningProfile
        let unmet: [String]
        /// 0 = exact, 1 = prefix wildcard, 2 = full wildcard. Lower is more specific.
        let specificity: Int
    }

    /// Checks that do not depend on which bundle is being signed.
    static func eligibility(_ profile: ProvisioningProfile, leafSHA1: String, certificateTeam: String?,
                            now: Date) -> ProfileRejection? {
        let info = profile.info
        if !info.certificateSHA1s.contains(leafSHA1) { return .doesNotListCertificate }
        if let team = certificateTeam, team != info.teamID {
            return .teamMismatch(profile: info.teamID, certificate: team)
        }
        if info.isExpired(at: now) { return .expired(info.expirationDate) }
        if info.kind == .appStore { return .appStoreProfile }
        if !info.platforms.isEmpty, !info.platforms.contains("iOS") { return .platformMismatch(info.platforms) }
        return nil
    }

    /// First reason this profile cannot sign `bundleIdentifier`, or nil.
    static func rejection(_ profile: ProvisioningProfile, bundleIdentifier: String, requested: [String: Any],
                          leafSHA1: String, certificateTeam: String?, now: Date,
                          policy: EntitlementMismatchPolicy, ignoreApplicationIdentifier: Bool = false) -> ProfileRejection? {
        if let why = eligibility(profile, leafSHA1: leafSHA1, certificateTeam: certificateTeam, now: now) { return why }
        let info = profile.info
        if !ignoreApplicationIdentifier, !EntitlementsPolicy.permits(profileApplicationIdentifier: info.applicationIdentifier,
                                       teamID: info.teamID, bundleIdentifier: bundleIdentifier) {
            return .applicationIdentifierMismatch(profile: info.applicationIdentifier, bundleIdentifier: bundleIdentifier)
        }
        if policy == .reject {
            let unmet = EntitlementsPolicy.unmet(requested: requested, profile: profile.entitlements, teamID: info.teamID)
            if !unmet.isEmpty { return .entitlementsNotGranted(unmet) }
        }
        return nil
    }

    static func specificity(of info: ProfileInfo) -> Int {
        let pattern = info.bundleIdentifierPattern
        if pattern == "*" { return 2 }
        return pattern.hasSuffix(".*") ? 1 : 0
    }

    /// Chooses among compatible candidates: fewest unmet entitlements, then most specific
    /// application identifier, then latest expiry, then UUID (so the choice is deterministic).
    static func best(_ candidates: [Candidate]) -> Candidate? {
        candidates.min { a, b in
            if a.unmet.count != b.unmet.count { return a.unmet.count < b.unmet.count }
            if a.specificity != b.specificity { return a.specificity < b.specificity }
            if a.profile.info.expirationDate != b.profile.info.expirationDate {
                return a.profile.info.expirationDate > b.profile.info.expirationDate
            }
            return a.profile.info.id.uuidString < b.profile.info.id.uuidString
        }
    }
}
