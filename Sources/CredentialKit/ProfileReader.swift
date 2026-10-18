import Foundation

enum ProfileReader {
    static let maxBytes = 1024 * 1024

    /// Parses a `.mobileprovision`: a CMS SignedData whose content is an XML property list.
    ///
    /// The CMS signature is NOT verified: iOS has no public CMS verification API. Profiles are
    /// checked for structure and required fields only.
    static func read(_ data: Data, importedAt: Date, now: Date) throws -> ProfileInfo {
        try readDetailed(data, importedAt: importedAt, now: now).info
    }

    static func readDetailed(_ data: Data, importedAt: Date, now: Date) throws -> (info: ProfileInfo, entitlements: [String: Any]) {
        guard data.count <= maxBytes else { throw CredentialError.fileTooLarge }
        let plistBytes = try embeddedContent(of: data)

        guard let plist = try? PropertyListSerialization.propertyList(from: plistBytes, format: nil)
                as? [String: Any] else { throw CredentialError.profileInvalidPlist }

        func required<T>(_ key: String, _ type: T.Type) throws -> T {
            guard let v = plist[key] as? T else { throw CredentialError.profileMissingKey(key) }
            return v
        }

        let uuidString = try required("UUID", String.self)
        guard let uuid = UUID(uuidString: uuidString) else { throw CredentialError.profileInvalidPlist }
        let name = try required("Name", String.self)
        let expiration = try required("ExpirationDate", Date.self)
        let teams = try required("TeamIdentifier", [String].self)
        guard let team = teams.first, !team.isEmpty else { throw CredentialError.profileMissingKey("TeamIdentifier") }
        let entitlements = try required("Entitlements", [String: Any].self)
        guard let appID = entitlements["application-identifier"] as? String, !appID.isEmpty else {
            throw CredentialError.profileMissingKey("Entitlements.application-identifier")
        }
        let certs = try required("DeveloperCertificates", [Data].self)

        guard expiration > now else { throw CredentialError.profileExpired(expiration) }

        let devices = plist["ProvisionedDevices"] as? [String]
        let allDevices = (plist["ProvisionsAllDevices"] as? Bool) ?? false
        let taskAllow = (entitlements["get-task-allow"] as? Bool) ?? false

        let kind: ProfileKind =
            allDevices ? .enterprise : (devices != nil ? (taskAllow ? .development : .adHoc) : .appStore)

        let info = ProfileInfo(
            id: uuid, name: name, appIDName: plist["AppIDName"] as? String, teamID: team,
            teamName: plist["TeamName"] as? String, applicationIdentifier: appID,
            platforms: (plist["Platform"] as? [String]) ?? [],
            creationDate: plist["CreationDate"] as? Date, expirationDate: expiration, kind: kind,
            provisionedDeviceCount: devices?.count, provisionsAllDevices: allDevices,
            getTaskAllow: taskAllow, certificateSHA1s: certs.map(X509Summary.sha1Hex),
            importedAt: importedAt)
        return (info, entitlements)
    }

    /// The plist inside a signed profile, via the same parser the signature check uses.
    private static func embeddedContent(of data: Data) throws -> Data {
        let signed: CMSSignedData
        do { signed = try CMSSignedData.parse(data) }
        catch { throw CredentialError.profileNotCMS }
        guard let content = signed.encapsulatedContent else { throw CredentialError.profileNoEmbeddedPlist }
        return content
    }
}
