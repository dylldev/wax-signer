import Foundation

/// A thin, 64-bit, little-endian Mach-O file held in memory. Universal binaries must first be validated and thinned by FatMachO.
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
    private var firstSectionOffset: Int = 32
    private var fileDataRanges: [Range<Int>] = []
    private var commandsEnd: Int = 32

    static let executeFileType: UInt32 = 2
    private static let lcCodeSignature: UInt32 = 0x1d
    private static let lcSegment64: UInt32 = 0x19
    private static let linkeditPage: UInt64 = 0x4000

    private static let fixedMinimums: [UInt32: Int] = [0x4: 16, 0x5: 16, 0x16: 16, 0x17: 12, 0x1A: 72,
        0x1B: 24, 0x8000_0028: 24, 0x2A: 16, 0x2D: 12, 0x31: 40]

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
        guard self.data.u32(4) == 0x0100_000C, [0, 2].contains(self.data.u32(8) & 0x00FF_FFFF) else {
            throw SigningError.machO("only arm64 and arm64e binaries can be signed")
        }
        guard [2, 6, 8].contains(fileType) else { throw SigningError.machO("unsupported Mach-O file type") }
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
        guard CheckedBytes.contains(32, total, in: data.count), count <= total / 8 else {
            throw SigningError.machO("load commands exceed their declared region")
        }
        commandsEnd = 32 + total
        var offset = 32
        var segments: [(name: String, range: Range<Int>)] = []
        var sectionStarts: [Int] = []
        var platforms: Set<UInt32> = []
        var entryPoints: [UInt64] = []
        func range(_ start: UInt64, _ length: UInt64) throws -> Range<Int> {
            guard CheckedBytes.contains(start, length, in: UInt64(data.count)) else {
                throw SigningError.machO("file data range lies outside the Mach-O")
            }
            return Int(start)..<Int(start + length)
        }
        for _ in 0..<count {
            guard CheckedBytes.contains(offset, 8, in: commandsEnd) else { throw SigningError.machO("truncated load command") }
            let cmd = data.u32(offset), size = Int(data.u32(offset + 4))
            guard size >= 8, size % 8 == 0, CheckedBytes.contains(offset, size, in: commandsEnd) else {
                throw SigningError.machO("bad load command size")
            }
            func minimum(_ n: Int) throws {
                guard size >= n else { throw SigningError.machO("load command \(String(cmd, radix: 16)) is too small") }
            }
            // Fixed records used by supported device images, even when signing does not otherwise interpret them.
            if let fixed = Self.fixedMinimums[cmd] { try minimum(fixed) }
            if cmd == 0x8000_0028 { entryPoints.append(data.u64(offset + 8)) }
            if cmd == Self.lcCodeSignature {
                try minimum(16)
                guard signatureCommandOffset == nil else { throw SigningError.machO("more than one code signature command") }
                signatureCommandOffset = offset
            }
            if [Self.lcLoadDylib, Self.lcLoadWeakDylib, 0xD, 0x8000_001F, 0x20, 0x8000_0023,
                Self.lcRpath, 0xE, 0xF, 0x12, 0x13, 0x14, 0x15, 0x27, 0x39].contains(cmd) {
                let fixed = [Self.lcLoadDylib, Self.lcLoadWeakDylib, 0xD, 0x8000_001F, 0x20, 0x8000_0023].contains(cmd) ? 24 : 12
                try minimum(fixed)
                let start = Int(data.u32(offset + 8))
                guard start >= fixed, start < size, data[(offset + start)..<(offset + size)].contains(0) else {
                    throw SigningError.machO("library command has an invalid string offset or unterminated name")
                }
            }
            if cmd == 0x21 || cmd == 0x2C {
                try minimum(cmd == 0x2C ? 24 : 20)
                _ = try range(UInt64(data.u32(offset + 8)), UInt64(data.u32(offset + 12)))
                if data.u32(offset + 16) != 0 { isEncrypted = true }
            }
            if cmd == 0x32 { // LC_BUILD_VERSION
                try minimum(24)
                guard Int(data.u32(offset + 20)) <= (size - 24) / 8 else { throw SigningError.machO("build tool table exceeds command") }
                platforms.insert(data.u32(offset + 8))
            } else if [UInt32(0x24), 0x25, 0x2F, 0x30].contains(cmd) {
                try minimum(16)
                platforms.insert(cmd == 0x25 ? 2 : (cmd == 0x30 ? 4 : 0))
            }
            if cmd == Self.lcSegment64 {
                try minimum(72)
                let name = String(decoding: data[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }, as: UTF8.self)
                let fileOff = data.u64(offset + 40), fileSize = data.u64(offset + 48)
                let segment = try range(fileOff, fileSize)
                let vm = data.u64(offset + 24), vmSize = data.u64(offset + 32)
                guard !vm.addingReportingOverflow(vmSize).overflow else { throw SigningError.machO("segment VM range overflows") }
                if fileSize != 0 {
                    guard !segments.contains(where: { $0.range.overlaps(segment) }) else { throw SigningError.machO("overlapping file segments") }
                    segments.append((name, segment))
                }
                if name == "__LINKEDIT" {
                    guard linkeditCommandOffset == nil else { throw SigningError.machO("duplicate __LINKEDIT segment") }
                    linkeditCommandOffset = offset; linkeditFileOffset = fileOff; linkeditFileSize = fileSize
                }
                if name == "__TEXT" {
                    guard textFileSize == 0, fileOff == 0, fileSize >= UInt64(commandsEnd) else { throw SigningError.machO("invalid __TEXT segment") }
                    textFileOffset = fileOff; textFileSize = fileSize
                }
                let nsects = Int(data.u32(offset + 64))
                guard nsects <= (size - 72) / 80 else { throw SigningError.machO("section table exceeds its segment command") }
                for s in 0..<nsects {
                    let sect = offset + 72 + s * 80
                    let address = data.u64(sect + 32), length = data.u64(sect + 40)
                    guard address >= vm, CheckedBytes.contains(address - vm, length, in: vmSize) else { throw SigningError.machO("section lies outside its VM segment") }
                    let kind = data.u32(sect + 64) & 0xFF
                    if length != 0, ![UInt32(1), 0xC, 0x12].contains(kind) { // zero-fill sections occupy no file bytes
                        let r = try range(UInt64(data.u32(sect + 48)), length)
                        guard r.lowerBound >= commandsEnd, r.lowerBound >= segment.lowerBound, r.upperBound <= segment.upperBound else {
                            throw SigningError.machO("section overlaps load commands or lies outside its segment")
                        }
                        fileDataRanges.append(r); sectionStarts.append(r.lowerBound)
                    }
                    let relocCount = UInt64(data.u32(sect + 60))
                    if relocCount != 0 { fileDataRanges.append(try range(UInt64(data.u32(sect + 56)), relocCount * 8)) }
                }
            }
            // File-backed LINKEDIT payloads must survive replacement of the old signature.
            if [UInt32(0x1E), 0x26, 0x29, 0x2B, 0x2E, 0x8000_0033, 0x8000_0034, 0x36, 0x37, 0x38].contains(cmd) {
                try minimum(16)
                let length = UInt64(data.u32(offset + 12))
                if length != 0 { fileDataRanges.append(try range(UInt64(data.u32(offset + 8)), length)) }
            }
            if cmd == 0x31 { // LC_NOTE
                let n = data.u64(offset + 32)
                if n != 0 { fileDataRanges.append(try range(data.u64(offset + 24), n)) }
            }
            if cmd == 0x16 { // LC_TWOLEVEL_HINTS
                let n = UInt64(data.u32(offset + 12)) * 4
                if n != 0 { fileDataRanges.append(try range(UInt64(data.u32(offset + 8)), n)) }
            }
            if cmd == 0x2 { // LC_SYMTAB
                try minimum(24)
                for (o, n) in [(UInt64(data.u32(offset + 8)), UInt64(data.u32(offset + 12)) * 16),
                               (UInt64(data.u32(offset + 16)), UInt64(data.u32(offset + 20)))] where n != 0 {
                    fileDataRanges.append(try range(o, n))
                }
            }
            if cmd == 0x22 || cmd == 0x8000_0022 { // LC_DYLD_INFO(_ONLY)
                try minimum(48)
                for i in 0..<5 {
                    let n = UInt64(data.u32(offset + 12 + i * 8))
                    if n != 0 { fileDataRanges.append(try range(UInt64(data.u32(offset + 8 + i * 8)), n)) }
                }
            }
            if cmd == 0xB { // LC_DYSYMTAB: offsets/counts for file tables, not symbol-table indices
                try minimum(80)
                for (field, stride) in [(32, 8), (40, 56), (48, 4), (56, 4), (64, 8), (72, 8)] {
                    let n = UInt64(data.u32(offset + field + 4)) * UInt64(stride)
                    if n != 0 { fileDataRanges.append(try range(UInt64(data.u32(offset + field)), n)) }
                }
            }
            offset += size
        }
        guard offset == commandsEnd else { throw SigningError.machO("load command count does not match sizeofcmds") }
        guard platforms.count <= 1, platforms.allSatisfy({ $0 == 2 || $0 == 4 }) else {
            throw SigningError.machO("unsupported or inconsistent platform (only iOS and watchOS device code is supported)")
        }
        guard linkeditCommandOffset != nil, textFileSize != 0 else { throw SigningError.machO("missing __TEXT or __LINKEDIT segment") }
        guard segments.allSatisfy({ $0.name == "__LINKEDIT" || UInt64($0.range.upperBound) <= linkeditFileOffset }) else {
            throw SigningError.machO("__LINKEDIT is not the last file-backed segment")
        }
        guard linkeditFileOffset >= UInt64(commandsEnd), fileDataRanges.allSatisfy({ $0.lowerBound >= commandsEnd }) else {
            throw SigningError.machO("file data overlaps load commands")
        }
        for entry in entryPoints {
            guard entry >= UInt64(commandsEnd), entry < textFileSize else { throw SigningError.machO("entry point overlaps commands or lies outside __TEXT") }
            fileDataRanges.append(Int(entry)..<(Int(entry) + 1))
        }
        // No sections is not evidence of unlimited writable header padding.
        firstSectionOffset = sectionStarts.min() ?? commandsEnd
        firstSectionOffset = min(firstSectionOffset, fileDataRanges.map(\.lowerBound).min() ?? firstSectionOffset)
        if let sig = existingSignature {
            let r = try range(UInt64(sig.offset), UInt64(sig.size))
            guard sig.size > 0, sig.offset >= commandsEnd,
                  UInt64(sig.offset) >= linkeditFileOffset,
                  UInt64(r.upperBound) <= linkeditFileOffset + linkeditFileSize,
                  !segments.contains(where: { $0.name != "__LINKEDIT" && $0.range.overlaps(r) }),
                  !fileDataRanges.contains(where: { $0.overlaps(r) }) else {
                throw SigningError.machO("invalid code signature placement or overlap")
            }
        }
    }

    private func requirePadding(_ length: Int) throws {
        guard CheckedBytes.contains(commandsEnd, length, in: min(firstSectionOffset, data.count)),
              data[commandsEnd..<(commandsEnd + length)].allSatisfy({ $0 == 0 }) else {
            throw SigningError.machO("no room in the Mach-O header for another load command")
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
            guard CheckedBytes.contains(offset, 8, in: commandsEnd) else { break }
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
        guard !name.utf8.contains(0), name.utf8.count <= Int(UInt32.max) - 32 else { throw SigningError.machO("invalid library name") }
        let nameBytes = Data(name.utf8) + Data([0])
        let size = (24 + nameBytes.count + 7) & ~7
        let reserve = signatureCommandOffset == nil ? 16 : 0
        try requirePadding(size + reserve)
        guard data.u32(ncmdsOffset) < UInt32.max, UInt64(data.u32(sizeofcmdsOffset)) + UInt64(size) <= UInt32.max else {
            throw SigningError.machO("load command counts overflow")
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
        guard size >= 0, size <= Int(UInt32.max) else { throw SigningError.machO("signature size is out of range") }
        let old = existingSignature
        if let old {
            guard old.size <= data.count, old.offset == data.count - old.size else {
                throw SigningError.machO("existing signature is not at the end of the file")
            }
        } else {
            try requirePadding(16)
            guard data.u32(ncmdsOffset) < UInt32.max, data.u32(sizeofcmdsOffset) <= UInt32.max - 16 else {
                throw SigningError.machO("load command counts overflow")
            }
        }
        let length = old?.offset ?? data.count
        guard length <= Int(UInt32.max) - 15 else { throw SigningError.machO("signature offset is out of range") }
        let aligned = (length + 15) & ~15
        let fileOff = data.u64(linkedit + 40)
        guard fileOff <= UInt64(aligned) else { throw SigningError.machO("__LINKEDIT starts after the signature position") }
        let newFileSize = UInt64(aligned) + UInt64(size) - fileOff
        let vmSize = (newFileSize + Self.linkeditPage - 1) / Self.linkeditPage * Self.linkeditPage
        guard !data.u64(linkedit + 24).addingReportingOverflow(vmSize).overflow else {
            throw SigningError.machO("rewritten __LINKEDIT VM range overflows")
        }
        // All validation precedes mutation. Commit bytes and bookkeeping together.
        var updated = data
        if let old { updated.removeSubrange(old.offset..<updated.count) }
        let command = signatureCommandOffset ?? commandsEnd
        if signatureCommandOffset == nil {
            updated.replaceSubrange(commandsEnd..<(commandsEnd + 16),
                                    with: Data([0x1d, 0, 0, 0, 0x10, 0, 0, 0]) + Data(count: 8))
            updated.setU32(ncmdsOffset, updated.u32(ncmdsOffset) + 1)
            updated.setU32(sizeofcmdsOffset, updated.u32(sizeofcmdsOffset) + 16)
        }
        updated.append(Data(count: aligned - length))
        updated.setU32(command + 8, UInt32(aligned)); updated.setU32(command + 12, UInt32(size))
        updated.setU64(linkedit + 48, newFileSize); updated.setU64(linkedit + 32, vmSize)
        if signatureCommandOffset == nil { commandsEnd += 16 }
        signatureCommandOffset = command; signatureStart = aligned
        linkeditFileSize = newFileSize
        data = updated
    }

    mutating func attach(signature: Data) throws {
        guard data.count == signatureStart, signature.count == existingSignature?.size else {
            throw SigningError.machO("signature does not match the prepared image")
        }
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
