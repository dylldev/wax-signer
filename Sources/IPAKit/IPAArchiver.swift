import Compression
import zlib
import CryptoKit
import Foundation

/// Writes and validates a staged classic ZIP, then atomically promotes it. ZIP64 sentinels are refused.
public enum IPAArchiver {
    public struct Limits: Sendable {
        public var maximumConcurrentFiles: Int = 4
        /// Cumulative bytes written to compression scratch and the staged ZIP, not peak live storage.
        public var maximumTemporaryBytes: Int = 8 * 1024 * 1024 * 1024
        public var minimumFreeBytes: Int64 = 16 * 1024 * 1024
        public var deadline: TimeInterval = 1800
        public init() {}
    }
    public enum BudgetError: Error, Equatable, LocalizedError {
        case invalidLimits
        case deadline
        case temporaryBytes(limit: Int)
        case diskSpace(required: Int64, available: Int64)
        public var errorDescription: String? {
            switch self {
            case .invalidLimits: "The packaging resource limits are invalid."
            case .deadline: "Packing exceeded its total time limit. Retry with a smaller IPA or a longer configured limit."
            case .temporaryBytes(let limit): "Packing exceeded its \(limit) byte temporary-write budget. Retry with a larger configured limit."
            case .diskSpace(let required, let available): "Packing needs at least \(required) free bytes; only \(available) are available. Free storage and retry."
            }
        }
    }

    /// Original compressed bytes are reused only after SHA-256 content identity has been established.
    /// An extraction inventory avoids reading/decompressing the original entries a second time.
    /// `compressChangedFiles: false` stores changed files of at least 2 MiB without compression.
    /// `verifiedManifest` must be captured before verifying the bundle; packaging must preserve that snapshot.
    /// `finalTreeCheck: false` removes the built-in "tree unchanged since the manifest" proof. Only pass it if the caller proves
    /// that itself before the output is promoted (IPASigner does, concurrently, and waits for it in `validateArchive`).
    /// `validateArchive` runs on the private candidate before the mandatory final integrity gate.
    public static func archive(directory: URL, to output: URL, rootFolder: String = "Payload", reusing original: URL? = nil,
                               compressChangedFiles: Bool = true, fastDeflate: Bool = false, finalTreeCheck: Bool = true,
                               progress: ((Int, Int) -> Void)? = nil,
                               byteProgress: ((Double) -> Void)? = nil, reusingExtraction inventory: IPAExtractionInventory? = nil,
                               verifiedManifest: IPAArchiveManifest? = nil, validateArchive: ((URL) throws -> Void)? = nil,
                               limits: Limits = Limits(),
                               checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) throws {
        try archive(directory: directory, to: output, rootFolder: rootFolder, reusing: original, compressChangedFiles: compressChangedFiles,
                    fastDeflate: fastDeflate, finalTreeCheck: finalTreeCheck, progress: progress, byteProgress: byteProgress, reusingExtraction: inventory, verifiedManifest: verifiedManifest,
                    validateArchive: validateArchive, limits: limits, checkCancellation: checkCancellation, environment: .live)
    }

