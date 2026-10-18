import Foundation

public struct IPAMetadata: Equatable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String
    public let build: String
    public let minimumOSVersion: String?
    public let executable: String
    public let appFolder: String
    public let entryCount: Int
    /// `_CodeSignature/CodeResources` exists. Says nothing about whether the signature is valid.
    public let hasCodeSignature: Bool
    /// `embedded.mobileprovision` exists. Says nothing about whether the profile is valid.
    public let hasEmbeddedProfile: Bool
    /// `get-task-allow` from the embedded profile's entitlements: true for development profiles, false for
    /// distribution ones, nil when there is no profile, it cannot be read, or the key is absent.
    public let embeddedProfileGetTaskAllow: Bool?
}

public enum IPAError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case notAZip
    case unsupportedZip(String)
    case unsafePath(String)
    case corruptEntry(String)
    case duplicateEntry(String)
    case noApp
    case multipleApps
    case missingInfoPlist
    case invalidInfoPlist
    case missingBundleIdentifier
    case missingExecutable(name: String?)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "Cannot read file: \(why)"
        case .notAZip: return "Not a valid zip archive (corrupt or truncated)."
        case .unsupportedZip(let what): return "Unsupported zip feature: \(what)."
        case .unsafePath(let p): return "Archive contains an unsafe path: \(p)"
        case .corruptEntry(let n): return "Archive entry is corrupt (CRC or size mismatch): \(n)"
        case .duplicateEntry(let n): return "Archive contains duplicate entries (ambiguous when extracted): \(n)"
        case .noApp: return "No Payload/<name>.app found. This does not look like an IPA."
        case .multipleApps: return "Payload contains more than one .app."
        case .missingInfoPlist: return "App bundle has no Info.plist."
        case .invalidInfoPlist: return "Info.plist could not be parsed as a property list dictionary."
        case .missingBundleIdentifier: return "Info.plist has no CFBundleIdentifier."
        case .missingExecutable(let n):
            return n.map { "Executable \"\($0)\" named in Info.plist is not in the archive." }
                ?? "Info.plist has no CFBundleExecutable."
        }
    }
}

public enum IPAInspector {
    /// Validates the archive structure and reads Info.plist. Does not verify code signatures.
    public static func inspect(url: URL) throws -> IPAMetadata {
        let zip = try ZipArchive(url: url)

        for e in zip.entries where isUnsafe(e.name) { throw IPAError.unsafePath(e.name) }

        var folders = Set<String>()
        for e in zip.entries where e.name.hasPrefix("Payload/") {
            let parts = e.name.split(separator: "/", omittingEmptySubsequences: true)
            // A bare file named "X.app" directly in Payload is not an app folder.
            if parts.count >= 3 || e.name.hasSuffix("/"), parts.count >= 2, parts[1].hasSuffix(".app") {
                folders.insert(String(parts[1]))
            }
        }
        guard !folders.isEmpty else { throw IPAError.noApp }
        guard folders.count == 1, let folder = folders.first else { throw IPAError.multipleApps }

        let root = "Payload/\(folder)/"
        let byName = Dictionary(zip.entries.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        guard let plistEntry = byName[root + "Info.plist"] else { throw IPAError.missingInfoPlist }
        let plistData = try zip.data(for: plistEntry)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { throw IPAError.invalidInfoPlist }

        func string(_ key: String) -> String? {
            (plist[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let bundleID = string("CFBundleIdentifier") else { throw IPAError.missingBundleIdentifier }
        guard let exe = string("CFBundleExecutable") else { throw IPAError.missingExecutable(name: nil) }
        guard byName[root + exe] != nil else { throw IPAError.missingExecutable(name: exe) }

        return IPAMetadata(
            bundleIdentifier: bundleID,
            displayName: string("CFBundleDisplayName") ?? string("CFBundleName")
                ?? String(folder.dropLast(".app".count)),
            version: string("CFBundleShortVersionString") ?? "",
            build: string("CFBundleVersion") ?? "",
            minimumOSVersion: string("MinimumOSVersion"),
            executable: exe,
            appFolder: folder,
            entryCount: zip.entries.count,
            hasCodeSignature: byName[root + "_CodeSignature/CodeResources"] != nil,
            hasEmbeddedProfile: byName[root + "embedded.mobileprovision"] != nil,
            embeddedProfileGetTaskAllow: byName[root + "embedded.mobileprovision"]
                .flatMap { try? zip.data(for: $0) }.flatMap(getTaskAllow(inProfile:))
        )
    }

    /// The profile is a CMS blob wrapping an XML plist; the plist is found by its markers. Not a signature check.
    static func getTaskAllow(inProfile data: Data) -> Bool? {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
              let dict = plist as? [String: Any], let ent = dict["Entitlements"] as? [String: Any]
        else { return nil }
        return ent["get-task-allow"] as? Bool
    }

    static func isUnsafe(_ name: String) -> Bool {
        if name.isEmpty || name.hasPrefix("/") || name.contains("\\") || name.contains("\0") { return true }
        // Canonical form only: no "", "." or ".." components (a single trailing "/" marks a directory).
        let comps = name.split(separator: "/", omittingEmptySubsequences: false)
        let body = name.hasSuffix("/") ? comps.dropLast() : comps[...]
        return body.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}
