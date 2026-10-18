import CryptoKit
import Foundation

/// Builds `_CodeSignature/CodeResources` (version 2): SHA-1 `files`, SHA-256 `files2`, and the standard
/// rule sets Apple's codesign writes for iOS bundles.
enum CodeResources {
    private struct Rule {
        let regex: NSRegularExpression
        let weight: Double
        let omit: Bool
        let optional: Bool
    }

    private static let rules1: [String: Any] = [
        "^.*": true,
        "^.*\\.lproj/": ["optional": true, "weight": 1000.0],
        "^.*\\.lproj/locversion.plist$": ["omit": true, "weight": 1100.0],
        "^Base\\.lproj/": ["weight": 1010.0],
        "^version.plist$": true,
    ]

    private static let rules2: [String: Any] = [
        ".*\\.dSYM($|/)": ["weight": 11.0],
        "^(.*/)?\\.DS_Store$": ["omit": true, "weight": 2000.0],
        "^.*": true,
        "^.*\\.lproj/": ["optional": true, "weight": 1000.0],
        "^.*\\.lproj/locversion.plist$": ["omit": true, "weight": 1100.0],
        "^Base\\.lproj/": ["weight": 1010.0],
        "^Info\\.plist$": ["omit": true, "weight": 20.0],
        "^PkgInfo$": ["omit": true, "weight": 20.0],
        "^embedded\\.provisionprofile$": ["weight": 20.0],
        "^version\\.plist$": ["weight": 20.0],
    ]

    private static func compile(_ rules: [String: Any]) throws -> [Rule] {
        try rules.map { pattern, spec in
            let regex = try NSRegularExpression(pattern: pattern)
            if let d = spec as? [String: Any] {
                return Rule(regex: regex, weight: (d["weight"] as? Double) ?? 1,
                            omit: (d["omit"] as? Bool) ?? false, optional: (d["optional"] as? Bool) ?? false)
            }
            return Rule(regex: regex, weight: 1, omit: false, optional: false)
        }
    }

    private static func match(_ rules: [Rule], _ path: String) -> Rule? {
        let range = NSRange(path.startIndex..., in: path)
        return rules.filter { $0.regex.firstMatch(in: path, range: range) != nil }.max { $0.weight < $1.weight }
    }

    /// - `executable`: relative path of the bundle's own executable, sealed by its CodeDirectory instead.
    static func build(bundleRoot: URL, executable: String?) throws -> Data {
        let r1 = try compile(rules1), r2 = try compile(rules2)
        var files: [String: Any] = [:]
        var files2: [String: Any] = [:]

        let fm = FileManager.default
        guard let walker = fm.enumerator(at: bundleRoot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                                         options: []) else { throw SigningError.io("cannot read \(bundleRoot.path)") }
        let rootPath = bundleRoot.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            // Resolve the folder the entry lives in, never the entry itself: a symlink is sealed as a link under its own name.
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(url.lastPathComponent).path
            guard full.hasPrefix(rootPath + "/") else { continue }
            let rel = String(full.dropFirst(rootPath.count + 1))
            // Only this bundle's own signature directory is excluded. A nested bundle's
            // _CodeSignature/CodeResources is sealed (verified against Apple's codesign).
            if rel == "_CodeSignature" || rel.hasPrefix("_CodeSignature/") { continue }
            if rel == executable { continue }

            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: url.path)
                if let rule = match(r1, rel), !rule.omit { files[rel] = ["symlink": target] }
                if let rule = match(r2, rel), !rule.omit { files2[rel] = ["symlink": target] }
                continue
            }
            if values.isDirectory == true { continue }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if let rule = match(r1, rel), !rule.omit {
                let sha1 = Data(Insecure.SHA1.hash(data: data))
                files[rel] = rule.optional ? ["hash": sha1, "optional": true] as [String: Any] : sha1
            }
            if let rule = match(r2, rel), !rule.omit {
                var entry: [String: Any] = ["hash2": Data(SHA256.hash(data: data))]
                if rule.optional { entry["optional"] = true }
                files2[rel] = entry
            }
        }

        let plist: [String: Any] = ["files": files, "files2": files2, "rules": rules1, "rules2": rules2]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
