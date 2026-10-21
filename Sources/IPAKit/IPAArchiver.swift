import Compression
import Foundation

/// Writes a directory tree as an IPA (zip). Streams file data (deflate) with data descriptors, records Unix
/// permissions and symlinks. Classic zip only: no zip64, so more than 65,535 entries or 4 GiB is refused.
public enum IPAArchiver {
    /// - Parameter reusing: the archive these files came from. A file whose size and CRC32 still match its entry
    ///   there is copied across in its original compressed form instead of being compressed again, which is most of
    ///   the work for a signed app. Anything missing, changed or unreadable is compressed as usual.
    /// - Parameter compressChangedFiles: `false` writes big changed files as stored (uncompressed) entries. That is much
    ///   faster and fine when the archive only travels inside the phone to be installed; keep `true` for exports.
    /// - Parameter byteProgress: fraction (0...1) of the uncompressed bytes handled so far.
    public static func archive(directory: URL, to output: URL, rootFolder: String = "Payload", reusing original: URL? = nil,
                               compressChangedFiles: Bool = true, progress: ((Int, Int) -> Void)? = nil, byteProgress: ((Double) -> Void)? = nil) throws {
        let fm = FileManager.default
        let source = original.flatMap { try? ZipArchive(url: $0) }
        let reusable = Dictionary(uniqueKeysWithValues: (source?.entries ?? []).filter { !$0.isDirectory && !$0.isSymlink }.map { ($0.name, $0) })
        let base = directory.appendingPathComponent(rootFolder)
        guard (try? base.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw IPAError.noApp }

        // Deterministic order: the root folder, then everything beneath it sorted by path.
        var items: [(rel: String, url: URL)] = [("\(rootFolder)/", base)]
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: []) else { throw IPAError.noApp }
        let baseResolved = base.resolvingSymlinksInPath().path
        var found: [(String, URL)] = []
        for case let url as URL in walker {
            // Resolve only the parent so a symlink entry keeps its own name.
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            guard full.hasPrefix(baseResolved + "/") else { continue }
            found.append((rootFolder + "/" + String(full.dropFirst(baseResolved.count + 1)), url))
        }
        found.sort { $0.0 < $1.0 }
        items += found.map { ($0.0, $0.1) }
        guard items.count <= 65_535 else { throw IPAError.unsupportedZip("zip64 would be required (too many entries)") }

