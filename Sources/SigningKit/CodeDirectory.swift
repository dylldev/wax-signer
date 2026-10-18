import CryptoKit
import Foundation

/// Builds a version 0x20400 CodeDirectory with SHA-256 page hashes.
/// SHA-1 slots for pre-iOS-12 compatibility are not produced (prototype scope).
struct CodeDirectory {
    var identifier: String
    var teamIdentifier: String?
    var codeLimit: Int
    var execSegmentBase: UInt64
    var execSegmentLimit: UInt64
    var execSegmentFlags: UInt64
    /// Special slot number (1...7) to the SHA-256 of that blob/file.
    var specialHashes: [Int: Data]

    static let execMainBinary: UInt64 = 0x1
    static let execAllowUnsigned: UInt64 = 0x10 // what Apple's codesign sets when get-task-allow is granted

    static let pageSizeLog2 = 12

    func build(image: Data) -> Data {
        let pageSize = 1 << Self.pageSizeLog2
        let pageCount = (codeLimit + pageSize - 1) / pageSize
        let nSpecial = specialHashes.keys.max() ?? 0

        let ident = Data(identifier.utf8) + Data([0])
        let team = teamIdentifier.map { Data($0.utf8) + Data([0]) }
        let headerSize = 88
        let identOffset = headerSize
        let teamOffset = team != nil ? identOffset + ident.count : 0
        let specialStart = identOffset + ident.count + (team?.count ?? 0)
        let hashOffset = specialStart + nSpecial * 32

        var out = Data()
        out += Blob.be32(Blob.codeDirectory)
        out += Blob.be32(0)                                         // length, patched below
        out += Blob.be32(0x20400)                                   // version
        out += Blob.be32(0)                                         // flags
        out += Blob.be32(UInt32(hashOffset))
        out += Blob.be32(UInt32(identOffset))
        out += Blob.be32(UInt32(nSpecial))
        out += Blob.be32(UInt32(pageCount))
        out += Blob.be32(UInt32(min(codeLimit, Int(UInt32.max))))   // codeLimit
        out += Data([32, 2, 0, UInt8(Self.pageSizeLog2)])           // hashSize, SHA-256, platform, pageSize
        out += Blob.be32(0)                                         // spare2
        out += Blob.be32(0)                                         // scatterOffset
        out += Blob.be32(UInt32(teamOffset))
        out += Blob.be32(0)                                         // spare3
        out += Blob.be64(UInt64(codeLimit))                         // codeLimit64
        out += Blob.be64(execSegmentBase)
        out += Blob.be64(execSegmentLimit)
        out += Blob.be64(execSegmentFlags)
        precondition(out.count == headerSize)

        out += ident
        if let team { out += team }
        for slot in stride(from: nSpecial, through: 1, by: -1) {
            out += specialHashes[slot] ?? Data(count: 32)
        }
        for page in 0..<pageCount {
            let start = page * pageSize
            let end = min(start + pageSize, codeLimit)
            out += Data(SHA256.hash(data: image[(image.startIndex + start)..<(image.startIndex + end)]))
        }

        let length = UInt32(out.count)
        out.replaceSubrange(4..<8, with: Blob.be32(length))
        return out
    }
}
