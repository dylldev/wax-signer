import CryptoKit
import Foundation
import IPAKit

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

        // Pass 1, serial and cheap: decide what is sealed and how. Symlinks are sealed on the spot; regular files are
        // queued so their bytes can be hashed on every core in pass 2.
        struct Item { let rel: String; let url: URL; let size: Int; let rule1: Rule?; let rule2: Rule? }
        var items: [Item] = []
        let keys = FileKey.Resolver()
        for case let url as URL in walker {
            // Resolve the folder the entry lives in, never the entry itself: a symlink is sealed as a link under its own name.
            let full = keys.of(url)
            guard full.hasPrefix(rootPath + "/") else { continue }
            let rel = String(full.dropFirst(rootPath.count + 1))
            // Only this bundle's own signature directory is excluded. A nested bundle's
            // _CodeSignature/CodeResources is sealed (verified against Apple's codesign).
            if rel == "_CodeSignature" || rel.hasPrefix("_CodeSignature/") { continue }
            if rel == executable { continue }

            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: url.path)
                if let rule = match(r1, rel), !rule.omit { files[rel] = ["symlink": target] }
                if let rule = match(r2, rel), !rule.omit { files2[rel] = ["symlink": target] }
                continue
            }
            if values.isDirectory == true { continue }
            let rule1 = match(r1, rel).flatMap { $0.omit ? nil : $0 }
            let rule2 = match(r2, rel).flatMap { $0.omit ? nil : $0 }
            if rule1 != nil || rule2 != nil { items.append(Item(rel: rel, url: url, size: values.fileSize ?? 0, rule1: rule1, rule2: rule2)) }
        }

        // Pass 2: hash the files in parallel. Each worker maps one file at a time, so memory stays small.
        var sha1s = [Data?](repeating: nil, count: items.count)
        var sha256s = [Data?](repeating: nil, count: items.count)
        let lock = NSLock()
        var failure: Error?
        let order = items.indices.sorted { items[$0].size > items[$1].size }      // biggest first
        DispatchQueue.concurrentPerform(iterations: order.count) { slot in
            lock.lock(); let stop = failure != nil; lock.unlock()
            if stop { return }
            let i = order[slot]
            do {
                let data = try Data(contentsOf: items[i].url, options: .mappedIfSafe)
                let one = items[i].rule1 != nil ? Data(Insecure.SHA1.hash(data: data)) : nil
                let two = items[i].rule2 != nil ? Data(SHA256.hash(data: data)) : nil
                lock.lock(); sha1s[i] = one; sha256s[i] = two; lock.unlock()
            } catch {
                lock.lock(); failure = failure ?? error; lock.unlock()
            }
        }
        if let failure { throw failure }

        for (i, item) in items.enumerated() {
            if let rule = item.rule1, let sha1 = sha1s[i] {
                files[item.rel] = rule.optional ? ["hash": sha1, "optional": true] as [String: Any] : sha1
            }
            if let rule = item.rule2, let sha256 = sha256s[i] {
                var entry: [String: Any] = ["hash2": sha256]
                if rule.optional { entry["optional"] = true }
                files2[item.rel] = entry
            }
        }

        let plist: [String: Any] = ["files": files, "files2": files2, "rules": rules1, "rules2": rules2]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
