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

    /// ContentInfo { signedData, [0] SignedData { version, digestAlgs, encapContentInfo { data, [0] OCTET STRING } } }
    private static func embeddedContent(of data: Data) throws -> Data {
        let signedDataOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        do {
            let root = try ASN1.parse(data)
            let top = try root.children()
            guard root.tag == 0x30, top.count == 2, top[0].tag == 0x06, top[0].content == signedDataOID,
                  top[1].tag == 0xA0, let signedData = try top[1].children().first, signedData.tag == 0x30
            else { throw CredentialError.profileNotCMS }

            let parts = try signedData.children()
            guard parts.count >= 3, parts[2].tag == 0x30 else { throw CredentialError.profileNotCMS }
            let encap = try parts[2].children()
            guard encap.count == 2, encap[1].tag == 0xA0, let octets = try encap[1].children().first,
                  octets.tag == 0x04 || octets.tag == 0x24 else { throw CredentialError.profileNoEmbeddedPlist }

            if octets.tag == 0x04 { return Data(octets.content) }
            // Constructed (chunked) OCTET STRING, as produced by streaming CMS encoders.
            return Data(try octets.children().flatMap { chunk -> [UInt8] in
                guard chunk.tag == 0x04 else { throw CredentialError.profileNoEmbeddedPlist }
                return chunk.content
            })
        } catch is ASN1.Malformed {
            throw CredentialError.profileNotCMS
        }
    }
}
