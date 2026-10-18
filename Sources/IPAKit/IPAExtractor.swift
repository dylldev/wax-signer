import Foundation

/// Unpacks an IPA to a directory. Streams every entry to disk (no whole-file reads), verifies CRC32 and sizes,
/// keeps Unix permissions and symlinks, and refuses anything that could write outside the destination.
public enum IPAExtractor {
    public struct Limits {
        public var maxTotalBytes: Int = 6 * 1024 * 1024 * 1024
        public var maxEntries: Int = 65_535
        public init() {}
    }

    @discardableResult
    public static func extract(ipa: URL, to directory: URL, limits: Limits = Limits(),
                               progress: ((Int, Int) -> Void)? = nil, byteProgress: ((Double) -> Void)? = nil) throws -> [String] {
        let zip = try ZipArchive(url: ipa)
        guard zip.entries.count <= limits.maxEntries else { throw IPAError.unsupportedZip("too many entries") }
        let total = zip.entries.reduce(0) { $0 + $1.uncompressedSize }
        guard total <= limits.maxTotalBytes else {
            throw IPAError.unsupportedZip("archive expands to \(total) bytes, over the \(limits.maxTotalBytes) byte limit")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.resolvingSymlinksInPath().path
        var done = 0
        var doneBytes = 0
        var names: [String] = []

        for entry in zip.entries {
            let name = entry.name
            if IPAInspector.isUnsafe(name) { throw IPAError.unsafePath(name) }
            let dest = directory.appendingPathComponent(name)
            // Parent must be inside the destination after resolving links created by earlier entries.
            let parent = dest.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard parent == root || parent.hasPrefix(root + "/") else { throw IPAError.unsafePath(name) }

            if let attributes = try? fm.attributesOfItem(atPath: dest.path) {
                let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
                guard entry.isDirectory || !isDirectory else { throw IPAError.unsafePath(name) }
                if !isDirectory { try fm.removeItem(at: dest) }
            }

            if entry.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if entry.isSymlink {
                let data = try zip.data(for: entry)   // a link target is a short path
                guard data.count < 4096, let target = String(data: data, encoding: .utf8), !target.isEmpty,
                      !target.hasPrefix("/"), !target.split(separator: "/").contains("..") else {
                    throw IPAError.unsafePath("\(name) -> link target is not a relative path inside the app")
                }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
            } else {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try zip.extract(entry, to: dest)
                let mode = Int((entry.unixMode ?? 0o644) & 0o777) | 0o600   // owner can always read and rewrite
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dest.path)
            }
            names.append(name)
            done += 1
            doneBytes += entry.uncompressedSize
            progress?(done, zip.entries.count)
            byteProgress?(total > 0 ? Double(doneBytes) / Double(total) : 1)
        }
        return names
    }
}
