import Compression
import Foundation

struct ZipEntry {
    let name: String
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
    private static let maxCentralDirectoryBytes = 64 * 1024 * 1024

    let entries: [ZipEntry]
    private let handle: FileHandle
    private let fileSize: Int

    init(url: URL) throws {
        do {
            handle = try FileHandle(forReadingFrom: url)
            fileSize = Int(try handle.seekToEnd())
        } catch {
            throw IPAError.unreadable(error.localizedDescription)
        }
        let (parsed, cdOffset) = try Self.readCentralDirectory(handle: handle, fileSize: fileSize)
        entries = parsed
        try validateLayout(centralDirectoryOffset: cdOffset)
    }

    deinit { try? handle.close() }

    /// Streams an entry's stored bytes (still compressed) without inflating them.
    func copyRaw(_ entry: ZipEntry, to write: (Data) throws -> Void) throws {
        guard entry.method == 0 || entry.method == 8 else { throw IPAError.unsupportedZip("compression method \(entry.method)") }
        let start = try payloadStart(of: entry)
        var remaining = entry.compressedSize, offset = start
        while remaining > 0 {
            let n = min(1 << 20, remaining)
            try write(try read(at: offset, count: n))
            offset += n; remaining -= n
        }
    }

    func data(for entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntryBytes,
              entry.compressedSize <= Self.maxEntryBytes + 65536 else {
            throw IPAError.unsupportedZip("entry too large: \(entry.name)")
        }
        let start = try payloadStart(of: entry)
        let raw = try read(at: start, count: entry.compressedSize)

        let out: Data
        switch entry.method {
        case 0:
            out = raw
        case 8:
            out = try Self.inflate(raw, expected: entry.uncompressedSize, name: entry.name)
        default:
            throw IPAError.unsupportedZip("compression method \(entry.method)")
        }
        guard out.count == entry.uncompressedSize, CRC32.checksum(out) == entry.crc32 else {
            throw IPAError.corruptEntry(entry.name)
        }
        return out
    }

    // MARK: - Streaming extraction

    /// Writes one entry to `url` without holding it in memory. Verifies size and CRC32.
    func extract(_ entry: ZipEntry, to url: URL) throws {
        let start = try payloadStart(of: entry)
        guard entry.method == 0 || entry.method == 8 else {
            throw IPAError.unsupportedZip("compression method \(entry.method)")
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out: FileHandle
        do { out = try FileHandle(forWritingTo: url) } catch { throw IPAError.unreadable(error.localizedDescription) }
        defer { try? out.close() }

        var crc = CRC32.begin()
        var written = 0
        func emit(_ chunk: Data) throws {
            guard !chunk.isEmpty else { return }
            written += chunk.count
            guard written <= entry.uncompressedSize else { throw IPAError.corruptEntry(entry.name) }
            crc = CRC32.update(crc, chunk)
            try out.write(contentsOf: chunk)
        }

        let chunkSize = 256 * 1024
        var remaining = entry.compressedSize
        var offset = start
        if entry.method == 0 {
            while remaining > 0 {
                let n = min(chunkSize, remaining)
                try emit(try read(at: offset, count: n))
                offset += n; remaining -= n
            }
        } else {
            guard let stream = CompressionStream(COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) else {
                throw IPAError.corruptEntry(entry.name)
            }
            var dst = [UInt8](repeating: 0, count: chunkSize)
            var finished = false
            while !finished {
                let n = min(chunkSize, remaining)
                let src = n > 0 ? try read(at: offset, count: n) : Data()
                offset += n; remaining -= n
                let final = remaining == 0
                try src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                    var idle = 0
                    repeat {
                        let before = stream.pendingInput
                        let status = dst.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: final) }
                        let produced = chunkSize - stream.pendingOutput
                        if produced > 0 { try emit(Data(dst[0..<produced])) }
                        switch status {
                        case COMPRESSION_STATUS_END: finished = true
                        case COMPRESSION_STATUS_OK: break
                        default: throw IPAError.corruptEntry(entry.name)
                        }
                        // After the last input the decoder must be called until it reports END.
                        idle = (produced == 0 && stream.pendingInput == before) ? idle + 1 : 0
                        if idle > 2 { throw IPAError.corruptEntry(entry.name) }
                    } while !finished && (stream.pendingInput > 0 || stream.pendingOutput == 0 || final)
                }
                if final && !finished { throw IPAError.corruptEntry(entry.name) }
            }
        }
        guard written == entry.uncompressedSize, CRC32.finish(crc) == entry.crc32 else {
            throw IPAError.corruptEntry(entry.name)
        }
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
        guard cdSize <= maxCentralDirectoryBytes, cdOffset + cdSize <= fileSize else { throw IPAError.notAZip }

        let cd = try read(cdOffset, cdSize)
        var entries: [ZipEntry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, cd.u32(p) == 0x02014b50 else { throw IPAError.notAZip }
            let flags = cd.u16(p + 8)
            let nameLen = Int(cd.u16(p + 28))
            let extraLen = Int(cd.u16(p + 30))
            let commentLen = Int(cd.u16(p + 32))
            guard p + 46 + nameLen <= cd.count else { throw IPAError.notAZip }
            let nameBytes = cd.subdata(in: (p + 46)..<(p + 46 + nameLen))
            guard let name = String(bytes: nameBytes, encoding: .utf8) else {
                throw IPAError.unsafePath(String(decoding: nameBytes, as: UTF8.self))
            }

            if flags & 1 != 0 { throw IPAError.unsupportedZip("encrypted entry") }
            let comp = cd.u32(p + 20), uncomp = cd.u32(p + 24), local = cd.u32(p + 42)
            if comp == 0xFFFF_FFFF || uncomp == 0xFFFF_FFFF || local == 0xFFFF_FFFF {
                throw IPAError.unsupportedZip("zip64")
            }
            entries.append(ZipEntry(name: name, method: cd.u16(p + 10), crc32: cd.u32(p + 16),
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
            guard localName == Data(e.name.utf8), header.u16(8) == e.method, flags & 1 == 0 else {
                throw IPAError.corruptEntry(e.name)
            }
            // Bit 3: sizes/CRC live in a trailing data descriptor, local fields are zero.
            if flags & 8 == 0 {
                guard header.u32(14) == e.crc32, Int(header.u32(18)) == e.compressedSize,
                      Int(header.u32(22)) == e.uncompressedSize else { throw IPAError.corruptEntry(e.name) }
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

    private static func inflate(_ raw: Data, expected: Int, name: String) throws -> Data {
        if expected == 0 { return Data() }
        // One spare byte: a stream longer than declared must fail, not be silently truncated.
        var dst = [UInt8](repeating: 0, count: expected + 1)
        let n = raw.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&dst, expected + 1, base, raw.count, nil, COMPRESSION_ZLIB)
        }
        guard n == expected else { throw IPAError.corruptEntry(name) }
        return Data(dst[0..<expected])
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
