import Foundation

public enum LibraryError: Error, LocalizedError {
    case io(String, String), changed(String), damagedIndex(String), unsafeFile(String), missingPending, cleanupPending(String)
    public var errorDescription: String? {
        switch self {
        case .io(let stage, let why): return "\(stage) failed: \(why). The source was kept. Free some space and retry saving, or export the retained IPA."
        case .changed(let why): return "\(why). Nothing was replaced. Retry saving from the retained original."
        case .damagedIndex(let why): return "The library index could not be read: \(why). Existing files were kept. Export recoverable files or use Recover Library Index."
        case .unsafeFile(let name): return "The library refused an unsafe file or folder: \(name). Existing files were kept."
        case .missingPending: return "The retained IPA is unavailable. Its record was kept; choose the original file again."
        case .cleanupPending(let why): return "The index update committed, but file cleanup is pending: \(why). Retry cleanup; retained files have not been silently discarded."
        }
    }
}

public struct LibraryEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case unsigned, signed }
    public enum Provenance: String, Codable, Sendable { case fileImport, sourceDownload, waxSigned, recoveredUnknown }
    public let id: UUID
    public let kind: Kind
    public let name: String
    public let version: String
    public let bundleID: String
    public let size: Int
    public let added: Date
    let fileName: String
    public var sha256: String?
    public var build: String?
    public var provenance: Provenance?
}

public struct LibrarySaveResult: Sendable {
    public let entry: LibraryEntry
    public let alreadySaved: Bool
    public let warning: String?
}

/// A retained artifact is not a shelf entry until its index commit succeeds.
public struct LibraryPending: Codable, Identifiable, Sendable {
    enum Phase: String, Codable, Sendable { case preparing, ready, committing }
    public let id: UUID
    var entry: LibraryEntry
    var phase: Phase
    public var name: String { entry.name }
    public var kind: LibraryEntry.Kind { entry.kind }
    public var provenance: LibraryEntry.Provenance? { entry.provenance }
}

public struct LibraryRecoveryItem: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let pendingID: UUID?
}

/// Serial, recoverable shelf transactions. No metadata-based replacement and no automatic orphan deletion.
public final class IPALibrary: @unchecked Sendable {
    public let root: URL
    // All instances for one canonical root share a lock. No cross-process writers are used by Wax.
    private static let registryLock = NSLock()
    private static var locks: [String: NSRecursiveLock] = [:]
    private let lock: NSRecursiveLock
    private var stored: [LibraryEntry] = []
    private var deletions: [LibraryEntry] = []
    private var problem: String?
    private var loaded = false
    enum Checkpoint { case beforeCopy, copyChunk, afterCopy, hashRead, beforeJournalWrite, beforePublish, afterPublish, beforeIndexWrite, afterIndexWrite, beforeCleanup }
    private let fault: ((Checkpoint, URL) throws -> Void)?
    private struct Index: Codable { var version = 2; var entries: [LibraryEntry]; var deletions: [LibraryEntry] }
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var pendingRoot: URL { root.appendingPathComponent("pending", isDirectory: true) }

