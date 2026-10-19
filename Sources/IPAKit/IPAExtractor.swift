import Foundation

/// Unpacks an IPA to a directory. Streams every entry to disk (no whole-file reads), verifies CRC32 and sizes,
/// keeps Unix permissions and symlinks, and refuses anything that could write outside the destination.
public enum IPAExtractor {
    public struct Limits {
        public var maxTotalBytes: Int = 6 * 1024 * 1024 * 1024
        public var maxEntries: Int = 65_534
        public init() {}
    }

    /// Whether a symlink's target stays inside the app bundle the link itself sits in. Real frameworks link to their
    /// siblings with `..`; anything that climbs above `Payload/<name>.app` is refused. Links outside any `.app` folder
    /// keep the strict rule: no `..` at all.
    static func staysInsideTheApp(link: String, target: String) -> Bool {
        let parts = link.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[1].hasSuffix(".app") else { return !target.split(separator: "/").contains("..") }
        var depth = parts.count - 1                  // directory the link lives in: Payload/X.app/... (depth counts its components)
        for component in target.split(separator: "/", omittingEmptySubsequences: true) {
            if component == ".." { depth -= 1; if depth < 2 { return false } }       // above Payload/X.app
            else if component != "." { depth += 1 }
        }
        return true
    }

    @discardableResult
    public static func extract(ipa: URL, to directory: URL, limits: Limits = Limits(),
                               progress: ((Int, Int) -> Void)? = nil, byteProgress: ((Double) -> Void)? = nil) throws -> [String] {
        try IPAArchiveSession(url: ipa).extract(to: directory, limits: limits, progress: progress, byteProgress: byteProgress).names
    }

    static func extract(session: IPAArchiveSession, to directory: URL, limits: Limits,
                        progress: ((Int, Int) -> Void)?, byteProgress: ((Double) -> Void)?) throws -> IPAExtractionInventory {
        let zip = session.zip
        guard zip.entries.count <= limits.maxEntries else { throw IPAError.unsupportedZip("too many entries") }
        let total = zip.entries.reduce(0) { $0 + $1.uncompressedSize }
        guard total <= limits.maxTotalBytes else {
            throw IPAError.unsupportedZip("archive expands to \(total) bytes, over the \(limits.maxTotalBytes) byte limit")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.resolvingSymlinksInPath().path
        var names: [String] = []

        // Pass 1, one entry at a time: every safety check, the directories and the symlinks. Regular files are only
        // queued, with the destination each one will really land on. Nothing here is left to chance in pass 2.
        struct Job { let entry: ZipEntry; let dest: URL }
        var jobs: [Job] = []
        var links: [(name: String, dest: URL, target: String)] = []      // checked again, against the real filesystem, once all exist
        var landing = Set<String>()
        var done = 0
        var doneBytes = 0
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
                      !target.hasPrefix("/"), Self.staysInsideTheApp(link: name, target: target) else {
                    throw IPAError.unsafePath("\(name) -> link target is not a relative path inside the app")
                }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                // A link planted where a queued file will land would redirect that file's write. Same check as for files.
                let linkReal = dest.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(dest.lastPathComponent).path
                guard landing.insert(linkReal).inserted else { throw IPAError.unsafePath("\(name) -> lands where another entry is written") }
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
                links.append((name, dest, target))
            } else {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Two names can reach one file through a link inside the archive; written at the same time they would race.
                let real = dest.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(dest.lastPathComponent).path
                guard landing.insert(real).inserted else { throw IPAError.unsafePath("\(name) -> lands on a file another entry also writes") }
                jobs.append(Job(entry: entry, dest: dest))
            }
            names.append(name)
            if entry.isDirectory || entry.isSymlink {
                done += 1
                doneBytes += entry.uncompressedSize
                progress?(done, zip.entries.count)
                byteProgress?(total > 0 ? Double(doneBytes) / Double(total) : 1)
            }
        }

        // The text of a target can look harmless while an earlier link moves where it really starts. So each target is
        // walked on the real filesystem: `..` is only allowed at the start (after a name it would mean something else
        // once a link is involved), and the end must land inside the app. Links in the middle of a path are fine, as in
        // versioned frameworks (`Versions/Current`): where they lead is checked by the final resolution.
        for link in links {
            let parts = link.name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            let inApp = parts.count >= 3 && parts[1].hasSuffix(".app")
            let allowedURL = inApp ? directory.appendingPathComponent(parts[0] + "/" + parts[1]) : directory
            // The app folder must be a real directory: a link standing in for it would move the boundary.
            if inApp, (try? fm.attributesOfItem(atPath: allowedURL.path))?[.type] as? FileAttributeType != .typeDirectory {
                throw IPAError.unsafePath("\(parts[0])/\(parts[1]) is not a plain folder")
            }
            let allowed = allowedURL.resolvingSymlinksInPath().path
            func inside(_ path: String) -> Bool { path == allowed || path.hasPrefix(allowed + "/") }
            let refuse = IPAError.unsafePath("\(link.name) -> link target leaves the app")

            var current = link.dest.deletingLastPathComponent().resolvingSymlinksInPath()
            var seenName = false
            for step in link.target.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
                if step == "." { continue }
                if step == ".." {
                    guard !seenName else { throw refuse }                  // `..` after a name: not allowed at all
                    current = current.deletingLastPathComponent()
                    guard inside(current.path) else { throw refuse }
                } else {
                    seenName = true
                    current = current.appendingPathComponent(step)
                }
            }
            guard inside(current.resolvingSymlinksInPath().path) else { throw refuse }
        }

        // Pass 2: the regular files, on every core. Biggest first so no core is left finishing one huge file alone.
        // Workers share the archive safely (positioned reads) and each writes a different file.
        let order = jobs.indices.sorted { jobs[$0].entry.uncompressedSize > jobs[$1].entry.uncompressedSize }
        let lock = NSLock()
        var failure: Error?
        DispatchQueue.concurrentPerform(iterations: order.count) { slot in
            lock.lock(); let stop = failure != nil; lock.unlock()
            if stop { return }
            let job = jobs[order[slot]]
            do {
                // Belt and braces: never write through a link, whatever happened since the safety pass.
                if (try? fm.attributesOfItem(atPath: job.dest.path))?[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw IPAError.unsafePath(job.entry.name)
                }
                try zip.extract(job.entry, to: job.dest)
                let mode = Int((job.entry.unixMode ?? 0o644) & 0o777) | 0o600   // owner can always read and rewrite
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: job.dest.path)
                lock.lock()
                done += 1; doneBytes += job.entry.uncompressedSize
                let (d, b) = (done, doneBytes)
                lock.unlock()
                // Callbacks run outside the lock, so a slow or blocking callback cannot stall the other workers.
                // They may be called from different threads, in any order of arrival.
                progress?(d, zip.entries.count)
                byteProgress?(total > 0 ? Double(b) / Double(total) : 1)
            } catch {
                lock.lock(); failure = failure ?? error; lock.unlock()
            }
        }
        if let failure { throw failure }
        return IPAExtractionInventory(names: names, session: session, directory: directory.standardizedFileURL.resolvingSymlinksInPath())
    }
}
