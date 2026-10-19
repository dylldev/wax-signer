import CryptoKit
import zlib
import Foundation

struct ZipEntry {
    let name: String
    let flags: UInt16
    let method: UInt16
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
    /// High 16 bits are the Unix mode when the archive was made on a Unix host.
    let externalAttributes: UInt32
    let madeByUnix: Bool

    var unixMode: UInt32? { madeByUnix ? externalAttributes >> 16 : nil }
    var isDirectory: Bool { name.hasSuffix("/") }
    var isSymlink: Bool { (unixMode ?? 0) & 0xF000 == 0xA000 }
}

/// Minimal read-only zip reader: stored + deflate, no zip64, no encryption.
/// Reads from disk on demand; nothing is extracted.
final class ZipArchive {
    /// Cap for a single in-memory entry. We only read plists, never binaries.
    static let maxEntryBytes = 16 * 1024 * 1024
    static let maxCentralDirectoryBytes = 64 * 1024 * 1024

    let entries: [ZipEntry]
    private let handle: FileHandle
    private let fileSize: Int
    private let fingerprintLock = NSLock()
    private var observed: [String: ZipFingerprint] = [:]

    init(url: URL) throws {
        do {
            handle = try FileHandle(forReadingFrom: url)
            let size = try handle.seekToEnd()
            guard size <= UInt64(ClassicZIP.maxBytes) else { throw IPAError.unsupportedZip("archive exceeds classic ZIP limit") }
            fileSize = Int(size)
        } catch {
            throw IPAError.unreadable(error.localizedDescription)
        }
        let (parsed, cdOffset) = try Self.readCentralDirectory(handle: handle, fileSize: fileSize)
        entries = parsed
        try validateLayout(centralDirectoryOffset: cdOffset)
    }

    deinit { try? handle.close() }

    /// Compressed bytes are copied only from this open source and checked against the same extraction read.
    func copyRaw(_ entry: ZipEntry, expecting expected: ZipFingerprint, to write: (Data) throws -> Void) throws {
        let start = try payloadStart(of: entry)
        var remaining = entry.compressedSize, offset = start, hash = SHA256()
        while remaining > 0 {
            let n = min(256 * 1024, remaining), data = try read(at: offset, count: min(256 * 1024, remaining))
            hash.update(data: data); try write(data); offset += n; remaining -= n
        }
        guard Data(hash.finalize()) == expected.compressedSHA256 else {
            throw IPAError.integrity("original archive changed while reusing \(entry.name)")
        }
    }

    func data(for entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntryBytes, entry.compressedSize <= Self.maxEntryBytes + 65536 else {
            throw IPAError.unsupportedZip("entry too large: \(entry.name)")
        }
        var data = Data()
        _ = try stream(entry) { data.append($0) }
        return data
    }

    func fingerprint(_ entry: ZipEntry) throws -> ZipFingerprint {
        fingerprintLock.lock(); let cached = observed[entry.name]; fingerprintLock.unlock()
        return try cached ?? stream(entry, emit: { _ in })
    }

