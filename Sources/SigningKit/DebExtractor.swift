import Compression
import Foundation
import IPAKit

/// Pulls the dylibs out of a Debian package (`.deb`), the format iOS tweaks come in. A `.deb` is an `ar` archive
/// holding `data.tar.<compression>`; this reads that, finds files ending in `.dylib`, and writes each into the output
/// folder by its bare file name (nothing is ever written outside that folder).
enum DebExtractor {
    static let maxDecompressed = DebArchive.maxDecompressed      // 1 GiB of tar data
    static let maxFile = DebArchive.maxFile            // 512 MiB per library

    static func dylibs(inDeb deb: URL, to directory: URL) throws -> [URL] {
        let bytes = try Data(contentsOf: deb, options: .mappedIfSafe)
        let members = try arMembers(bytes)
        guard let data = members.first(where: { $0.name.hasPrefix("data.tar") }) else {
            throw SigningError.bundle("\(deb.lastPathComponent) is not a tweak package (no data archive inside).")
        }
        let tar = try decompress(data.bytes, name: data.name)
        let files = try DebArchive.tarFiles(tar).filter { $0.name.lowercased().hasSuffix(".dylib") && !$0.name.hasSuffix("/") }
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
        try DebArchive.arMembers(d)
    }

    // MARK: Compression

    static func decompress(_ d: Data, name: String) throws -> Data {
        switch (name as NSString).pathExtension.lowercased() {
        case "tar":
            guard d.count <= maxDecompressed else { throw bad }
            return d
        case "gz":
            let member = try DebGzip.parse(d)
            let output = try DebDeflate.decode(member.payload)
            try member.validate(output)
            return output
        case "xz", "lzma": return try inflate(d, algorithm: COMPRESSION_LZMA)
        case "zst": throw SigningError.bundle("This package uses zstd compression, which Wax cannot read yet. Repack the tweak with gzip or xz.")
        case "bz2": throw SigningError.bundle("This package uses bzip2 compression, which Wax cannot read yet. Repack the tweak with gzip or xz.")
        default: throw SigningError.bundle("This package uses a compression Wax does not support (\(name)).")
        }
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
                let before = stream.pendingInput
                let status = buffer.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: true) }
                let produced = chunk - stream.pendingOutput
                guard produced <= maxDecompressed - out.count else { throw SigningError.bundle("The tweak package expands to more than the allowed size.") }
                out.append(buffer, count: produced)
                switch status {
                case COMPRESSION_STATUS_END:
                    guard stream.pendingInput == 0 else { throw bad }
                    return
                case COMPRESSION_STATUS_OK:
                    guard produced != 0 || stream.pendingInput < before else { throw bad }
                    continue
                default: throw bad
                }
            }
        }
        return out
    }

}
