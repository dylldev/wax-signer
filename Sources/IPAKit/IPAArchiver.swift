import Compression
import CryptoKit
import Foundation

/// Writes and validates a staged classic ZIP, then atomically promotes it. ZIP64 sentinels are refused.
public enum IPAArchiver {
    /// Original compressed bytes are reused only after SHA-256 content identity has been established.
    /// An extraction inventory avoids reading/decompressing the original entries a second time.
    /// `verifiedManifest` must be captured before verifying the bundle; packaging must preserve that snapshot.
    /// `validateArchive` runs on the private candidate before the mandatory final integrity gate.
    public static func archive(directory: URL, to output: URL, rootFolder: String = "Payload", reusing original: URL? = nil,
                               compressChangedFiles: Bool = true, progress: ((Int, Int) -> Void)? = nil,
                               byteProgress: ((Double) -> Void)? = nil, reusingExtraction inventory: IPAExtractionInventory? = nil,
                               verifiedManifest: IPAArchiveManifest? = nil, validateArchive: ((URL) throws -> Void)? = nil) throws {
        let fm = FileManager.default
        let manifest = try verifiedManifest ?? IPAArchiveManifest.capture(directory: directory, rootFolder: rootFolder)
        guard manifest.directory == directory.standardizedFileURL.resolvingSymlinksInPath(), manifest.rootFolder == rootFolder else {
            throw IPAError.integrity("snapshot belongs to a different working tree")
        }
        let items = manifest.records.values.sorted { $0.name < $1.name }
        try ClassicZIP.entryCount(items.count)
        let source: ZipArchive?
        if let inventory {
            guard inventory.directory == manifest.directory,
                  original == nil || original!.standardizedFileURL == inventory.session.url else {
                throw IPAError.integrity("extraction inventory belongs to a different source or working tree")
            }
            source = inventory.session.zip
        } else {
            source = try original.map { try ZipArchive(url: $0) }
        }
        let reusable = Dictionary(uniqueKeysWithValues: (source?.entries ?? []).filter { !$0.isDirectory && !$0.isSymlink }.map { ($0.name, $0) })
        var reuse: [String: (ZipEntry, ZipFingerprint)] = [:]
        var centralBytes = 0
        for item in items {
            centralBytes += 46 + (try ClassicZIP.name(item.name)).count
            if let expected = item.fingerprint, let old = reusable[item.name], old.uncompressedSize == expected.size, let source {
                let fingerprint = try source.fingerprint(old)
                if fingerprint.file == expected { reuse[item.name] = (old, fingerprint) }
            }
        }
        guard centralBytes <= ZipArchive.maxCentralDirectoryBytes else { throw IPAError.unsupportedZip("central directory is too large") }
        let outputPath = output.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = manifest.directory.appendingPathComponent(rootFolder).path
        guard outputPath != rootPath, !outputPath.hasPrefix(rootPath + "/") else { throw IPAError.integrity("output is inside the archived tree") }

        // Only changed large files need parallel compression. SHA-256 is computed during the same reads.
        let work = fm.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let bigList = items.filter { ($0.fingerprint?.size ?? 0) >= 2 * 1024 * 1024 && reuse[$0.name] == nil }
        var prepared = [Precompressed?](repeating: nil, count: bigList.count)
        var failure: Error?
        let lock = NSLock()
        if compressChangedFiles {
            DispatchQueue.concurrentPerform(iterations: bigList.count) { i in
                do {
                    let item = bigList[i]
                    let p = try precompress(manifest.directory.appendingPathComponent(item.name), in: work)
                    guard p.fingerprint == item.fingerprint else { throw IPAError.integrity("file changed during compression: \(item.name)") }
                    lock.lock(); prepared[i] = p; lock.unlock()
                } catch { lock.lock(); failure = failure ?? error; lock.unlock() }
            }
        }
        if let failure { throw failure }
        var precompressed: [String: Precompressed] = [:]
        for (i, entry) in bigList.enumerated() { if let p = prepared[i] { precompressed[entry.name] = p } }

        let parent = output.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".wax-archive-\(UUID().uuidString).part")
        guard fm.createFile(atPath: staged.path, contents: nil) else { throw IPAError.unreadable("creating staged archive") }
        defer { try? fm.removeItem(at: staged) }
        let out = try FileHandle(forWritingTo: staged)
        var closed = false
        defer { if !closed { try? out.close() } }
        var offset = 0
        func write(_ d: Data) throws {
            guard d.count <= ClassicZIP.maxBytes - offset else { throw IPAError.unsupportedZip("archive exceeds classic ZIP limits") }
            try out.write(contentsOf: d); offset += d.count
        }
        var central: [CentralRecord] = []
        var doneBytes = 0
        let totalBytes = max(1, items.reduce(0) { $0 + ($1.fingerprint?.size ?? 0) })
        for (index, item) in items.enumerated() {
            let url = manifest.directory.appendingPathComponent(item.name)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let (time, date) = dos((attrs[.modificationDate] as? Date) ?? Date())
            let start = try ClassicZIP.size(offset)
            let record: CentralRecord
            switch item.kind {
            case .directory:
                record = try writeStored(item.name, Data(), mode: item.mode, time: time, date: date, offset: start, write: write, directory: true)
            case .symlink:
                record = try writeStored(item.name, Data(item.target!.utf8), mode: item.mode, time: time, date: date, offset: start, write: write)
            case .file:
                let expected = item.fingerprint!
                if let (old, fingerprint) = reuse[item.name], let source {
                    record = try reuseRecord(item.name, old, fingerprint, source, mode: item.mode, time: time, date: date, offset: start, write: write)
                } else if let p = precompressed[item.name] {
                    record = try writePrecompressed(item.name, p, mode: item.mode, time: time, date: date, offset: start, write: write)
                } else if !compressChangedFiles && expected.size >= 2 * 1024 * 1024 {
                    record = try writeStoredFile(item.name, url, expected: expected, mode: item.mode, time: time, date: date, offset: start, write: write)
                } else {
                    record = try writeFile(item.name, url, expected: expected, mode: item.mode, time: time, date: date, offset: start, write: write)
                }
                doneBytes += expected.size
            }
            central.append(record)
            progress?(index + 1, items.count)
            byteProgress?(min(1, Double(doneBytes) / Double(totalBytes)))
        }
        let cdStart = offset
        for c in central {
            let name = try ClassicZIP.name(c.name)
            var h = Data()
            h.le32(0x02014b50); h.le16(0x031E); h.le16(20); h.le16(c.flags); h.le16(c.method)
            h.le16(c.time); h.le16(c.date); h.le32(c.crc); h.le32(c.comp); h.le32(c.uncomp)
            h.le16(UInt16(name.count)); h.le16(0); h.le16(0); h.le16(0); h.le16(0)
            h.le32(c.external); h.le32(c.offset); h.append(name)
            try write(h)
        }
        var e = Data()
        e.le32(0x06054b50); e.le16(0); e.le16(0); e.le16(UInt16(central.count)); e.le16(UInt16(central.count))
        e.le32(try ClassicZIP.size(offset - cdStart)); e.le32(try ClassicZIP.size(cdStart)); e.le16(0)
        try write(e)
        try out.close(); closed = true
        try validateArchive?(staged)
        try manifest.verify(archive: staged)
        try manifest.verifyTree()
        try ArchivePromotion.promote(staged, to: output)
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
        let nameData = try ClassicZIP.name(name)
        try write(localHeader(name: nameData, flags: 0x0800, method: 0, time: time, date: date,
                              crc: crc, comp: UInt32(data.count), uncomp: UInt32(data.count)))
        try write(data)
        return CentralRecord(name: name, flags: 0x0800, method: 0, time: time, date: date, crc: crc,
                             comp: UInt32(data.count), uncomp: UInt32(data.count), offset: offset,
                             external: mode << 16 | (directory ? 0x10 : 0))
    }

    private static func reuseRecord(_ name: String, _ old: ZipEntry, _ fingerprint: ZipFingerprint, _ source: ZipArchive,
                                    mode: UInt32, time: UInt16, date: UInt16, offset: UInt32,
                                    write: (Data) throws -> Void) throws -> CentralRecord {
        let comp = try ClassicZIP.size(old.compressedSize), uncomp = try ClassicZIP.size(old.uncompressedSize)
        try write(localHeader(name: try ClassicZIP.name(name), flags: 0x0800, method: old.method, time: time, date: date,
                              crc: old.crc32, comp: comp, uncomp: uncomp))
        try source.copyRaw(old, expecting: fingerprint, to: write)
        return CentralRecord(name: name, flags: 0x0800, method: old.method, time: time, date: date, crc: old.crc32,
                             comp: comp, uncomp: uncomp, offset: offset, external: mode << 16)
    }

    private static func writeStoredFile(_ name: String, _ url: URL, expected: FileFingerprint, mode: UInt32, time: UInt16, date: UInt16,
                                        offset: UInt32, write: (Data) throws -> Void) throws -> CentralRecord {
        let size = try ClassicZIP.size(expected.size)
        try write(localHeader(name: try ClassicZIP.name(name), flags: 0x0800, method: 0, time: time, date: date,
                              crc: expected.crc32, comp: size, uncomp: size))
        let input = try FileHandle(forReadingFrom: url)
        var closed = false
        defer { if !closed { try? input.close() } }
        let actual = try FileFingerprint.read(expectedSize: expected.size) { count in
            let data = try input.read(upToCount: count)
            if let data { try write(data) }
            return data
        }
        guard actual == expected else { throw IPAError.integrity("file changed during packing: \(name)") }
        try input.close(); closed = true
        return CentralRecord(name: name, flags: 0x0800, method: 0, time: time, date: date, crc: expected.crc32,
                             comp: size, uncomp: size, offset: offset, external: mode << 16)
    }

    private static func writeFile(_ name: String, _ url: URL, expected: FileFingerprint, mode: UInt32, time: UInt16, date: UInt16, offset: UInt32,
                                  write: (Data) throws -> Void) throws -> CentralRecord {
        let nameData = try ClassicZIP.name(name)
        // Sizes and CRC follow the data in a data descriptor (flag bit 3), so the file is read exactly once.
        try write(localHeader(name: nameData, flags: 0x0808, method: 8, time: time, date: date, crc: 0, comp: 0, uncomp: 0))
        let r = try deflate(url, emit: write)
        guard r.fingerprint == expected else { throw IPAError.integrity("file changed during packing: \(name)") }
        var dd = Data()
        dd.le32(0x08074b50); dd.le32(r.crc); dd.le32(UInt32(r.comp)); dd.le32(UInt32(r.uncomp))
        try write(dd)
        return CentralRecord(name: name, flags: 0x0808, method: 8, time: time, date: date, crc: r.crc,
                             comp: UInt32(r.comp), uncomp: UInt32(r.uncomp), offset: offset, external: mode << 16)
    }

    /// A file already compressed (on another thread) into a temporary file.
    struct Precompressed { let temp: URL; let crc: UInt32; let comp: Int; let uncomp: Int; let fingerprint: FileFingerprint }

    private static func writePrecompressed(_ name: String, _ p: Precompressed, mode: UInt32, time: UInt16, date: UInt16,
                                           offset: UInt32, write: (Data) throws -> Void) throws -> CentralRecord {
        _ = try ClassicZIP.size(p.comp); _ = try ClassicZIP.size(p.uncomp)
        try write(localHeader(name: try ClassicZIP.name(name), flags: 0x0800, method: 8, time: time, date: date,
                              crc: p.crc, comp: UInt32(p.comp), uncomp: UInt32(p.uncomp)))
        let input = try FileHandle(forReadingFrom: p.temp)
        defer { try? input.close(); try? FileManager.default.removeItem(at: p.temp) }
        var copied = 0
        while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
            guard chunk.count <= p.comp - copied else { throw IPAError.integrity("precompressed file grew") }
            try write(chunk); copied += chunk.count
        }
        guard copied == p.comp else { throw IPAError.integrity("precompressed file was truncated") }
        try input.close()
        return CentralRecord(name: name, flags: 0x0800, method: 8, time: time, date: date, crc: p.crc,
                             comp: UInt32(p.comp), uncomp: UInt32(p.uncomp), offset: offset, external: mode << 16)
    }

    /// Compresses a file into a temporary file. Safe to call from several threads at once.
    static func precompress(_ url: URL, in tempDirectory: URL) throws -> Precompressed {
        let temp = tempDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw IPAError.unreadable("creating compression scratch file") }
        let out = try FileHandle(forWritingTo: temp)
        var complete = false
        defer { if !complete { try? out.close(); try? FileManager.default.removeItem(at: temp) } }
        let r = try deflate(url, emit: { try out.write(contentsOf: $0) })
        try out.close(); complete = true
        return Precompressed(temp: temp, crc: r.crc, comp: r.comp, uncomp: r.uncomp, fingerprint: r.fingerprint)
    }

    /// Raw deflate of a whole file, streamed in chunks. Returns the CRC32 and both sizes.
    private static func deflate(_ url: URL, emit write: (Data) throws -> Void) throws -> (crc: UInt32, comp: Int, uncomp: Int, fingerprint: FileFingerprint) {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        guard let stream = CompressionStream(COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) else {
            throw IPAError.unreadable("compression could not start")
        }

        var crc = CRC32.begin(), hash = SHA256()
        var uncompressed = 0, compressed = 0
        let chunk = 256 * 1024
        var dst = [UInt8](repeating: 0, count: chunk)
        var finished = false
        var inputDone = false
        while !finished {
            let src = inputDone ? Data() : (try input.read(upToCount: chunk) ?? Data())
            if src.isEmpty { inputDone = true }
            crc = CRC32.update(crc, src); hash.update(data: src)
            guard src.count <= ClassicZIP.maxBytes - uncompressed else { throw IPAError.unsupportedZip("file exceeds classic ZIP limits") }
            uncompressed += src.count
            try src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                var idle = 0
                repeat {
                    let before = stream.pendingInput
                    let status = dst.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: inputDone) }
                    let produced = chunk - stream.pendingOutput
                    if produced > 0 {
                        guard produced <= ClassicZIP.maxBytes - compressed else { throw IPAError.unsupportedZip("compressed file exceeds classic ZIP limits") }
                        try write(Data(dst[0..<produced])); compressed += produced
                    }
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
        try input.close()
        let fingerprint = FileFingerprint(sha256: Data(hash.finalize()), crc32: CRC32.finish(crc), size: uncompressed)
        return (fingerprint.crc32, compressed, uncompressed, fingerprint)
    }

    private static func dos(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        // Split into small typed steps: the CI toolchain cannot type-check the one-line version in reasonable time.
        let year: Int = min(2107, max(1980, c.year ?? 1980))
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
