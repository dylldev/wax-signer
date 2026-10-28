import Foundation

/// The identity of a file for signature coverage: parent directory resolved through symlinks,
/// own name kept literal. Two paths that will read the same bytes must produce the same key.
public enum FileKey {
    public static func of(_ url: URL) -> String {
        join(url.deletingLastPathComponent().resolvingSymlinksInPath().path, url.lastPathComponent)
    }

    /// `of`, with each parent folder resolved only once. For one walk over a tree that nothing changes during the walk
    /// (a signing run's own work tree). Not thread-safe.
    public final class Resolver {
        private var parents: [String: String] = [:]
        public init() {}
        public func of(_ url: URL) -> String {
            let parent = url.deletingLastPathComponent()
            if let known = parents[parent.path] { return FileKey.join(known, url.lastPathComponent) }
            let resolved = parent.resolvingSymlinksInPath().path
            parents[parent.path] = resolved
            return FileKey.join(resolved, url.lastPathComponent)
        }
    }

    /// Same text as `appendingPathComponent(name).path`, without the filesystem lookup that call makes.
    static func join(_ parent: String, _ name: String) -> String { parent == "/" ? "/" + name : parent + "/" + name }
}
