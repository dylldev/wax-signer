import Foundation

/// Non-secret certificate details shown in the UI and kept in the metadata index.
/// The private key lives only in the Keychain.
public struct CertificateInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let commonName: String
    public let organization: String?
    /// Subject OU. For Apple-issued development and distribution certificates this is the Team ID.
    public let teamID: String?
    public let country: String?
    public let serialNumberHex: String
    public let sha1Fingerprint: String
    public let notBefore: Date
    public let notAfter: Date
    public let importedAt: Date

    public enum Validity: Equatable, Sendable { case valid, expired, notYetValid }

    public func validity(at date: Date) -> Validity {
        date < notBefore ? .notYetValid : (date > notAfter ? .expired : .valid)
    }
}

public enum ProfileKind: String, Codable, Sendable {
    case development, adHoc, enterprise, appStore
}

extension ProfileKind {
    public var title: String {
        switch self {
        case .development: "Development"
        case .adHoc: "Ad Hoc"
        case .enterprise: "Enterprise"
        case .appStore: "App Store"
        }
    }
}

/// Non-secret profile details. The raw profile is stored separately (see CredentialStore).
public struct ProfileInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let appIDName: String?
    public let teamID: String
    public let teamName: String?
    /// Full application identifier, e.g. `TEAMID.com.example.app` or `TEAMID.*`.
    public let applicationIdentifier: String
    public let platforms: [String]
    public let creationDate: Date?
    public let expirationDate: Date
    /// Inferred from the profile's device list and entitlements, not declared by Apple in the file.
    public let kind: ProfileKind
    public let provisionedDeviceCount: Int?
    public let provisionsAllDevices: Bool
    public let getTaskAllow: Bool
    /// SHA-1 fingerprints (uppercase hex) of the certificates the profile allows to sign.
    public let certificateSHA1s: [String]
    public let importedAt: Date

    /// Application identifier without the team prefix, e.g. `com.example.app` or `*`.
    public var bundleIdentifierPattern: String {
        applicationIdentifier.hasPrefix(teamID + ".")
            ? String(applicationIdentifier.dropFirst(teamID.count + 1)) : applicationIdentifier
    }

    public func isExpired(at date: Date) -> Bool { date > expirationDate }
}

public enum CredentialError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case incorrectPassword
    case malformedPKCS12
    case unsupportedPKCS12(status: Int32)
    case noPrivateKey
    case certificateUnreadable
    case certificateExpired(Date)
    case certificateNotYetValid(Date)
    case profileNotCMS
    case profileNoEmbeddedPlist
    case profileInvalidPlist
    case profileMissingKey(String)
    case profileExpired(Date)
    case alreadyImported
    case notFound
    case keychain(operation: String, status: Int32)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "File is too large to be a certificate or profile."
        case .incorrectPassword: return "Incorrect password for this .p12 file."
        case .malformedPKCS12:
            return "This .p12 could not be read. iOS reports this same error for some wrong passwords, so check the "
                + "password first; if it is right, the file may be corrupt, truncated or not PKCS#12."
        case .unsupportedPKCS12(let s):
            return "The system could not import this .p12 (\(Self.message(s)))."
        case .noPrivateKey:
            return "The .p12 contains no private key. A signing certificate needs its private key."
        case .certificateUnreadable: return "The certificate in this file could not be read."
        case .certificateExpired(let d): return "Certificate expired on \(Self.format(d))."
        case .certificateNotYetValid(let d): return "Certificate is not valid until \(Self.format(d))."
        case .profileNotCMS: return "Not a provisioning profile (not a signed CMS container)."
        case .profileNoEmbeddedPlist: return "Provisioning profile has no embedded content."
        case .profileInvalidPlist: return "Provisioning profile content is not a valid property list."
        case .profileMissingKey(let k): return "Provisioning profile is missing required field: \(k)."
        case .profileExpired(let d): return "Provisioning profile expired on \(Self.format(d))."
        case .alreadyImported: return "This certificate is already imported."
        case .notFound: return "Item not found."
        case .keychain(let op, let s):
            if s == errSecMissingEntitlement {
                return "Keychain \(op) failed: this copy of Wax was signed without keychain access "
                    + "(errSecMissingEntitlement, \(s)). Re-sign it with a profile that has an application identifier."
            }
            return "Keychain \(op) failed (\(Self.message(s)))."
        case .storage(let what): return "Could not update stored credentials: \(what)"
        }
    }

    private static func message(_ status: Int32) -> String {
        (SecCopyErrorMessageString(status, nil) as String?).map { "\($0) [\(status)]" } ?? "OSStatus \(status)"
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
