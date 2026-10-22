import Foundation

/// The places a bundle may contain other code we sign, in the order the signer walks them.
public enum BundleLayout {
    /// Directories inside a bundle that may hold nested code.
    public static let containers = ["Frameworks", "PlugIns", "Extensions", "AppClips", "Watch", "XPCServices"]

    /// Every nested .app/.appex inside `bundle`, deepest paths last, sorted for reproducibility.
    /// Mirrors what the signer signs and the editor renames.
    public static func nestedBundles(in bundle: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        // Depth is capped and symlinks are skipped: a crafted IPA can link a bundle back to its own parent.
        func walk(_ dir: URL, depth: Int) {
            guard depth < 8 else { return }
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
            for item in items.sorted(by: { $0.path < $1.path }) {
                guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                guard ["app", "appex"].contains(item.pathExtension) else { continue }   // frameworks and XPC services are signed directly, never renamed
                found.append(item)
                for container in containers { walk(item.appendingPathComponent(container), depth: depth + 1) }
            }
        }
        for container in containers { walk(bundle.appendingPathComponent(container), depth: 0) }
        return found
    }
}