    public convenience init(root: URL) { self.init(root: root, fault: nil) }
    init(root: URL, fault: ((Checkpoint, URL) throws -> Void)?) {
        self.root = root.standardizedFileURL; self.fault = fault
        let key = root.resolvingSymlinksInPath().path
        lock = Self.registryLock.withLock {
            if let existing = Self.locks[key] { return existing }
            let created = NSRecursiveLock(); Self.locks[key] = created; return created
        }
    }
    public static func standard() -> IPALibrary {
        IPALibrary(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true))
    }
    public var issue: String? { lock.withLock {
        if !loaded { load() }
        if let problem { return problem }
        let missing = stored.filter { (try? checkFile(rawURL($0), kind: $0.kind)) == nil }.count
        return missing == 0 ? nil : "\(missing) referenced IPA file(s) are unavailable. Their index references were kept."
    } }
    public func url(for entry: LibraryEntry) -> URL {
        lock.withLock {
            let candidate = rawURL(entry)
            return (try? checkFile(candidate, kind: entry.kind)) != nil ? candidate : root.appendingPathComponent("unavailable-\(entry.id).ipa")
        }
    }
    public func entries(_ kind: LibraryEntry.Kind) -> [LibraryEntry] {
        lock.withLock {
            if !loaded { load() }
            return stored.filter { $0.kind == kind && (try? checkFile(rawURL($0), kind: kind)) != nil }.sorted { $0.added > $1.added }
        }
    }
    public func totalBytes(_ kind: LibraryEntry.Kind) -> Int { entries(kind).reduce(0) { $0 + $1.size } }

    /// Caller-owned originals are never moved or deleted. Only committed copies are eligible for deduplication.
    @discardableResult public func add(file: URL, kind: LibraryEntry.Kind, name: String, version: String, bundleID: String,
                                      now: Date = Date(), build: String? = nil, provenance: LibraryEntry.Provenance? = nil) throws -> LibraryEntry {
        try save(file: file, kind: kind, name: name, version: version, bundleID: bundleID, now: now, build: build, provenance: provenance).entry
    }
    public func save(file: URL, kind: LibraryEntry.Kind, name: String, version: String, bundleID: String,
                     now: Date = Date(), build: String? = nil, provenance: LibraryEntry.Provenance? = nil) throws -> LibrarySaveResult {
        let pending = try prepare(file: file, kind: kind, name: name, version: version, bundleID: bundleID, now: now, build: build, provenance: provenance)
        return try commit(pending.id)
    }

    /// Reserve a unique durable location before download/signing. The producer must complete it before commit.
    public func reserve(kind: LibraryEntry.Kind, name: String, version: String = "", bundleID: String = "", now: Date = Date(),
                        build: String? = nil, provenance: LibraryEntry.Provenance? = nil) throws -> LibraryPending {
        try lock.withLock {
            try directory(root); load()
            let id = UUID()
            let entry = LibraryEntry(id: id, kind: kind, name: name, version: version, bundleID: bundleID, size: 0, added: now,
                                     fileName: "\(id.uuidString).ipa", sha256: nil, build: build, provenance: provenance)
            let pending = LibraryPending(id: id, entry: entry, phase: .preparing)
            try directory(pendingRoot)
            try FileManager.default.createDirectory(at: pendingFolder(id), withIntermediateDirectories: false)
            try journal(pending)
            return pending
        }
    }
    public func pendingURL(_ id: UUID) throws -> URL {
        try lock.withLock {
            try checkPendingFolder(id)
            let pending = try readPending(id)
            let artifact = pendingFolder(id).appendingPathComponent("artifact.ipa")
            if FileManager.default.fileExists(atPath: artifact.path) { try plainFile(artifact); return artifact }
            let part = pendingFolder(id).appendingPathComponent("artifact.part")
            if FileManager.default.fileExists(atPath: part.path) { try plainFile(part); return part }
            let published = rawURL(pending.entry)
            if FileManager.default.fileExists(atPath: published.path) { try checkFile(published, kind: pending.entry.kind); return published }
            return artifact // Reserved output, not created by the producer yet.
        }
    }
    public func prepare(file: URL, kind: LibraryEntry.Kind, name: String, version: String, bundleID: String, now: Date = Date(),
                        build: String? = nil, provenance: LibraryEntry.Provenance? = nil) throws -> LibraryPending {
        try lock.withLock {
            let pending = try reserve(kind: kind, name: name, version: version, bundleID: bundleID, now: now, build: build, provenance: provenance)
            let folder = pendingFolder(pending.id), part = folder.appendingPathComponent("artifact.part")
            let digest = try LibraryFileIO.copy(file, to: part, checkpoint: checkpoint)
            try FileManager.default.moveItem(at: part, to: folder.appendingPathComponent("artifact.ipa"))
            return try finish(pending, digest: digest)
        }
    }
    /// Used after signing or inspection of our retained copy, not inferred from a publisher's signature marker.
    public func complete(_ id: UUID, name: String, version: String, bundleID: String, build: String?, provenance: LibraryEntry.Provenance?) throws -> LibraryPending {
        try lock.withLock {
            try directory(root)
            let old = try readPending(id), file = try pendingURL(id)
            // A prepared digest is an expectation, not proof of current bytes. Commit verifies it before
            // duplicate cleanup or against the published file; metadata completion need not hash it again.
            let digest: LibraryFileIO.Digest
            if let expected = old.entry.sha256 { digest = LibraryFileIO.Digest(sha256: expected, size: old.entry.size) }
            else { digest = try LibraryFileIO.hash(file, read: { try self.checkpoint(.hashRead, file) }) }
            let entry = LibraryEntry(id: old.entry.id, kind: old.entry.kind, name: name, version: version, bundleID: bundleID, size: digest.size,
                                     added: old.entry.added, fileName: old.entry.fileName, sha256: digest.sha256, build: build, provenance: provenance)
            if file.lastPathComponent == "artifact.part" {
                try FileManager.default.moveItem(at: file, to: pendingFolder(id).appendingPathComponent("artifact.ipa"))
            }
            let updated = LibraryPending(id: id, entry: entry, phase: .ready)
            try journal(updated); return updated
        }
    }
    public func commit(_ id: UUID) throws -> LibrarySaveResult {
        try lock.withLock {
            try ready()
            var pending = try readPending(id)
            guard pending.phase != .preparing, let expected = pending.entry.sha256 else { throw LibraryError.missingPending }
            let file = try pendingURL(id)
            let actual = LibraryFileIO.Digest(sha256: expected, size: pending.entry.size)
            func verifyRetained() throws {
                guard try LibraryFileIO.hash(file, read: { try self.checkpoint(.hashRead, file) }) == actual else {
                    throw LibraryError.changed("The retained IPA changed before saving")
                }
            }
            if let present = stored.first(where: { $0.id == pending.entry.id }) {
                guard present.sha256 == expected, present.kind == pending.entry.kind, present.fileName == pending.entry.fileName else { throw LibraryError.changed("A transaction ID is already in use") }
                try verifyRetained()
                return LibrarySaveResult(entry: present, alreadySaved: true, warning: cleanup(pending.id))
            }
            // Size is only a prefilter. Verify the actual existing bytes before returning Already Saved.
            for i in stored.indices where stored[i].kind == pending.entry.kind && stored[i].size == actual.size {
                if let old = stored[i].sha256, old != expected { continue }
                let oldURL = rawURL(stored[i])
                guard (try? checkFile(oldURL, kind: stored[i].kind)) != nil else { continue }
                let oldDigest = try LibraryFileIO.hash(oldURL, read: { try self.checkpoint(.hashRead, oldURL) })
                if oldDigest.sha256 == expected, oldDigest.size == actual.size {
                    try verifyRetained()
                    var updated = stored; updated[i].sha256 = expected
                    try persist(updated, deletions: deletions); stored = updated
                    return LibrarySaveResult(entry: stored[i], alreadySaved: true, warning: cleanup(id))
                }
            }
            pending.phase = .committing; try journal(pending)
            try publish(pending)
            let updated = stored + [pending.entry]
            try persist(updated, deletions: deletions); stored = updated
            try checkpoint(.afterIndexWrite, indexURL)
            return LibrarySaveResult(entry: pending.entry, alreadySaved: false, warning: cleanup(id))
        }
    }

    public func remove(_ entry: LibraryEntry) throws {
        try lock.withLock {
            try ready()
            guard let actual = stored.first(where: { $0.id == entry.id }) else { try cleanDeletions(); return }
            let updated = stored.filter { $0.id != actual.id }, removed = deletions + [actual]
            try persist(updated, deletions: removed); stored = updated; deletions = removed
            try cleanDeletions()
        }
    }
    public func clear(_ kind: LibraryEntry.Kind) throws {
        try lock.withLock {
            try ready()
            let removed = deletions + stored.filter { $0.kind == kind }, updated = stored.filter { $0.kind != kind }
            try persist(updated, deletions: removed); stored = updated; deletions = removed
            try cleanDeletions()
        }
    }

    /// Finish only journaled commits. Unfinished producers and unknown orphans remain available for explicit recovery.
    public func recover() throws {
        try lock.withLock {
            try ready()
            for id in pendingIDs() {
                do {
                    let pending = try readPending(id)
                    if pending.phase == .committing { _ = try commit(id) }
                    else if stored.contains(where: { $0.id == id }) { _ = cleanup(id) }
                } catch { problem = error.localizedDescription }
            }
            try cleanDeletions()
        }
    }
    public func recoveryItems() -> [LibraryRecoveryItem] {
        lock.withLock {
            if !loaded { load() }
            var result: [LibraryRecoveryItem] = []
            for id in pendingIDs() where !stored.contains(where: { $0.id == id }) {
                guard let pending = try? readPending(id), let reserved = try? pendingURL(id) else { continue }
                let part = pendingFolder(id).appendingPathComponent("artifact.part")
                let url = (try? plainFile(reserved)) != nil ? reserved : part
                guard (try? plainFile(url)) != nil else { continue }
                result.append(LibraryRecoveryItem(id: id.uuidString, url: url, name: pending.name, pendingID: id))
            }
            // A broken/missing journal must not hide its only surviving artifact. Expose, never auto-delete it.
            if (try? plainDirectory(pendingRoot)) != nil {
                for folder in (try? FileManager.default.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil)) ?? [] {
                    guard (try? plainDirectory(folder)) != nil else { continue }
                    let known = UUID(uuidString: folder.lastPathComponent).flatMap { try? readPending($0) } != nil
                    if known { continue }
                    for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                        guard ["ipa", "part"].contains(file.pathExtension.lowercased()), (try? plainFile(file)) != nil else { continue }
                        result.append(LibraryRecoveryItem(id: file.path, url: file, name: "Unrecognized retained file: " + file.lastPathComponent, pendingID: nil))
                    }
                }
            }
            let referenced = Set((stored + deletions).map { rawURL($0).standardizedFileURL.path })
            for kind in [LibraryEntry.Kind.unsigned, .signed] {
                let folder = root.appendingPathComponent(kind.rawValue)
                guard (try? plainDirectory(folder)) != nil else { continue }
                for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                    guard file.pathExtension.lowercased() == "ipa", !referenced.contains(file.standardizedFileURL.path), (try? plainFile(file)) != nil else { continue }
                    result.append(LibraryRecoveryItem(id: file.path, url: file, name: file.lastPathComponent, pendingID: nil))
                }
            }
            // Completed downloads/imports that have not reached the transaction stage are never auto-deleted.
            let incoming = root.appendingPathComponent("incoming")
            if (try? plainDirectory(incoming)) != nil {
                for folder in (try? FileManager.default.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil)) ?? [] {
                    guard (try? plainDirectory(folder)) != nil else { continue }
                    for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension.lowercased() == "ipa" {
                        if (try? plainFile(file)) != nil { result.append(LibraryRecoveryItem(id: file.path, url: file, name: file.lastPathComponent, pendingID: nil)) }
                    }
                }
            }
            return result
        }
    }
    public func pendingRecord(_ id: UUID) throws -> LibraryPending { try lock.withLock { try readPending(id) } }

    /// Cleanup only a known completed producer copy under incoming/<UUID>. Never a caller's arbitrary URL.
    public func removeIncoming(_ file: URL) throws {
        try lock.withLock {
            let incoming = root.appendingPathComponent("incoming").resolvingSymlinksInPath().path
            let parent = file.deletingLastPathComponent()
            guard UUID(uuidString: parent.lastPathComponent) != nil,
                  parent.deletingLastPathComponent().resolvingSymlinksInPath().path == incoming else { return }
            try plainDirectory(root); try plainDirectory(root.appendingPathComponent("incoming")); try plainDirectory(parent); try plainFile(file)
            try checkpoint(.beforeCleanup, file); try FileManager.default.removeItem(at: file)
            if try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty { try FileManager.default.removeItem(at: parent) }
        }
    }
    public func incomingDirectory() throws -> URL {
        try lock.withLock {
            try directory(root)
            let incoming = root.appendingPathComponent("incoming", isDirectory: true); try directory(incoming)
            let unique = incoming.appendingPathComponent(UUID().uuidString, isDirectory: true); try directory(unique); return unique
        }
    }
    /// Explicit user-directed repair. Preserve damaged bytes and every artifact; never infer equality from metadata.
    public func repairIndex() throws {
        try lock.withLock {
            try directory(root)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                try plainFile(indexURL)
                try FileManager.default.copyItem(at: indexURL, to: root.appendingPathComponent("index-damaged-\(UUID().uuidString).json"))
            }
            var recovered: [LibraryEntry] = (try? decodeIndex(indexURL))?.entries ?? []
            let backup = root.appendingPathComponent("index.previous.json")
            if recovered.isEmpty, let index = try? decodeIndex(backup) { recovered = index.entries }
            for kind in [LibraryEntry.Kind.unsigned, .signed] {
                let folder = root.appendingPathComponent(kind.rawValue)
                guard (try? plainDirectory(folder)) != nil else { continue }
                for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension.lowercased() == "ipa" {
                    guard (try? plainFile(file)) != nil, !recovered.contains(where: { $0.kind == kind && $0.fileName == file.lastPathComponent }) else { continue }
                    let hash = try LibraryFileIO.hash(file)
                    let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
                    recovered.append(LibraryEntry(id: recovered.contains(where: { $0.id == id }) ? UUID() : id, kind: kind, name: file.deletingPathExtension().lastPathComponent,
                        version: "", bundleID: "", size: hash.size, added: Date(), fileName: file.lastPathComponent, sha256: hash.sha256, build: nil, provenance: .recoveredUnknown))
                }
            }
            // Do not overwrite the known-good backup with the damaged index.
            try writeIndex(recovered, deletions: [])
            stored = recovered; deletions = []; loaded = true; problem = nil
        }
    }

    private func finish(_ pending: LibraryPending, digest: LibraryFileIO.Digest) throws -> LibraryPending {
        var entry = pending.entry
        entry = LibraryEntry(id: entry.id, kind: entry.kind, name: entry.name, version: entry.version, bundleID: entry.bundleID, size: digest.size,
                             added: entry.added, fileName: entry.fileName, sha256: digest.sha256, build: entry.build, provenance: entry.provenance)
        let ready = LibraryPending(id: pending.id, entry: entry, phase: .ready); try journal(ready); return ready
    }
    private func publish(_ pending: LibraryPending) throws {
        let source = pendingFolder(pending.id).appendingPathComponent("artifact.ipa"), dest = rawURL(pending.entry)
        try directory(root.appendingPathComponent(pending.entry.kind.rawValue, isDirectory: true))
        if FileManager.default.fileExists(atPath: source.path) {
            guard !FileManager.default.fileExists(atPath: dest.path) else { throw LibraryError.changed("The reserved destination already exists") }
            try plainFile(source); try checkpoint(.beforePublish, source)
            try FileManager.default.moveItem(at: source, to: dest)
            try checkpoint(.afterPublish, dest)
        }
        try checkFile(dest, kind: pending.entry.kind)
        let hash = try LibraryFileIO.hash(dest, read: { try self.checkpoint(.hashRead, dest) })
        guard hash.sha256 == pending.entry.sha256, hash.size == pending.entry.size else { throw LibraryError.changed("The published copy did not match its transaction") }
    }
    private func ready() throws {
        try directory(root)
        load()
        if let problem { throw LibraryError.damagedIndex(problem) }
    }
    private func load() {
        loaded = true
        do {
            try plainDirectory(root)
            if !FileManager.default.fileExists(atPath: indexURL.path) { stored = []; deletions = []; problem = nil; return }
            let index = try decodeIndex(indexURL); stored = index.entries; deletions = index.deletions; problem = nil
        } catch {
            // Keep any previously loaded references, and block writes. A malformed index is never an empty index.
            problem = error.localizedDescription
        }
    }
    private func decodeIndex(_ url: URL) throws -> Index {
        try plainFile(url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.size] as? Int ?? Int.max) <= 64 * 1024 * 1024 else { throw LibraryError.damagedIndex("index is too large") }
        let data = try Data(contentsOf: url), decoder = JSONDecoder()
        let index: Index
        if let legacy = try? decoder.decode([LibraryEntry].self, from: data) { index = Index(entries: legacy, deletions: []) }
        else { index = try decoder.decode(Index.self, from: data) }
        guard index.version == 2, Set(index.entries.map(\.id)).count == index.entries.count,
              (index.entries + index.deletions).allSatisfy({ safeName($0.fileName) && $0.size >= 0 && validDigest($0.sha256) }) else {
            throw LibraryError.damagedIndex("unsupported version or invalid entry")
        }
        return index
    }
    private func persist(_ entries: [LibraryEntry], deletions: [LibraryEntry]) throws {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            _ = try decodeIndex(indexURL)
            let backup = root.appendingPathComponent("index.previous.json")
            try rejectLink(backup)
            try Data(contentsOf: indexURL).write(to: backup, options: .atomic)
        }
        try writeIndex(entries, deletions: deletions)
    }
    private func writeIndex(_ entries: [LibraryEntry], deletions: [LibraryEntry]) throws {
        try rejectLink(indexURL); try checkpoint(.beforeIndexWrite, indexURL)
        do {
            let data = try JSONEncoder().encode(Index(entries: entries, deletions: deletions))
            guard data.count <= 64 * 1024 * 1024 else { throw LibraryError.damagedIndex("index size limit would be exceeded") }
            try data.write(to: indexURL, options: .atomic)
        }
        catch { throw LibraryError.io("Writing the library index", error.localizedDescription) }
    }
    private func journal(_ pending: LibraryPending) throws {
        try checkPendingFolder(pending.id)
        let url = pendingFolder(pending.id).appendingPathComponent("record.json")
        try rejectLink(url); try checkpoint(.beforeJournalWrite, url)
        let data = try JSONEncoder().encode(pending)
        guard data.count < 64 * 1024 else { throw LibraryError.unsafeFile("transaction metadata exceeds 64 KiB") }
        try data.write(to: url, options: .atomic)
    }
    private func readPending(_ id: UUID) throws -> LibraryPending {
        try checkPendingFolder(id)
        let url = pendingFolder(id).appendingPathComponent("record.json"); try plainFile(url)
        guard (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? Int.max) < 64 * 1024 else { throw LibraryError.unsafeFile("oversized transaction") }
        let pending = try JSONDecoder().decode(LibraryPending.self, from: Data(contentsOf: url))
        guard pending.id == id, pending.entry.id == id, pending.entry.fileName == "\(id.uuidString).ipa", validDigest(pending.entry.sha256), pending.entry.size >= 0 else { throw LibraryError.unsafeFile("invalid transaction") }
        return pending
    }
    private func cleanup(_ id: UUID) -> String? {
        do {
            let folder = pendingFolder(id); try checkPendingFolder(id); try checkpoint(.beforeCleanup, folder)
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            guard contents.allSatisfy({ ["record.json", "artifact.ipa", "artifact.part"].contains($0) }) else { throw LibraryError.cleanupPending("unknown transaction files were retained") }
            try FileManager.default.removeItem(at: folder); return nil
        } catch { return LibraryError.cleanupPending(error.localizedDescription).localizedDescription }
    }
    private func cleanDeletions() throws {
        var remaining: [LibraryEntry] = []
        for entry in deletions {
            if stored.contains(where: { $0.kind == entry.kind && $0.fileName == entry.fileName }) { continue }
            do {
                let url = rawURL(entry)
                if FileManager.default.fileExists(atPath: url.path) { try checkFile(url, kind: entry.kind); try checkpoint(.beforeCleanup, url); try FileManager.default.removeItem(at: url) }
            } catch { remaining.append(entry) }
        }
        if remaining.count != deletions.count { try persist(stored, deletions: remaining); deletions = remaining }
        if !remaining.isEmpty { throw LibraryError.cleanupPending("\(remaining.count) file(s) remain") }
    }
    private func checkpoint(_ point: Checkpoint, _ url: URL) throws { try fault?(point, url) }
    private func pendingFolder(_ id: UUID) -> URL { pendingRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func pendingIDs() -> [UUID] {
        guard (try? plainDirectory(root)) != nil, (try? plainDirectory(pendingRoot)) != nil else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: pendingRoot.path)) ?? []).compactMap(UUID.init(uuidString:))
    }
    private func rawURL(_ entry: LibraryEntry) -> URL { root.appendingPathComponent(entry.kind.rawValue).appendingPathComponent(safeName(entry.fileName) ? entry.fileName : "invalid-entry") }
    private func safeName(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0") }
    private func validDigest(_ hash: String?) -> Bool { hash == nil || (hash!.count == 64 && hash!.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }) }
    private func checkPendingFolder(_ id: UUID) throws { try plainDirectory(root); try plainDirectory(pendingRoot); try plainDirectory(pendingFolder(id)) }
    private func checkFile(_ url: URL, kind: LibraryEntry.Kind) throws { try plainDirectory(root); try plainDirectory(root.appendingPathComponent(kind.rawValue)); try plainFile(url) }
    private func directory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try plainDirectory(url) }
        else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); try plainDirectory(url) }
    }
    private func rejectLink(_ url: URL) throws {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink { throw LibraryError.unsafeFile(url.lastPathComponent) }
    }
    private func plainDirectory(_ url: URL) throws { guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else { throw LibraryError.unsafeFile(url.lastPathComponent) } }
    private func plainFile(_ url: URL) throws { guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else { throw LibraryError.unsafeFile(url.lastPathComponent) } }
}
