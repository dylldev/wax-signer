import Foundation

/// The identity of a file for signature coverage: parent directory resolved through symlinks,
/// own name kept literal. Two paths that will read the same bytes must produce the same key.
public enum FileKey {
    public static func of(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).path
    }
}
