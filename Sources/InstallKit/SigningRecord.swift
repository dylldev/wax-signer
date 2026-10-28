import Foundation

/// What Wax signed a shelf app with: public identifiers and dates only. No key material, passwords, certificate
/// names or device identifiers. Lets a later signing say whether it will update this copy or install a new one.
public struct SigningRecord: Codable, Equatable, Sendable {
    public struct Profile: Codable, Equatable, Sendable {
        /// Wax's id for the imported profile (`ProfileInfo.id`).
        public let id: UUID
        public let name: String
        public let kind: String
        public let expires: Date
        public init(id: UUID, name: String, kind: String, expires: Date) {
            self.id = id; self.name = name; self.kind = kind; self.expires = expires
        }
    }
    public var schema = 1
    public let signedAt: Date
    /// The app's bundle ID before signing, and the one it was signed with (they differ after Rename to fit).
    public let originalBundleID: String
    public let finalBundleID: String
    /// Team ID from the signing certificate.
    public let teamID: String?
    /// Prefix of the main profile's application identifier. It decides which keychain items the app can read.
    public let appIDPrefix: String?
    /// SHA-1 fingerprint of the signing certificate: public, identifies it without naming its owner.
    public let certificateSHA1: String?
    public let certificateExpires: Date?
    /// The main app's profile first, then any other profile used for extensions.
    public let profiles: [Profile]

    public init(signedAt: Date, originalBundleID: String, finalBundleID: String, teamID: String?, appIDPrefix: String?,
                certificateSHA1: String?, certificateExpires: Date?, profiles: [Profile]) {
        self.signedAt = signedAt; self.originalBundleID = originalBundleID; self.finalBundleID = finalBundleID
        self.teamID = teamID; self.appIDPrefix = appIDPrefix; self.certificateSHA1 = certificateSHA1
        self.certificateExpires = certificateExpires; self.profiles = profiles
    }
}