    /// A fresh stream is always used for extraction. Previously inspected bytes must agree with this read.
    func extract(_ entry: ZipEntry, to url: URL, checkpoint: (() throws -> Void)? = nil,
                 beforeWrite: ((Int) throws -> Void)? = nil) throws {
        try checkpoint?()
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw IPAError.unreadable(url.path) }
        let out = try FileHandle(forWritingTo: url)
        var closed = false, success = false
        defer {
            if !closed { try? out.close() }
            if !success { try? FileManager.default.removeItem(at: url) }
        }
        try out.truncate(atOffset: 0)
        _ = try stream(entry, checkpoint: checkpoint) { try beforeWrite?($0.count); try out.write(contentsOf: $0) }
        try out.close(); closed = true; success = true
    }

    /// Bounded streaming decode with exact compressed-input consumption, size, CRC and cryptographic fingerprints.
    private func stream(_ entry: ZipEntry, checkpoint: (() throws -> Void)? = nil, emit: (Data) throws -> Void) throws -> ZipFingerprint {
        try checkpoint?()
        let start = try payloadStart(of: entry)
        guard entry.method == 0 || entry.method == 8 else { throw IPAError.unsupportedZip("compression method \(entry.method)") }
        var rawHash = SHA256(), hash = SHA256(), crc = CRC32.begin(), written = 0
        var remaining = entry.compressedSize, offset = start
        func output(_ data: Data) throws {
            try checkpoint?()
            guard data.count <= entry.uncompressedSize - written else { throw IPAError.corruptEntry(entry.name) }
            written += data.count; hash.update(data: data); crc = CRC32.update(crc, data)
            try emit(data)
        }
        func input() throws -> Data {
            try checkpoint?()
            let n = min(256 * 1024, remaining), data = try read(at: offset, count: min(256 * 1024, remaining))
            offset += n; remaining -= n; rawHash.update(data: data)
            return data
        }
        if entry.method == 0 {
            while remaining > 0 { try output(input()) }
        } else {
            var decoder = z_stream()
            guard inflateInit2_(&decoder, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw IPAError.corruptEntry(entry.name)
            }
            defer { inflateEnd(&decoder) }
            var buffer = [UInt8](repeating: 0, count: 256 * 1024), finished = false
            while !finished {
                let data = try input()
                try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    decoder.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
                    decoder.avail_in = UInt32(raw.count)
                    repeat {
                        let before = decoder.avail_in
                        let status = buffer.withUnsafeMutableBufferPointer { dst in
                            decoder.next_out = dst.baseAddress!; decoder.avail_out = UInt32(dst.count)
                            return inflate(&decoder, Z_NO_FLUSH)
                        }
                        let produced = buffer.count - Int(decoder.avail_out)
                        if produced > 0 { try output(Data(buffer.prefix(produced))) }
                        if status == Z_STREAM_END {
                            guard remaining == 0, decoder.avail_in == 0, decoder.total_in == entry.compressedSize else {
                                throw IPAError.corruptEntry(entry.name)
                            }
                            finished = true; break
                        }
                        guard status == Z_OK, produced > 0 || decoder.avail_in < before else { throw IPAError.corruptEntry(entry.name) }
                    } while decoder.avail_in > 0 || decoder.avail_out == 0 || remaining == 0
                }
            }
        }
        guard written == entry.uncompressedSize, CRC32.finish(crc) == entry.crc32 else { throw IPAError.corruptEntry(entry.name) }
        let result = ZipFingerprint(file: FileFingerprint(sha256: Data(hash.finalize()), crc32: CRC32.finish(crc), size: written),
                                    compressedSHA256: Data(rawHash.finalize()))
        fingerprintLock.lock(); defer { fingerprintLock.unlock() }
        if let previous = observed[entry.name], previous != result {
            throw IPAError.integrity("original archive changed since inspection/extraction: \(entry.name)")
        }
        observed[entry.name] = result
        return result
    }

    /// Where an entry's stored bytes begin: past its local file header and variable-length fields.
    private func payloadStart(of entry: ZipEntry) throws -> Int {
        let header = try read(at: entry.localHeaderOffset, count: 30)
        guard header.u32(0) == 0x04034b50 else { throw IPAError.corruptEntry(entry.name) }
        let start = entry.localHeaderOffset + 30 + Int(header.u16(26)) + Int(header.u16(28))
        guard start >= 0, start + entry.compressedSize <= fileSize else { throw IPAError.corruptEntry(entry.name) }
        return start
    }

    // MARK: - Parsing

    private static func readCentralDirectory(handle: FileHandle, fileSize: Int) throws -> ([ZipEntry], Int) {
        func read(_ offset: Int, _ count: Int) throws -> Data {
            try handle.seek(toOffset: UInt64(offset))
            guard let d = try handle.read(upToCount: count), d.count == count else { throw IPAError.notAZip }
            return d
        }

        guard fileSize >= 22 else { throw IPAError.notAZip }
        let tailLen = min(fileSize, 22 + 0xFFFF)
        let tail = try read(fileSize - tailLen, tailLen)
        // Only structurally consistent candidates count: signature, then a comment that ends exactly at EOF.
        // More than one means parsers could disagree about the directory, so refuse.
        let candidates = (0...(tailLen - 22)).filter {
            tail.u32($0) == 0x06054b50 && $0 + 22 + Int(tail.u16($0 + 20)) == tailLen
        }
        guard let eocd = candidates.first else { throw IPAError.notAZip }
        guard candidates.count == 1 else { throw IPAError.unsupportedZip("ambiguous end of central directory") }
        let count = Int(tail.u16(eocd + 10))
        guard tail.u16(eocd + 4) == 0, tail.u16(eocd + 6) == 0, Int(tail.u16(eocd + 8)) == count else {
            throw IPAError.unsupportedZip("multi-disk archive")
        }
        let cdSize = Int(tail.u32(eocd + 12))
        let cdOffset = Int(tail.u32(eocd + 16))
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw IPAError.unsupportedZip("zip64")
        }
        guard cdSize <= maxCentralDirectoryBytes, cdOffset + cdSize <= fileSize - tailLen + eocd else { throw IPAError.notAZip }

        let cd = try read(cdOffset, cdSize)
        var entries: [ZipEntry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, cd.u32(p) == 0x02014b50 else { throw IPAError.notAZip }
            let flags = cd.u16(p + 8)
            let nameLen = Int(cd.u16(p + 28))
            let extraLen = Int(cd.u16(p + 30))
            let commentLen = Int(cd.u16(p + 32))
            guard nameLen > 0, p + 46 + nameLen + extraLen + commentLen <= cd.count, cd.u16(p + 34) == 0 else { throw IPAError.notAZip }
            let nameBytes = cd.subdata(in: (p + 46)..<(p + 46 + nameLen))
            guard let name = String(bytes: nameBytes, encoding: .utf8) else {
                throw IPAError.unsafePath(String(decoding: nameBytes, as: UTF8.self))
            }

            if flags & 1 != 0 { throw IPAError.unsupportedZip("encrypted entry") }
            let comp = cd.u32(p + 20), uncomp = cd.u32(p + 24), local = cd.u32(p + 42)
            if comp == 0xFFFF_FFFF || uncomp == 0xFFFF_FFFF || local == 0xFFFF_FFFF {
                throw IPAError.unsupportedZip("zip64")
            }
            entries.append(ZipEntry(name: name, flags: flags, method: cd.u16(p + 10), crc32: cd.u32(p + 16),
                                    compressedSize: Int(comp), uncompressedSize: Int(uncomp),
                                    localHeaderOffset: Int(local),
                                    externalAttributes: cd.u32(p + 38), madeByUnix: cd.u16(p + 4) >> 8 == 3))
            p += 46 + nameLen + extraLen + commentLen
        }
        guard p == cd.count else { throw IPAError.notAZip }

        var seen = Set<String>()
        for e in entries {
            // Case/normalization-insensitive: APFS would merge these on extraction.
            let key = e.name.precomposedStringWithCanonicalMapping.lowercased()
            if !seen.insert(key).inserted { throw IPAError.duplicateEntry(e.name) }
        }
        return (entries, cdOffset)
    }

    /// Entries must not overlap, must end before the central directory, and each local header
    /// must agree with the central one. Otherwise another extractor could see different content.
    private func validateLayout(centralDirectoryOffset cdOffset: Int) throws {
        let sorted = entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        for (i, e) in sorted.enumerated() {
            let limit = i + 1 < sorted.count ? sorted[i + 1].localHeaderOffset : cdOffset
            let header = try read(at: e.localHeaderOffset, count: 30)
            guard header.u32(0) == 0x04034b50 else { throw IPAError.corruptEntry(e.name) }
            let nameLen = Int(header.u16(26))
            let dataStart = e.localHeaderOffset + 30 + nameLen + Int(header.u16(28))
            guard dataStart + e.compressedSize <= limit else { throw IPAError.corruptEntry(e.name) }

            let localName = try read(at: e.localHeaderOffset + 30, count: nameLen)
            let flags = header.u16(6)
            guard localName == Data(e.name.utf8), header.u16(8) == e.method, flags == e.flags, flags & 1 == 0 else {
                throw IPAError.corruptEntry(e.name)
            }
            // Bit 3: sizes/CRC live in a trailing data descriptor, local fields are zero.
            if flags & 8 == 0 {
                guard header.u32(14) == e.crc32, Int(header.u32(18)) == e.compressedSize,
                      Int(header.u32(22)) == e.uncompressedSize else { throw IPAError.corruptEntry(e.name) }
            } else {
                let end = dataStart + e.compressedSize
                guard end + 12 <= limit else { throw IPAError.corruptEntry(e.name) }
                let dd = try read(at: end, count: min(16, limit - end))
                func matches(_ o: Int) -> Bool {
                    dd.count >= o + 12 && dd.u32(o) == e.crc32 && Int(dd.u32(o + 4)) == e.compressedSize
                        && Int(dd.u32(o + 8)) == e.uncompressedSize
                }
                guard matches(0) || (dd.u32(0) == 0x08074b50 && matches(4)) else { throw IPAError.corruptEntry(e.name) }
                guard (header.u32(14) == 0 || header.u32(14) == e.crc32),
                      (header.u32(18) == 0 || Int(header.u32(18)) == e.compressedSize),
                      (header.u32(22) == 0 || Int(header.u32(22)) == e.uncompressedSize) else { throw IPAError.corruptEntry(e.name) }
            }
        }
    }

    /// Reads `count` bytes at `offset` with `pread`, which does not move a shared file position, so several threads
    /// may read different entries from the same archive at once.
    private func read(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0 else { throw IPAError.notAZip }
        var data = Data(count: count)
        var done = 0
        let fd = handle.fileDescriptor
        while done < count {
            let n = data.withUnsafeMutableBytes { raw in pread(fd, raw.baseAddress! + done, count - done, off_t(offset + done)) }
            if n < 0 { if errno == EINTR { continue }; throw IPAError.unreadable(String(cString: strerror(errno))) }
            if n == 0 { throw IPAError.notAZip }          // ran past the end of the file
            done += n
        }
        return data
    }


}

private extension Data {
    func u16(_ o: Int) -> UInt16 {
        UInt16(self[startIndex + o]) | UInt16(self[startIndex + o + 1]) << 8
    }

    func u32(_ o: Int) -> UInt32 {
        UInt32(u16(o)) | UInt32(u16(o + 2)) << 16
    }
}
