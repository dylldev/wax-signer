import CryptoKit
import Foundation

/// A single open archive shared by inspection, extraction and compressed-entry reuse. Replacing its pathname
/// cannot switch the source mid-operation; in-place changes are detected by the fingerprints captured on reads.
public final class IPAArchiveSession {
    let zip: ZipArchive
    let url: URL
    public init(url: URL) throws { self.url = url.standardizedFileURL; zip = try ZipArchive(url: url) }
    public func inspect() throws -> IPAMetadata { try IPAInspector.inspect(archive: zip) }
    public func extract(to directory: URL, limits: IPAExtractor.Limits = IPAExtractor.Limits(),
                        progress: ((Int, Int) -> Void)? = nil, byteProgress: ((Double) -> Void)? = nil,
                        checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) throws -> IPAExtractionInventory {
        try IPAExtractor.extract(session: self, to: directory, limits: limits, progress: progress, byteProgress: byteProgress,
                                 checkCancellation: checkCancellation)
    }
}

/// Opaque provenance: only a successful extraction can produce this inventory.
public struct IPAExtractionInventory {
    public let names: [String]
    let session: IPAArchiveSession
    let directory: URL
}

struct FileFingerprint: Equatable {
    let sha256: Data
    let crc32: UInt32
    let size: Int

    /// Streaming EOF/short-read seam, also used by deterministic I/O failure tests.
    static func read(expectedSize: Int, next: (Int) throws -> Data?) throws -> FileFingerprint {
        guard expectedSize >= 0 else { throw IPAError.integrity("negative expected file size") }
        var hash = SHA256(), crc = CRC32.begin(), count = 0
        while let data = try next(256 * 1024), !data.isEmpty {
            guard data.count <= expectedSize - count else { throw IPAError.integrity("file grew while being read") }
            hash.update(data: data); crc = CRC32.update(crc, data); count += data.count
        }
        guard count == expectedSize else { throw IPAError.integrity("unexpected EOF: expected \(expectedSize) bytes, read \(count)") }
        return FileFingerprint(sha256: Data(hash.finalize()), crc32: CRC32.finish(crc), size: count)
    }

    static func file(_ url: URL) throws -> FileFingerprint {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw IPAError.unreadable("\(url.lastPathComponent): \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var closed = false
        defer { if !closed { try? handle.close() } }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & 0o170000 == 0o100000, before.st_size >= 0,
              before.st_size < UInt32.max else { throw IPAError.unsupportedZip("not a regular classic-ZIP file: \(url.lastPathComponent)") }
        let result = try read(expectedSize: Int(before.st_size), next: { try handle.read(upToCount: $0) })
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size, before.st_mode == after.st_mode else {
            throw IPAError.integrity("file changed while hashing: \(url.lastPathComponent)")
        }
        try handle.close(); closed = true
        return result
    }
}

struct ZipFingerprint: Equatable {
    let file: FileFingerprint
    let compressedSHA256: Data
}

/// The exact intended Payload tree, captured before signature verification. Dates are deliberately not identities.
public struct IPAArchiveManifest {
    enum Kind: Equatable { case file, directory, symlink }
    struct Record: Equatable {
        let name: String, kind: Kind, mode: UInt32, fingerprint: FileFingerprint?, target: String?
    }
    let directory: URL
    let rootFolder: String
    let records: [String: Record]

