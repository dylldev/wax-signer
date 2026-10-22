import Foundation

/// Legacy stored names: installed means URL-scheme detection, not independently confirmed install/launch.
public enum InstallTestResult: String, Codable, Sendable { case installed, failed }

/// What Wax knows about a certificate and the profile paired with it, from their data and from any test install.
public struct IdentityFacts: Equatable, Sendable {
    public enum ProfileKind: Sendable { case development, adHoc, enterprise, appStore }
    public let certificateValid: Bool
    public let hasCompatibleProfile: Bool
    public let profileExpired: Bool
    public let profileKind: ProfileKind
    public let installTest: InstallTestResult?

    public init(certificateValid: Bool, hasCompatibleProfile: Bool, profileExpired: Bool, profileKind: ProfileKind,
                installTest: InstallTestResult?) {
        self.certificateValid = certificateValid; self.hasCompatibleProfile = hasCompatibleProfile
        self.profileExpired = profileExpired; self.profileKind = profileKind; self.installTest = installTest
    }
}

/// Static pairing checks plus historical probe observations. Neither a certificate name nor a URL scheme
/// determines current provisioning/trust acceptance or proves application launch.
public enum IdentityStatus: Equatable, Sendable {
    case ready              // paired and in date; no test install yet
    case verified           // legacy test record reports probe detection; not trust/launch proof
    case installFailed      // probe was not detected during the observation window
    case needsAttention(String)

    public static func evaluate(_ f: IdentityFacts) -> IdentityStatus {
        if !f.certificateValid { return .needsAttention("The certificate has expired or is not valid yet.") }
        if !f.hasCompatibleProfile { return .needsAttention("No imported profile lists this certificate.") }
        if f.profileExpired { return .needsAttention("The profile has expired.") }
        if f.profileKind == .appStore { return .needsAttention("An App Store profile can't install apps outside the App Store.") }
        switch f.installTest {
        case .installed?: return .verified
        case .failed?: return .installFailed
        case nil: return .ready
        }
    }

    public var label: String {
        switch self {
        case .ready: "Ready"
        case .verified: "Probe detected"
        case .installFailed: "Not detected"
        case .needsAttention: "Check"
        }
    }

    public var detail: String {
        switch self {
        case .ready: "Static certificate and profile checks pass. Installation and launch have not been verified."
        case .verified: "An earlier test record reports probe detection. It does not verify the current profile, iOS version, installation or launch."
        case .installFailed: "The probe was not detected during an earlier test. Cancellation or delivery failure can cause this; you can retry or export."
        case .needsAttention(let why): why
        }
    }
}

/// Legacy per-certificate observations. No profile/OS/time context: never use these as current eligibility proof.
public struct InstallTestStore {
    private let defaults: UserDefaults
    private static let key = "wax.installTests"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func result(for fingerprint: String) -> InstallTestResult? {
        (defaults.dictionary(forKey: Self.key) as? [String: String])?[fingerprint].flatMap(InstallTestResult.init(rawValue:))
    }

    public func set(_ result: InstallTestResult?, for fingerprint: String) {
        var all = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        all[fingerprint] = result?.rawValue
        defaults.set(all, forKey: Self.key)
    }
}

/// The URL-scheme probe observes availability only; it cannot observe the OS install decision or app launch.
public enum InstallProbeMessaging {
    public static let detected = "Wax detected the probe's URL scheme. Installation and launch are not independently confirmed. You can delete Wax Probe when finished."
    public static let notDetected = "Wax did not detect the probe before the timeout. The installation outcome is unknown. If you canceled the prompt or delivery failed, retry."
}
