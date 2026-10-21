import Foundation

/// A thin, 64-bit, little-endian Mach-O file held in memory. Fat binaries are rejected (prototype scope).
struct MachO {
    private(set) var data: Data
    let fileType: UInt32

    // Load-command bookkeeping (byte offsets into `data`).
    private var ncmdsOffset = 16
    private var sizeofcmdsOffset = 20
    private var signatureCommandOffset: Int?
    private var linkeditCommandOffset: Int?
    private(set) var textFileOffset: UInt64 = 0
    private(set) var textFileSize: UInt64 = 0
    private var firstSectionOffset: Int = .max
    private var commandsEnd: Int = 32

    static let executeFileType: UInt32 = 2
    private static let lcCodeSignature: UInt32 = 0x1d
    private static let lcSegment64: UInt32 = 0x19
    private static let linkeditPage: UInt64 = 0x4000

    init(_ data: Data) throws {
        self.data = Data(data) // reindex from 0
        guard data.count >= 32 else { throw SigningError.machO("file too small") }
        let magic = self.data.u32(0)
        switch magic {
        case 0xFEED_FACF: break
        case 0xCAFE_BABE, 0xBEBA_FECA: throw SigningError.machO("fat binaries are not supported yet")
        default: throw SigningError.machO("not a 64-bit little-endian Mach-O (magic \(String(magic, radix: 16)))")
        }
        fileType = self.data.u32(12)
        try parseCommands()
    }