    public static func capture(directory: URL, rootFolder: String = "Payload") throws -> IPAArchiveManifest {
        let fm = FileManager.default
        guard !IPAInspector.isUnsafe(rootFolder), !rootFolder.contains("/") else { throw IPAError.unsafePath(rootFolder) }
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let base = directory.appendingPathComponent(rootFolder)
        let baseResolved = base.resolvingSymlinksInPath().path
        guard (try? fm.attributesOfItem(atPath: base.path)[.type]) as? FileAttributeType == .typeDirectory else { throw IPAError.noApp }
        var failure: Error?
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil, errorHandler: { _, error in
            failure = error; return false
        }) else { throw IPAError.unreadable("cannot enumerate \(rootFolder)") }
        var urls = [base]
        for case let url as URL in walker { urls.append(url) }
        if let failure { throw failure }
        try ClassicZIP.entryCount(urls.count)
        var records: [String: Record] = [:], seen = Set<String>()
        for url in urls {
            // Resolve the parent only, preserving each symlink's own name. Use the same canonical spelling
            // on both sides: macOS enumeration may return /private/var for a /var temporary-directory URL.
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            guard full == baseResolved || full.hasPrefix(baseResolved + "/") else { throw IPAError.unsafePath(url.path) }
            var name = full == baseResolved ? rootFolder : rootFolder + "/" + String(full.dropFirst(baseResolved.count + 1))
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let type = attrs[.type] as? FileAttributeType
            let permissions = UInt32((attrs[.posixPermissions] as? Int) ?? 0)
            guard permissions & 0o7000 == 0 else { throw IPAError.unsupportedZip("special permission bits: \(name)") }
            let kind: Kind, mode: UInt32, fingerprint: FileFingerprint?, target: String?
            switch type {
            case .typeRegular:
                kind = .file; mode = 0o100000 | (permissions & 0o777)
                fingerprint = try FileFingerprint.file(url); target = nil
            case .typeDirectory:
                kind = .directory; mode = 0o040000 | (permissions & 0o777)
                fingerprint = nil; target = nil; name += "/"
            case .typeSymbolicLink:
                kind = .symlink; mode = 0o120777; fingerprint = nil
                let t = try fm.destinationOfSymbolicLink(atPath: url.path)
                guard !t.isEmpty, t.utf8.count < 4096, !t.hasPrefix("/"), !t.contains("\0"),
                      IPAExtractor.staysInsideTheApp(link: name, target: t) else { throw IPAError.unsafePath(name) }
                let parts = name.split(separator: "/")
                let allowed = parts.count >= 3 && parts[1].hasSuffix(".app")
                    ? directory.appendingPathComponent(String(parts[0]) + "/" + String(parts[1])).resolvingSymlinksInPath().path : directory.resolvingSymlinksInPath().path
                let resolved = url.resolvingSymlinksInPath().path
                guard resolved == allowed || resolved.hasPrefix(allowed + "/") else { throw IPAError.unsafePath(name) }
                target = t
            default: throw IPAError.unsupportedZip("unsupported filesystem object: \(name)")
            }
            _ = try ClassicZIP.name(name)
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else { throw IPAError.duplicateEntry(name) }
            records[name] = Record(name: name, kind: kind, mode: mode, fingerprint: fingerprint, target: target)
        }
        return IPAArchiveManifest(directory: directory, rootFolder: rootFolder, records: records)
    }

    /// Examine actual staged ZIP bytes without allocating another extracted tree.
    public func verify(archive: URL) throws {
        let zip = try ZipArchive(url: archive)
        guard zip.entries.count == records.count else { throw IPAError.integrity("packaged entry set differs from the verified tree") }
        for entry in zip.entries {
            guard let record = records[entry.name], record.name.utf8.elementsEqual(entry.name.utf8),
                  entry.madeByUnix, entry.unixMode == record.mode,
                  entry.externalAttributes & 0x10 == (record.kind == .directory ? 0x10 : 0),
                  entry.isDirectory == (record.kind == .directory), entry.isSymlink == (record.kind == .symlink) else {
                throw IPAError.integrity("packaged path, type or permissions differ: \(entry.name)")
            }
            let fingerprint = try zip.fingerprint(entry)
            switch record.kind {
            case .file:
                guard fingerprint.file == record.fingerprint else { throw IPAError.integrity("packaged bytes differ: \(entry.name)") }
            case .directory:
                guard fingerprint.file.size == 0 else { throw IPAError.integrity("directory contains data: \(entry.name)") }
            case .symlink:
                guard try zip.data(for: entry) == Data(record.target!.utf8) else { throw IPAError.integrity("packaged link differs: \(entry.name)") }
            }
        }
    }

    /// Recheck content, paths, modes and symlinks against this snapshot without writing the tree.
    public func verifyTree() throws {
        let current = try Self.capture(directory: directory, rootFolder: rootFolder)
        guard current.records == records else { throw IPAError.integrity("working tree changed after its snapshot was captured") }
    }
}

enum ClassicZIP {
    static let maxEntries = Int(UInt16.max) - 1
    static let maxBytes = Int(UInt32.max) - 1
    static func entryCount(_ count: Int) throws {
        guard count >= 0, count <= maxEntries else { throw IPAError.unsupportedZip("ZIP64 sentinel entry count (maximum 65,534)") }
    }
    static func size(_ size: Int) throws -> UInt32 {
        guard size >= 0, size <= maxBytes else { throw IPAError.unsupportedZip("ZIP64 size or offset sentinel") }
        return UInt32(size)
    }
    static func name(_ name: String) throws -> Data {
        let bytes = Data(name.utf8)
        guard !IPAInspector.isUnsafe(name), bytes.count <= Int(UInt16.max) else { throw IPAError.unsupportedZip("unsafe or overlong ZIP filename") }
        return bytes
    }
}

/// Both temporary and destination must be siblings. POSIX rename preserves the old destination on failure.
enum ArchivePromotion {
    static func promote(_ staged: URL, to output: URL) throws {
        guard rename(staged.path, output.path) == 0 else {
            throw IPAError.unreadable("promoting validated archive: \(String(cString: strerror(errno)))")
        }
    }
}
