import Foundation

/// What a test install showed for one signing identity.
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

/// Whether an identity can be used to sign and install on this phone. It never guesses from a certificate's name:
/// development certificates installed fine in testing, so only the data and a real test install decide.
public enum IdentityStatus: Equatable, Sendable {
    case ready              // paired and in date; no test install yet
    case verified           // a test install worked on this phone
    case installFailed      // a test install did not complete
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
        case .verified: "Installs here"
        case .installFailed: "Install failed"
        case .needsAttention: "Check"
        }
    }

    public var detail: String {
        switch self {
        case .ready: "Certificate and profile match. Not tested on this phone yet."
        case .verified: "A test app installed on this phone with this identity."
        case .installFailed: "A test install didn't complete. You can still export for a Mac, or test again."
        case .needsAttention(let why): why
        }
    }
}

/// Remembers test-install results per certificate (by SHA-1 fingerprint).
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