        // Big files dominate the time. Decide for each whether the original bytes can be reused, and compress the
        // ones that changed on several threads at once; the archive itself is still written in order below.
        let bigThreshold = 2 * 1024 * 1024
        let work = fm.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        var big: [String: URL] = [:]
        for item in items {
            guard let v = try? item.url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
                  v.isRegularFile == true, v.isSymbolicLink != true, (v.fileSize ?? 0) >= bigThreshold else { continue }
            big[item.rel] = item.url
        }
        let bigList = Array(big)
        var prepared = [Precompressed?](repeating: nil, count: bigList.count)
        var storedBig: [String: (crc: UInt32, size: Int)] = [:]     // changed big files that will be stored, with their CRC
        var verifiedReuse: [String: Date] = [:]     // big files whose CRC already matched the original, with their mtime then: not read a second time below
        var failure: Error?
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: bigList.count) { i in
            let (rel, url) = bigList[i]
            if let old = reusable[rel], let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size == old.uncompressedSize,
               fileCRC(url) == old.crc32 {                               // unchanged: reused in the loop below
                let stamp = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast
                lock.lock(); verifiedReuse[rel] = stamp; lock.unlock()
                return
            }
            if !compressChangedFiles {
                if let crc = fileCRC(url), let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size <= Int(UInt32.max) {
                    lock.lock(); storedBig[rel] = (crc, size); lock.unlock()
                    return
                }                                                           // unreadable: fall through to the normal path, which reports it
            }
            do {
                let p = try precompress(url, in: work)
                lock.lock(); prepared[i] = p; lock.unlock()
            } catch { lock.lock(); failure = failure ?? error; lock.unlock() }
        }
        if let failure { throw failure }
        var precompressed: [String: Precompressed] = [:]
        for (i, entry) in bigList.enumerated() { if let p = prepared[i] { precompressed[entry.0] = p } }

        fm.createFile(atPath: output.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        var closed = false
        defer { if !closed { try? out.close() } }

        var offset = 0
        func write(_ d: Data) throws { try out.write(contentsOf: d); offset += d.count }

        var central: [CentralRecord] = []
        var doneBytes = 0
        let totalBytes = max(1, items.reduce(0) { $0 + (((try? fm.attributesOfItem(atPath: $1.url.path))?[.size] as? Int) ?? 0) })

        for (index, item) in items.enumerated() {
            let values = try item.url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey])
            let attrs = try fm.attributesOfItem(atPath: item.url.path)
            let perm = (attrs[.posixPermissions] as? Int) ?? 0o644
            let (dosTime, dosDate) = dos(values.contentModificationDate ?? Date())
            guard offset <= Int(UInt32.max) - 1 else { throw IPAError.unsupportedZip("zip64 would be required (archive over 4 GiB)") }
            let startOffset = UInt32(offset)
            var rel = item.rel

            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: item.url.path)
                let data = Data(target.utf8)
                central.append(try writeStored(rel, data, mode: 0o120777, time: dosTime, date: dosDate,
                                               offset: startOffset, write: write))
            } else if values.isDirectory == true {
                if !rel.hasSuffix("/") { rel += "/" }
                central.append(try writeStored(rel, Data(), mode: 0o040000 | UInt32(perm & 0o777), time: dosTime, date: dosDate,
                                               offset: startOffset, write: write, directory: true))
            } else {
                if let stored = storedBig[rel] {
                    central.append(try writeStoredFile(rel, item.url, crc: stored.crc, size: stored.size, mode: 0o100000 | UInt32(perm & 0o777),
                                                       time: dosTime, date: dosDate, offset: startOffset, write: write))
                } else if let p = precompressed[rel] {
                    central.append(try writePrecompressed(rel, p, mode: 0o100000 | UInt32(perm & 0o777), time: dosTime, date: dosDate,
                                                          offset: startOffset, write: write))
                } else if let source, let old = reusable[rel], let record = try reuseRecord(rel, item.url, old, source, mode: 0o100000 | UInt32(perm & 0o777),
                                                                                    time: dosTime, date: dosDate, offset: startOffset,
                                                                                    verifiedAt: verifiedReuse[rel], write: write) {
                    central.append(record)
                } else {
                    central.append(try writeFile(rel, item.url, mode: 0o100000 | UInt32(perm & 0o777), time: dosTime, date: dosDate,
                                                 offset: startOffset, write: write))
                }
                doneBytes += (attrs[.size] as? Int) ?? 0
            }
            progress?(index + 1, items.count)
            byteProgress?(min(1, Double(doneBytes) / Double(totalBytes)))
        }

        let cdStart = offset
        for c in central {
            let name = Data(c.name.utf8)
            var h = Data()
            h.le32(0x02014b50); h.le16(0x031E); h.le16(20); h.le16(c.flags); h.le16(c.method)
            h.le16(c.time); h.le16(c.date); h.le32(c.crc); h.le32(c.comp); h.le32(c.uncomp)
            h.le16(UInt16(name.count)); h.le16(0); h.le16(0); h.le16(0); h.le16(0)
            h.le32(c.external); h.le32(c.offset); h.append(name)
            try write(h)
        }
        let cdSize = offset - cdStart
        guard cdStart <= Int(UInt32.max), cdSize <= Int(UInt32.max) else {
            throw IPAError.unsupportedZip("zip64 would be required")
        }
        var e = Data()
        e.le32(0x06054b50); e.le16(0); e.le16(0); e.le16(UInt16(central.count)); e.le16(UInt16(central.count))
        e.le32(UInt32(cdSize)); e.le32(UInt32(cdStart)); e.le16(0)
        try write(e)
        try out.close(); closed = true
    }

    // MARK: entries

    private static func localHeader(name: Data, flags: UInt16, method: UInt16, time: UInt16, date: UInt16,
                                    crc: UInt32, comp: UInt32, uncomp: UInt32) -> Data {
        var h = Data()
        h.le32(0x04034b50); h.le16(20); h.le16(flags); h.le16(method); h.le16(time); h.le16(date)
        h.le32(crc); h.le32(comp); h.le32(uncomp); h.le16(UInt16(name.count)); h.le16(0)
        h.append(name)
        return h
    }

    private static func writeStored(_ name: String, _ data: Data, mode: UInt32, time: UInt16, date: UInt16, offset: UInt32,
                                    write: (Data) throws -> Void, directory: Bool = false) throws -> CentralRecord {
        let crc = CRC32.checksum(data)
        let nameData = Data(name.utf8)
        try write(localHeader(name: nameData, flags: 0x0800, method: 0, time: time, date: date,
                              crc: crc, comp: UInt32(data.count), uncomp: UInt32(data.count)))
        try write(data)
        return CentralRecord(name: name, flags: 0x0800, method: 0, time: time, date: date, crc: crc,
                             comp: UInt32(data.count), uncomp: UInt32(data.count), offset: offset,
                             external: mode << 16 | (directory ? 0x10 : 0))
    }

    private static func fileCRC(_ url: URL) -> UInt32? {
        guard let input = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? input.close() }
        var crc = CRC32.begin()
        while let chunk = try? input.read(upToCount: 1 << 20), !chunk.isEmpty { crc = CRC32.update(crc, chunk) }
        return CRC32.finish(crc)
    }

    /// Copies an unchanged file's original compressed bytes. Returns nil (nothing written) when the file differs.
    private static func reuseRecord(_ name: String, _ url: URL, _ old: ZipEntry, _ source: ZipArchive, mode: UInt32,
                                    time: UInt16, date: UInt16, offset: UInt32, verifiedAt: Date? = nil,
                                    write: (Data) throws -> Void) throws -> CentralRecord? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size == old.uncompressedSize,
              old.compressedSize <= Int(UInt32.max) else { return nil }
        // `verifiedAt` means the caller already compared this file's CRC with the original's, when its mtime was that.
        // If the file was touched since, it is read and checked again.
        let untouched = verifiedAt != nil && (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date == verifiedAt
        if !untouched {
            guard let input = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? input.close() }
            var crc = CRC32.begin()
            while let chunk = try? input.read(upToCount: 1 << 20), !chunk.isEmpty { crc = CRC32.update(crc, chunk) }
            guard CRC32.finish(crc) == old.crc32 else { return nil }
        }
        try write(localHeader(name: Data(name.utf8), flags: 0x0800, method: old.method, time: time, date: date,
                              crc: old.crc32, comp: UInt32(old.compressedSize), uncomp: UInt32(old.uncompressedSize)))
        try source.copyRaw(old, to: write)
        return CentralRecord(name: name, flags: 0x0800, method: old.method, time: time, date: date, crc: old.crc32,
                             comp: UInt32(old.compressedSize), uncomp: UInt32(old.uncompressedSize), offset: offset, external: mode << 16)
    }

    /// A file stored as it is (method 0). The CRC and size were computed beforehand, so no data descriptor is needed.
    private static func writeStoredFile(_ name: String, _ url: URL, crc: UInt32, size: Int, mode: UInt32, time: UInt16, date: UInt16,
                                        offset: UInt32, write: (Data) throws -> Void) throws -> CentralRecord {
        try write(localHeader(name: Data(name.utf8), flags: 0x0800, method: 0, time: time, date: date,
                              crc: crc, comp: UInt32(size), uncomp: UInt32(size)))
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var sent = 0
        var check = CRC32.begin()
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { check = CRC32.update(check, chunk); try write(chunk); sent += chunk.count }
        // The header already holds the CRC from the earlier pass: if the file changed since, the entry would be corrupt.
        guard sent == size, CRC32.finish(check) == crc else { throw IPAError.unreadable("\(name) changed while it was being packed") }
        return CentralRecord(name: name, flags: 0x0800, method: 0, time: time, date: date, crc: crc,
                             comp: UInt32(size), uncomp: UInt32(size), offset: offset, external: mode << 16)
    }

    private static func writeFile(_ name: String, _ url: URL, mode: UInt32, time: UInt16, date: UInt16, offset: UInt32,
                                  write: (Data) throws -> Void) throws -> CentralRecord {
        let nameData = Data(name.utf8)
        // Sizes and CRC follow the data in a data descriptor (flag bit 3), so the file is read exactly once.
        try write(localHeader(name: nameData, flags: 0x0808, method: 8, time: time, date: date, crc: 0, comp: 0, uncomp: 0))
        let r = try deflate(url, emit: write)
        var dd = Data()
        dd.le32(0x08074b50); dd.le32(r.crc); dd.le32(UInt32(r.comp)); dd.le32(UInt32(r.uncomp))
        try write(dd)
        return CentralRecord(name: name, flags: 0x0808, method: 8, time: time, date: date, crc: r.crc,
                             comp: UInt32(r.comp), uncomp: UInt32(r.uncomp), offset: offset, external: mode << 16)
    }

    /// A file already compressed (on another thread) into a temporary file.
    struct Precompressed { let temp: URL; let crc: UInt32; let comp: Int; let uncomp: Int }

    private static func writePrecompressed(_ name: String, _ p: Precompressed, mode: UInt32, time: UInt16, date: UInt16,
                                           offset: UInt32, write: (Data) throws -> Void) throws -> CentralRecord {
        guard p.comp <= Int(UInt32.max), p.uncomp <= Int(UInt32.max) else {
            throw IPAError.unsupportedZip("zip64 would be required (file over 4 GiB)")
        }
        try write(localHeader(name: Data(name.utf8), flags: 0x0800, method: 8, time: time, date: date,
                              crc: p.crc, comp: UInt32(p.comp), uncomp: UInt32(p.uncomp)))
        let input = try FileHandle(forReadingFrom: p.temp)
        defer { try? input.close(); try? FileManager.default.removeItem(at: p.temp) }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { try write(chunk) }
        return CentralRecord(name: name, flags: 0x0800, method: 8, time: time, date: date, crc: p.crc,
                             comp: UInt32(p.comp), uncomp: UInt32(p.uncomp), offset: offset, external: mode << 16)
    }

    /// Compresses a file into a temporary file. Safe to call from several threads at once.
    static func precompress(_ url: URL, in tempDirectory: URL) throws -> Precompressed {
        let temp = tempDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let out = try FileHandle(forWritingTo: temp)
        defer { try? out.close() }
        let r = try deflate(url, emit: { try out.write(contentsOf: $0) })
        return Precompressed(temp: temp, crc: r.crc, comp: r.comp, uncomp: r.uncomp)
    }

    /// Raw deflate of a whole file, streamed in chunks. Returns the CRC32 and both sizes.
    private static func deflate(_ url: URL, emit write: (Data) throws -> Void) throws -> (crc: UInt32, comp: Int, uncomp: Int) {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        guard let stream = CompressionStream(COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) else {
            throw IPAError.unreadable("compression could not start")
        }

        var crc = CRC32.begin()
        var uncompressed = 0, compressed = 0
        let chunk = 256 * 1024
        var dst = [UInt8](repeating: 0, count: chunk)
        var finished = false
        var inputDone = false
        while !finished {
            let src = inputDone ? Data() : (try input.read(upToCount: chunk) ?? Data())
            if src.isEmpty { inputDone = true }
            crc = CRC32.update(crc, src)
            uncompressed += src.count
            guard uncompressed <= Int(UInt32.max) else { throw IPAError.unsupportedZip("zip64 would be required (file over 4 GiB)") }
            try src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                var idle = 0
                repeat {
                    let before = stream.pendingInput
                    let status = dst.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: inputDone) }
                    let produced = chunk - stream.pendingOutput
                    if produced > 0 { try write(Data(dst[0..<produced])); compressed += produced }
                    switch status {
                    case COMPRESSION_STATUS_END: finished = true
                    case COMPRESSION_STATUS_OK: break
                    default: throw IPAError.unreadable("compression failed")
                    }
                    idle = (produced == 0 && stream.pendingInput == before) ? idle + 1 : 0
                    if idle > 2 { throw IPAError.unreadable("compression stalled") }
                } while !finished && (stream.pendingInput > 0 || stream.pendingOutput == 0 || inputDone)
            }
        }
        return (CRC32.finish(crc), compressed, uncompressed)
    }

    private static func dos(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        // Split into small typed steps: the CI toolchain cannot type-check the one-line version in reasonable time.
        let year: Int = max(1980, c.year ?? 1980)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let month: Int = c.month ?? 1, dayOfMonth: Int = c.day ?? 1
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let day = UInt16(((year - 1980) << 9) | (month << 5) | dayOfMonth)
        return (time, day)
    }
}

private struct CentralRecord {
    var name: String; var flags: UInt16; var method: UInt16; var time: UInt16; var date: UInt16
    var crc: UInt32; var comp: UInt32; var uncomp: UInt32; var offset: UInt32; var external: UInt32
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8)]) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xff)) } }
}
