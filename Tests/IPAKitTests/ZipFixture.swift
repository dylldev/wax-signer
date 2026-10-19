import Compression
import Foundation
@testable import IPAKit

/// Builds small zip files in memory for tests. Not shipped.
struct ZipFixture {
    struct Entry {
        var name: String
        var data: Data
        var deflate = false
        var corruptCRC = false
        var encrypted = false
        /// Name written to the local header only (central keeps `name`).
        var localName: String?
        /// Raw name bytes, for non-UTF-8 tests.
        var rawName: Data?
        var claimedUncompressed: UInt32?
        var claimedCompressed: UInt32?
        var claimedCRC: UInt32?
        /// Central-directory local-header offset override.
        var centralOffset: UInt32?
        /// Unix mode (e.g. 0o120777 for a symlink); written as a Unix-host entry.
        var unixMode: UInt32?
        var externalAttributes: UInt32?
    }

    var entries: [Entry] = []
    var comment = Data()
    var eocdCount: UInt16?
    var eocdDisk: UInt16 = 0

    mutating func add(_ name: String, _ data: Data = Data(), deflate: Bool = false,
                      corruptCRC: Bool = false, encrypted: Bool = false,
                      tweak: (inout Entry) -> Void = { _ in }) {
        var e = Entry(name: name, data: data, deflate: deflate, corruptCRC: corruptCRC, encrypted: encrypted)
        tweak(&e)
        entries.append(e)
    }

    func write(to url: URL) throws {
        var out = Data()
        var central = Data()
        for e in entries {
            let stored = e.deflate ? Self.deflate(e.data) : e.data
            let crc = e.claimedCRC ?? (CRC32.checksum(e.data) ^ (e.corruptCRC ? 1 : 0))
            let name = e.rawName ?? Data(e.name.utf8)
            let localName = e.localName.map { Data($0.utf8) } ?? name
            let comp = e.claimedCompressed ?? UInt32(stored.count)
            let uncomp = e.claimedUncompressed ?? UInt32(e.data.count)
            let flags: UInt16 = e.encrypted ? 1 : 0
            let method: UInt16 = e.deflate ? 8 : 0
            let offset = UInt32(out.count)

            out.le32(0x04034b50); out.le16(20); out.le16(flags); out.le16(method)
            out.le16(0); out.le16(0); out.le32(crc)
            out.le32(comp); out.le32(uncomp)
            out.le16(UInt16(localName.count)); out.le16(0)
            out.append(localName); out.append(stored)

            central.le32(0x02014b50); central.le16(e.unixMode != nil ? 0x031E : 20); central.le16(20); central.le16(flags); central.le16(method)
            central.le16(0); central.le16(0); central.le32(crc)
            central.le32(comp); central.le32(uncomp)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(e.externalAttributes ?? ((e.unixMode ?? 0) << 16)); central.le32(e.centralOffset ?? offset)
            central.append(name)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        let n = eocdCount ?? UInt16(entries.count)
        out.le32(0x06054b50); out.le16(eocdDisk); out.le16(0)
        out.le16(n); out.le16(n)
        out.le32(UInt32(central.count)); out.le32(cdOffset); out.le16(UInt16(comment.count))
        out.append(comment)
        try out.write(to: url)
    }

    static func deflate(_ data: Data) -> Data {
        var dst = [UInt8](repeating: 0, count: data.count + 1024)
        let n = data.withUnsafeBytes { src in
            compression_encode_buffer(&dst, dst.count, src.bindMemory(to: UInt8.self).baseAddress!,
                                      data.count, nil, COMPRESSION_ZLIB)
        }
        precondition(n > 0, "deflate failed")
        return Data(dst[0..<n])
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8)]) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xff)) } }
}

func infoPlist(_ dict: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
}