    static func archive(directory: URL, to output: URL, rootFolder: String = "Payload", reusing original: URL? = nil,
                        compressChangedFiles: Bool = true, fastDeflate: Bool = false, finalTreeCheck: Bool = true,
                        progress: ((Int, Int) -> Void)? = nil,
                        byteProgress: ((Double) -> Void)? = nil, reusingExtraction inventory: IPAExtractionInventory? = nil,
                        verifiedManifest: IPAArchiveManifest? = nil, validateArchive: ((URL) throws -> Void)? = nil,
                        limits: Limits = Limits(),
                        checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() },
                        environment: ArchivingEnvironment) throws {
        let parent = output.deletingLastPathComponent()
        let budget = try ArchivingBudget(limits: limits, directory: parent, environment: environment, cancellation: checkCancellation)
        try budget.check(probeDisk: true)
        let fm = FileManager.default
        let manifest = try verifiedManifest ?? IPAArchiveManifest.capture(directory: directory, rootFolder: rootFolder, checkpoint: { try budget.check() })
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
            try budget.check()
            centralBytes += 46 + (try ClassicZIP.name(item.name)).count
            if let expected = item.fingerprint, let old = reusable[item.name], old.uncompressedSize == expected.size, let source {
                let fingerprint = try source.fingerprint(old, checkpoint: { try budget.check() })
                if fingerprint.file == expected { reuse[item.name] = (old, fingerprint) }
            }
        }
        guard centralBytes <= ZipArchive.maxCentralDirectoryBytes else { throw IPAError.unsupportedZip("central directory is too large") }
        let outputPath = output.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = manifest.directory.appendingPathComponent(rootFolder).resolvingSymlinksInPath().path
        guard outputPath != rootPath, !outputPath.hasPrefix(rootPath + "/") else { throw IPAError.integrity("output is inside the archived tree") }

        // Only changed large files need parallel compression. SHA-256 is computed during the same reads.
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try budget.check(probeDisk: true)
        let work = try createScratch(in: parent)
        defer { try? fm.removeItem(at: work) }
        let bigList = items.filter { ($0.fingerprint?.size ?? 0) >= 2 * 1024 * 1024 && reuse[$0.name] == nil }
        var prepared = [Precompressed?](repeating: nil, count: bigList.count)
        var failure: Error?
        let lock = NSLock()
        if compressChangedFiles {
            let order = bigList.indices.sorted { bigList[$0].fingerprint!.size > bigList[$1].fingerprint!.size }
            var next = 0
            DispatchQueue.concurrentPerform(iterations: min(limits.maximumConcurrentFiles, bigList.count)) { _ in
                while true {
                    let index: Int? = lock.withLock {
                        guard failure == nil, next < order.count else { return nil }
                        defer { next += 1 }
                        return order[next]
                    }
                    guard let i = index else { return }
                    do {
                        try budget.check(probeDisk: true)
                        let item = bigList[i]
                        let p = try precompress(manifest.directory.appendingPathComponent(item.name), in: work, budget: budget,
                                                level: fastDeflate ? Z_BEST_SPEED : Z_DEFAULT_COMPRESSION)
                        guard p.fingerprint == item.fingerprint else { throw IPAError.integrity("file changed during compression: \(item.name)") }
                        lock.withLock { prepared[i] = p }
                    } catch { lock.withLock { failure = failure ?? error }; return }
                }
            }
        }
        if let failure { throw failure }
        var precompressed: [String: Precompressed] = [:]
        for (i, entry) in bigList.enumerated() { if let p = prepared[i] { precompressed[entry.name] = p } }

        try budget.check(probeDisk: true)
        let staged = parent.appendingPathComponent(".wax-archive-\(UUID().uuidString).part")
        let out = try createTemporaryFile(at: staged)
        defer { try? fm.removeItem(at: staged) }
        var closed = false
        defer { if !closed { try? out.close() } }
        var offset = 0
        func write(_ d: Data) throws {
            guard d.count <= ClassicZIP.maxBytes - offset else { throw IPAError.unsupportedZip("archive exceeds classic ZIP limits") }
            try budget.beforeWrite(d.count)
            try out.write(contentsOf: d); offset += d.count
        }
        var central: [CentralRecord] = []
        var doneBytes = 0
        let totalBytes = max(1, items.reduce(0) { $0 + ($1.fingerprint?.size ?? 0) })
        for (index, item) in items.enumerated() {
            try budget.check(probeDisk: true)
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
                    record = try writeFile(item.name, url, expected: expected, mode: item.mode, time: time, date: date, offset: start,
                                           checkpoint: { try budget.check() }, write: write)
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
        // Resource/cancellation checks end before the owner's publication barrier. R2 verification remains mandatory.
        try budget.check(probeDisk: true)
        try validateArchive?(staged)
        try manifest.verify(archive: staged)
        if finalTreeCheck { try manifest.verifyTree() }
        try ArchivePromotion.promote(staged, to: output)
    }

    /// Exclusive creation establishes ownership before any cleanup is registered; never truncate an existing path.
    static func createTemporaryFile(at url: URL) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw IPAError.unreadable("creating packaging temporary file: \(String(cString: strerror(errno)))") }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func createScratch(in parent: URL) throws -> URL {
        var template = Array(parent.appendingPathComponent(".wax-archive-work-XXXXXX").path.utf8CString)
        return try template.withUnsafeMutableBufferPointer { buffer in
            guard let path = mkdtemp(buffer.baseAddress!) else {
                throw IPAError.unreadable("creating packaging scratch directory: \(String(cString: strerror(errno)))")
            }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
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
                                  checkpoint: (() throws -> Void)? = nil, write: (Data) throws -> Void) throws -> CentralRecord {
        let nameData = try ClassicZIP.name(name)
        // Sizes and CRC follow the data in a data descriptor (flag bit 3), so the file is read exactly once.
        try write(localHeader(name: nameData, flags: 0x0808, method: 8, time: time, date: date, crc: 0, comp: 0, uncomp: 0))
        let r = try deflate(url, checkpoint: checkpoint, emit: write)
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

    /// Files at least this big are deflated as independent blocks on several cores (one huge changed executable is
    /// otherwise a single-threaded job that dominates packing). Internal so tests can lower it.
    static var parallelDeflateMinimum = 16 * 1024 * 1024

    /// Compresses a file into a temporary file. Safe to call from several threads at once.
    static func precompress(_ url: URL, in tempDirectory: URL, budget: ArchivingBudget? = nil,
                            level: Int32 = Z_DEFAULT_COMPRESSION) throws -> Precompressed {
        let temp = tempDirectory.appendingPathComponent(UUID().uuidString)
        let out = try createTemporaryFile(at: temp)
        var complete = false
        defer { if !complete { try? out.close(); try? FileManager.default.removeItem(at: temp) } }
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
           size >= parallelDeflateMinimum || (level != Z_DEFAULT_COMPRESSION && size >= 2 * 1024 * 1024) {      // a chosen level needs the zlib path
            let r = try blockDeflate(url, size: size, into: out, in: tempDirectory, budget: budget, level: level)
            try out.close(); complete = true
            return Precompressed(temp: temp, crc: r.fingerprint.crc32, comp: r.comp, uncomp: size, fingerprint: r.fingerprint)
        }
        let r = try deflate(url, checkpoint: { try budget?.check() }, emit: {
            try budget?.beforeWrite($0.count)
            try out.write(contentsOf: $0)
        })
        try out.close(); complete = true
        return Precompressed(temp: temp, crc: r.crc, comp: r.comp, uncomp: r.uncomp, fingerprint: r.fingerprint)
    }

    /// pigz-style: the file is cut into blocks, each deflated by its own zlib stream on its own core and ended with a full
    /// flush (a byte-aligned empty stored block); the last block is finished normally. The concatenation of the blocks is one
    /// valid raw-deflate stream. The SHA-256 and CRC-32 come from the same mapped bytes the blocks were cut from.
    private static func blockDeflate(_ url: URL, size: Int, into out: FileHandle, in tempDirectory: URL,
                                     budget: ArchivingBudget?, level: Int32) throws -> (comp: Int, fingerprint: FileFingerprint) {
        guard size <= ClassicZIP.maxBytes else { throw IPAError.unsupportedZip("file exceeds classic ZIP limits") }
        // The input is mapped, not copied. The worktree is owned by this signing run (nothing else may write to it); a file
        // truncated underneath us by another process would fault instead of throwing, which is why ownership is required.
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count == size else { throw IPAError.integrity("file changed while compressing: \(url.lastPathComponent)") }
        // Below the block threshold only a chosen level routes a file here: one stream, written straight to `out`.
        let single = size < parallelDeflateMinimum
        let blocks = single ? 1 : max(2, min(ProcessInfo.processInfo.activeProcessorCount, size / (2 * 1024 * 1024)))
        let step = (size + blocks - 1) / blocks
        var pieces = [URL?](repeating: nil, count: blocks)
        var pieceSizes = [Int](repeating: 0, count: blocks)
        var print: FileFingerprint?
        var failure: Error?
        let lock = NSLock()
        func fail(_ e: Error) { lock.lock(); failure = failure ?? e; lock.unlock() }
        func stopped() -> Bool { lock.lock(); defer { lock.unlock() }; return failure != nil }

        DispatchQueue.concurrentPerform(iterations: blocks + 1) { index in
            if stopped() { return }
            do {
                if index == blocks {                      // one extra job: fingerprint of the same bytes
                    var hash = SHA256(), crc = CRC32.begin(), at = 0
                    while at < size {
                        try budget?.check()
                        let end = min(size, at + 1024 * 1024)
                        let part = data[at..<end]
                        hash.update(data: part); crc = CRC32.update(crc, part); at = end
                    }
                    let fp = FileFingerprint(sha256: Data(hash.finalize()), crc32: CRC32.finish(crc), size: size)
                    lock.lock(); print = fp; lock.unlock()
                    return
                }
                let lower = index * step, upper = min(size, lower + step)
                let isLast = index == blocks - 1
                let file: FileHandle
                if single { file = out } else {
                    let piece = tempDirectory.appendingPathComponent(UUID().uuidString + ".blk")
                    file = try createTemporaryFile(at: piece)
                    lock.lock(); pieces[index] = piece; lock.unlock()
                }
                defer { if !single { try? file.close() } }
                var z = z_stream()
                guard deflateInit2_(&z, level, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                                    ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw IPAError.unreadable("compression could not start") }
                defer { deflateEnd(&z) }
                var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
                var produced = 0
                try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    let base = raw.bindMemory(to: UInt8.self).baseAddress!
                    z.next_in = UnsafeMutablePointer(mutating: base + lower); z.avail_in = UInt32(upper - lower)
                    let flush = isLast ? Z_FINISH : Z_FULL_FLUSH
                    while true {
                        try budget?.check()
                        let status: Int32 = buffer.withUnsafeMutableBufferPointer { dst in
                            z.next_out = dst.baseAddress!; z.avail_out = UInt32(dst.count)
                            return zlib.deflate(&z, flush)
                        }
                        let n = buffer.count - Int(z.avail_out)
                        if n > 0 {
                            try budget?.beforeWrite(n)
                            try file.write(contentsOf: Data(buffer[0..<n])); produced += n
                        }
                        if status == Z_STREAM_END { break }
                        guard status == Z_OK || status == Z_BUF_ERROR else { throw IPAError.unreadable("compression failed") }
                        if z.avail_out != 0 && z.avail_in == 0 && !isLast { break }       // full flush complete
                    }
                }
                lock.lock(); pieceSizes[index] = produced; lock.unlock()
            } catch { fail(error) }
        }
        defer { for case let piece? in pieces { try? FileManager.default.removeItem(at: piece) } }
        if let failure { throw failure }
        guard let fingerprint = print else { throw IPAError.integrity("compression produced no fingerprint") }
        if single {
            guard pieceSizes[0] <= ClassicZIP.maxBytes else { throw IPAError.unsupportedZip("compressed file exceeds classic ZIP limits") }
            return (pieceSizes[0], fingerprint)
        }
        var total = 0
        for (i, piece) in pieces.enumerated() {
            guard let piece else { throw IPAError.integrity("missing compressed block") }
            try budget?.check(probeDisk: true)       // the pieces were counted when written; the stitch only needs free disk
            let input = try FileHandle(forReadingFrom: piece)
            defer { try? input.close() }
            var copied = 0
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try budget?.check()
                try out.write(contentsOf: chunk); copied += chunk.count
            }
            guard copied == pieceSizes[i] else { throw IPAError.integrity("compressed block was truncated") }
            total += copied
            guard total <= ClassicZIP.maxBytes else { throw IPAError.unsupportedZip("compressed file exceeds classic ZIP limits") }
        }
        return (total, fingerprint)
    }

    /// Raw deflate of a whole file, streamed in chunks. Returns the CRC32 and both sizes.
    private static func deflate(_ url: URL, checkpoint: (() throws -> Void)? = nil, emit write: (Data) throws -> Void) throws -> (crc: UInt32, comp: Int, uncomp: Int, fingerprint: FileFingerprint) {
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
            try checkpoint?()
            let src = inputDone ? Data() : (try input.read(upToCount: chunk) ?? Data())
            if src.isEmpty { inputDone = true }
            crc = CRC32.update(crc, src); hash.update(data: src)
            guard src.count <= ClassicZIP.maxBytes - uncompressed else { throw IPAError.unsupportedZip("file exceeds classic ZIP limits") }
            uncompressed += src.count
            try src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                var idle = 0
                repeat {
                    try checkpoint?()
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
