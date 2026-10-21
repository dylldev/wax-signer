import Compression
import Foundation
import IPAKit

/// Pulls the dylibs out of a Debian package (`.deb`), the format iOS tweaks come in. A `.deb` is an `ar` archive
/// holding `data.tar.<compression>`; this reads that, finds files ending in `.dylib`, and writes each into the output
/// folder by its bare file name (nothing is ever written outside that folder).
enum DebExtractor {
    static let maxDecompressed = 1 << 30      // 1 GiB of tar data
    static let maxFile = 512 << 20            // 512 MiB per library

    static func dylibs(inDeb deb: URL, to directory: URL) throws -> [URL] {
        let bytes = try Data(contentsOf: deb, options: .mappedIfSafe)
        let members = try arMembers(bytes)
        guard let data = members.first(where: { $0.name.hasPrefix("data.tar") }) else {
            throw SigningError.bundle("\(deb.lastPathComponent) is not a tweak package (no data archive inside).")
        }
        let tar = try decompress(data.bytes, name: data.name)
        let files = try tarFiles(tar).filter { $0.name.lowercased().hasSuffix(".dylib") && !$0.name.hasSuffix("/") }
        guard !files.isEmpty else { throw SigningError.bundle("\(deb.lastPathComponent) contains no .dylib files.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for f in files {
            let bare = (f.name as NSString).lastPathComponent        // never a path: no way to leave the folder
            guard !bare.isEmpty, bare != ".", bare != ".." else { continue }
            let url = directory.appendingPathComponent(bare)
            try f.bytes.write(to: url)
            written.append(url)
        }
        return written
    }

    // MARK: ar

    /// Members of an `ar` archive: GNU names ("name/"), BSD names ("#1/N" with the name in the data), plain names.
    static func arMembers(_ d: Data) throws -> [(name: String, bytes: Data)] {
        guard d.count >= 8, d.prefix(8) == Data("!<arch>\n".utf8) else { throw SigningError.bundle("That file is not a .deb package.") }
        var out: [(String, Data)] = []
        var pos = 8
        while pos + 60 <= d.count {
            let header = d[(d.startIndex + pos)..<(d.startIndex + pos + 60)]
            guard header.suffix(2) == Data("`\n".utf8) else { throw SigningError.bundle("The .deb package is damaged (bad archive header).") }
            func text(_ r: Range<Int>) -> String { String(decoding: header[(header.startIndex + r.lowerBound)..<(header.startIndex + r.upperBound)], as: UTF8.self).trimmingCharacters(in: .whitespaces) }
            var name = text(0..<16)
            guard let size = Int(text(48..<58)), size >= 0, pos + 60 + size <= d.count else { throw SigningError.bundle("The .deb package is damaged (bad member size).") }
            var start = pos + 60, length = size
            if name.hasPrefix("#1/"), let n = Int(name.dropFirst(3)), n <= length {     // BSD: name stored in the data
                name = String(decoding: d[(d.startIndex + start)..<(d.startIndex + start + n)], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                start += n; length -= n
            } else if name.hasSuffix("/") { name.removeLast() }
            if !name.hasPrefix("__.SYMDEF"), name != "/", name != "//" {
                out.append((name, Data(d[(d.startIndex + start)..<(d.startIndex + start + length)])))
            }
            pos += 60 + size + (size % 2)
        }
        return out
    }

    // MARK: Compression

    static func decompress(_ d: Data, name: String) throws -> Data {
        switch (name as NSString).pathExtension.lowercased() {
        case "tar": return d
        case "gz": return try inflate(gzipPayload(d), algorithm: COMPRESSION_ZLIB)
        case "xz", "lzma": return try inflate(d, algorithm: COMPRESSION_LZMA)
        case "zst": throw SigningError.bundle("This package uses zstd compression, which Wax cannot read yet. Repack the tweak with gzip or xz.")
        case "bz2": throw SigningError.bundle("This package uses bzip2 compression, which Wax cannot read yet. Repack the tweak with gzip or xz.")
        default: throw SigningError.bundle("This package uses a compression Wax does not support (\(name)).")
        }
    }

    /// The raw deflate stream inside a gzip file (the Compression framework wants it without the gzip wrapper).
    private static func gzipPayload(_ d: Data) throws -> Data {
        guard d.count > 18, d[d.startIndex] == 0x1F, d[d.startIndex + 1] == 0x8B, d[d.startIndex + 2] == 8 else {
            throw SigningError.bundle("The tweak's data is not a valid gzip file.")
        }
        let flags = d[d.startIndex + 3]
        var i = 10
        if flags & 0x04 != 0 { guard i + 2 <= d.count else { throw bad }; i += 2 + Int(d[d.startIndex + i]) + Int(d[d.startIndex + i + 1]) << 8 }
        for bit in [UInt8(0x08), 0x10] where flags & bit != 0 {
            while i < d.count, d[d.startIndex + i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x02 != 0 { i += 2 }
        guard i < d.count - 8 else { throw bad }
        return Data(d[(d.startIndex + i)..<(d.endIndex - 8)])      // drop the CRC32 + size trailer
    }

    private static var bad: SigningError { SigningError.bundle("The tweak's data is damaged.") }

    private static func inflate(_ input: Data, algorithm: compression_algorithm) throws -> Data {
        guard let stream = CompressionStream(COMPRESSION_STREAM_DECODE, algorithm) else { throw bad }
        var out = Data()
        let chunk = 1 << 16
        var buffer = [UInt8](repeating: 0, count: chunk)
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: true) }
                out.append(buffer, count: chunk - stream.pendingOutput)
                guard out.count <= maxDecompressed else { throw SigningError.bundle("The tweak package expands to more than the allowed size.") }
                switch status {
                case COMPRESSION_STATUS_END: return
                case COMPRESSION_STATUS_OK: continue
                default: throw bad
                }
            }
        }
        return out
    }

    // MARK: tar

    private struct TarFile { let name: String; let bytes: Data }

    /// Regular files of a tar archive (ustar, GNU long names). Directories, links and special files are skipped.
    private static func tarFiles(_ tar: Data) throws -> [TarFile] {
        var files: [TarFile] = []
        var pos = 0
        var longName: String?
        while pos + 512 <= tar.count {
            let h = tar[(tar.startIndex + pos)..<(tar.startIndex + pos + 512)]
            if h.allSatisfy({ $0 == 0 }) { break }
            func str(_ r: Range<Int>) -> String { String(decoding: h[(h.startIndex + r.lowerBound)..<(h.startIndex + r.upperBound)].prefix { $0 != 0 }, as: UTF8.self) }
            let sizeText = str(124..<136).trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText, radix: 8), size >= 0, size <= maxFile * 4 else { throw bad }
            let type = h[h.startIndex + 156]
            var name = str(0..<100)
            let prefix = str(345..<500)
            if !prefix.isEmpty { name = prefix + "/" + name }
            let dataStart = pos + 512
            guard dataStart + size <= tar.count else { throw bad }
            let body = tar[(tar.startIndex + dataStart)..<(tar.startIndex + dataStart + size)]
            if type == UInt8(ascii: "L") {                      // GNU long name for the next entry
                longName = String(decoding: body.prefix { $0 != 0 }, as: UTF8.self)
            } else {
                if let l = longName { name = l; longName = nil }
                if (type == 0 || type == UInt8(ascii: "0")) && size <= maxFile { files.append(TarFile(name: name, bytes: Data(body))) }
            }
            pos = dataStart + ((size + 511) / 512) * 512
        }
        return files
    }
}
