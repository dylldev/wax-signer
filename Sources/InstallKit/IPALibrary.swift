import Foundation

/// Wax's own shelf of IPAs: unsigned ones to sign and signed ones it made, kept in two folders with a small index.
public struct LibraryEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case unsigned, signed }
    public let id: UUID
    public let kind: Kind
    public let name: String
    public let version: String
    public let bundleID: String
    public let size: Int
    public let added: Date
    let fileName: String
}

public final class IPALibrary: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var stored: [LibraryEntry]

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    public init(root: URL) {
        self.root = root
        let data = try? Data(contentsOf: root.appendingPathComponent("index.json"))
        let all = data.flatMap { try? JSONDecoder().decode([LibraryEntry].self, from: $0) } ?? []
        // A file name is a single path component; anything else in a damaged index is ignored, never followed.
        stored = all.filter {
            $0.fileName == (($0.fileName as NSString).lastPathComponent) && !$0.fileName.isEmpty && $0.fileName != ".." && $0.fileName != "."
                && FileManager.default.fileExists(atPath: Self.fileURL(root, $0).path)
        }
    }

    /// The default shelf, in the app's own storage.
    public static func standard() -> IPALibrary {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return IPALibrary(root: support.appendingPathComponent("Library", isDirectory: true))
    }

    private static func fileURL(_ root: URL, _ e: LibraryEntry) -> URL {
        root.appendingPathComponent(e.kind.rawValue, isDirectory: true).appendingPathComponent(e.fileName)
    }

    public func url(for entry: LibraryEntry) -> URL { Self.fileURL(root, entry) }

    public func entries(_ kind: LibraryEntry.Kind) -> [LibraryEntry] {
        lock.withLock { stored.filter { $0.kind == kind }.sorted { $0.added > $1.added } }
    }

    public func totalBytes(_ kind: LibraryEntry.Kind) -> Int {
        lock.withLock { stored.filter { $0.kind == kind }.reduce(0) { $0 + $1.size } }
    }

    /// Copies `file` onto the shelf. The same bundle ID, version and size replaces the earlier copy.
    @discardableResult
    public func add(file: URL, kind: LibraryEntry.Kind, name: String, version: String, bundleID: String,
                    now: Date = Date()) throws -> LibraryEntry {
        let fm = FileManager.default
        let folder = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        let id = UUID()
        let entry = LibraryEntry(id: id, kind: kind, name: name, version: version, bundleID: bundleID, size: size, added: now,
                                 fileName: "\(id.uuidString).ipa")
        try fm.copyItem(at: file, to: Self.fileURL(root, entry))
        try lock.withLock {
            let same = stored.filter { $0.kind == kind && $0.bundleID == bundleID && $0.version == version && $0.size == size }
            let before = stored
            stored.removeAll { old in same.contains { $0.id == old.id } }
            stored.append(entry)
            do { try save() } catch {
                // Keep the shelf as it was, and the file that was just copied in is not left behind.
                stored = before
                try? fm.removeItem(at: Self.fileURL(root, entry))
                throw error
            }
            // Only once the index is safely written are the replaced files removed.
            for old in same { try? fm.removeItem(at: Self.fileURL(root, old)) }
        }
        return entry
    }

    public func remove(_ entry: LibraryEntry) throws {
        try lock.withLock {
            let updated = stored.filter { $0.id != entry.id }
            try save(updated)
            stored = updated
            try? FileManager.default.removeItem(at: Self.fileURL(root, entry))
        }
    }

    public func clear(_ kind: LibraryEntry.Kind) throws {
        try lock.withLock {
            let removed = stored.filter { $0.kind == kind }
            let updated = stored.filter { $0.kind != kind }
            try save(updated)
            stored = updated
            for e in removed { try? FileManager.default.removeItem(at: Self.fileURL(root, e)) }
        }
    }

    private func save(_ entries: [LibraryEntry]? = nil) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries ?? stored).write(to: indexURL, options: .atomic)
    }
}