    /// True if the file starts with a Mach-O or fat magic.
    static func looksLikeMachO(_ prefix: Data) -> Bool {
        guard prefix.count >= 4 else { return false }
        let m = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEED_FACF, 0xFEED_FACE, 0xCAFE_BABE, 0xBEBA_FECA].contains(m)
    }

    private mutating func parseCommands() throws {
        let count = Int(data.u32(16)), total = Int(data.u32(20))
        var offset = 32
        guard 32 + total <= data.count else { throw SigningError.machO("load commands exceed file") }
        for _ in 0..<count {
            guard offset + 8 <= data.count else { throw SigningError.machO("truncated load command") }
            let cmd = data.u32(offset), size = Int(data.u32(offset + 4))
            guard size >= 8, offset + size <= 32 + total else { throw SigningError.machO("bad load command size") }
            if cmd == Self.lcCodeSignature {
                guard size >= 16 else { throw SigningError.machO("code signature command too small") }
                guard signatureCommandOffset == nil else { throw SigningError.machO("more than one code signature command") }
                signatureCommandOffset = offset
            }
            if [Self.lcLoadDylib, Self.lcLoadWeakDylib, Self.lcRpath].contains(cmd) {
                guard size >= 12 else { throw SigningError.machO("library command too small") }   // its name offset is read at +8
            }
            if cmd == 0x21 || cmd == 0x2C {
                guard size >= 20 else { throw SigningError.machO("encryption command too small") }
                if data.u32(offset + 16) != 0 { isEncrypted = true }
            }
            if cmd == Self.lcSegment64 {
                guard size >= 72 else { throw SigningError.machO("segment command too small") }
                let name = String(decoding: data[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }, as: UTF8.self)
                if name == "__LINKEDIT" {
                    linkeditCommandOffset = offset
                    linkeditFileOffset = data.u64(offset + 40)
                    linkeditFileSize = data.u64(offset + 48)
                }
                if name == "__TEXT" {
                    textFileOffset = data.u64(offset + 40)
                    textFileSize = data.u64(offset + 48)
                }
                let nsects = Int(data.u32(offset + 64))
                guard nsects <= (size - 72) / 80 else { throw SigningError.machO("section table exceeds its segment command") }
                for s in 0..<nsects {
                    let sect = offset + 72 + s * 80
                    guard sect + 80 <= offset + size else { throw SigningError.machO("bad section table") }
                    let fileOff = Int(data.u32(sect + 48))
                    let sectSize = data.u64(sect + 40)
                    if fileOff != 0, sectSize != 0 { firstSectionOffset = min(firstSectionOffset, fileOff) }
                }
            }
            offset += size
        }
        commandsEnd = 32 + total
        guard linkeditCommandOffset != nil else { throw SigningError.machO("no __LINKEDIT segment") }
        // The code signature must lie inside the file, or removing it would corrupt the image.
        if let sig = existingSignature, sig.offset > data.count || sig.offset + sig.size > data.count {
            throw SigningError.machO("existing code signature extends past the end of the file")
        }
    }

    // MARK: Dynamic libraries

    private static let lcLoadDylib: UInt32 = 0xC
    private static let lcLoadWeakDylib: UInt32 = 0x8000_0018
    private static let lcRpath: UInt32 = 0x8000_001C

    /// Install names of the libraries this binary loads.
    var loadDylibNames: [String] { commands(of: [Self.lcLoadDylib, Self.lcLoadWeakDylib]).map(dylibName) }

    /// True when the binary searches its own Frameworks folder through `@rpath`.
    var hasFrameworksRpath: Bool {
        commands(of: [Self.lcRpath]).contains { off in
            let start = off + Int(data.u32(off + 8))
            let end = min(off + Int(data.u32(off + 4)), data.count)
            guard start < end else { return false }
            return String(decoding: data[start..<end].prefix { $0 != 0 }, as: UTF8.self).hasSuffix("@executable_path/Frameworks")
        }
    }

    private func commands(of kinds: [UInt32]) -> [Int] {
        var found: [Int] = []
        var offset = 32
        for _ in 0..<Int(data.u32(16)) {
            guard offset + 8 <= data.count else { break }
            let size = Int(data.u32(offset + 4))
            if kinds.contains(data.u32(offset)) { found.append(offset) }
            offset += max(size, 8)
        }
        return found
    }

    private func dylibName(at off: Int) -> String {
        let start = off + Int(data.u32(off + 8))
        let end = min(off + Int(data.u32(off + 4)), data.count)
        guard start < end else { return "" }
        return String(decoding: data[start..<end].prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Adds an `LC_LOAD_DYLIB` for `name` into the header padding. Throws, changing nothing, when the header has no
    /// room (it must also keep 16 bytes free for the code-signature command the signer adds).
    mutating func addLoadDylib(_ name: String) throws {
        if loadDylibNames.contains(name) { return }
        let nameBytes = Data(name.utf8) + Data([0])
        let size = (24 + nameBytes.count + 7) & ~7
        let reserve = signatureCommandOffset == nil ? 16 : 0
        guard commandsEnd + size + reserve <= firstSectionOffset else {
            throw SigningError.machO("There is no room in this app's header for another library. Remove one or choose fewer.")
        }
        var cmd = Data(count: size)
        cmd.setU32(0, Self.lcLoadDylib); cmd.setU32(4, UInt32(size)); cmd.setU32(8, 24)
        cmd.setU32(12, 2); cmd.setU32(16, 0x0001_0000); cmd.setU32(20, 0x0001_0000)
        cmd.replaceSubrange(24..<(24 + nameBytes.count), with: nameBytes)
        data.replaceSubrange(commandsEnd..<(commandsEnd + size), with: cmd)
        data.setU32(ncmdsOffset, data.u32(ncmdsOffset) + 1)
        data.setU32(sizeofcmdsOffset, data.u32(sizeofcmdsOffset) + UInt32(size))
        commandsEnd += size
    }

    /// The signature currently present, if any (`dataoff`, `datasize`).
    var existingSignature: (offset: Int, size: Int)? {
        signatureCommandOffset.map { (Int(data.u32($0 + 8)), Int(data.u32($0 + 12))) }
    }

    /// Bytes hashed by a CodeDirectory: everything before the signature.
    /// Call `prepareForSignature(size:)` first so headers are final.
    var signedLength: Int { signatureStart }
    private(set) var signatureStart = 0

    /// LC_ENCRYPTION_INFO(_64) with a non-zero cryptid: FairPlay-encrypted. Re-signing such a binary yields an app
    /// that cannot run, so the signer refuses it.
    private(set) var isEncrypted = false
    private(set) var linkeditFileOffset: UInt64 = 0
    private(set) var linkeditFileSize: UInt64 = 0

    /// Removes any existing signature and rewrites the headers for a signature blob of `size` bytes
    /// placed at the (16-byte aligned) end of the file. The signature must be the last thing in the file.
    mutating func prepareForSignature(size: Int) throws {
        guard let linkedit = linkeditCommandOffset else { throw SigningError.machO("no __LINKEDIT") }
        var length = data.count

        if let old = existingSignature {
            // Anything after the signature would be deleted along with it, so it must not exist.
            guard old.offset + old.size == data.count else {
                throw SigningError.machO("existing signature is not at the end of the file")
            }
            guard old.offset <= data.count else { throw SigningError.machO("signature offset out of range") }
            length = old.offset
            data.removeSubrange(old.offset..<data.count)
        } else {
            // New LC_CODE_SIGNATURE (16 bytes) must fit in the header padding.
            guard commandsEnd + 16 <= firstSectionOffset else {
                throw SigningError.machO("no room in the Mach-O header for a code-signature load command")
            }
            data.replaceSubrange(commandsEnd..<(commandsEnd + 16),
                                 with: Data([0x1d, 0, 0, 0, 0x10, 0, 0, 0]) + Data(count: 8))
            data.setU32(ncmdsOffset, data.u32(ncmdsOffset) + 1)
            data.setU32(sizeofcmdsOffset, data.u32(sizeofcmdsOffset) + 16)
            signatureCommandOffset = commandsEnd
            commandsEnd += 16
        }

        let aligned = (length + 15) & ~15
        if aligned > length { data.append(Data(count: aligned - length)) }
        signatureStart = aligned

        data.setU32(signatureCommandOffset! + 8, UInt32(aligned))
        data.setU32(signatureCommandOffset! + 12, UInt32(size))

        // __LINKEDIT must now extend to the end of the signature.
        let fileOff = data.u64(linkedit + 40)
        guard fileOff <= UInt64(aligned) else { throw SigningError.machO("__LINKEDIT starts after the signature position") }
        let newFileSize = UInt64(aligned + size) - fileOff
        data.setU64(linkedit + 48, newFileSize)
        data.setU64(linkedit + 32, (newFileSize + Self.linkeditPage - 1) / Self.linkeditPage * Self.linkeditPage)
    }

    mutating func attach(signature: Data) {
        precondition(data.count == signatureStart, "image changed after prepareForSignature")
        data.append(signature)
    }
}

extension Data {
    func u32(_ o: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + o + $1]) << UInt32(8 * $1) }
    }
    func u64(_ o: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(self[startIndex + o + $1]) << UInt64(8 * $1) }
    }
    mutating func setU32(_ o: Int, _ v: UInt32) {
        for i in 0..<4 { self[startIndex + o + i] = UInt8((v >> UInt32(8 * i)) & 0xff) }
    }
    mutating func setU64(_ o: Int, _ v: UInt64) {
        for i in 0..<8 { self[startIndex + o + i] = UInt8((v >> UInt64(8 * i)) & 0xff) }
    }
}
