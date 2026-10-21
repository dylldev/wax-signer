import Foundation

/// Universal ("fat") Mach-O files hold several architectures. An iPhone only runs one, so signing keeps the arm64
/// slice (else arm64e) and drops the rest, instead of refusing the whole app.
enum FatMachO {
    private static let cpuTypeARM64: UInt32 = 0x0100000C

    /// True when the file starts with the fat magic (stored big-endian: CA FE BA BE).
    static func isFat(_ prefix: Data) -> Bool {
        prefix.count >= 4 && Array(prefix.prefix(4)) == [0xCA, 0xFE, 0xBA, 0xBE]
    }

    /// Universal binaries Wax cannot read: the 64-bit variant (CA FE BA BF, for slices past 4 GiB) and the byte-swapped
    /// spellings. Treating one as an ordinary file would seal unsigned code as a resource, so signing stops instead.
    static func isUnsupportedFat(_ prefix: Data) -> Bool {
        guard prefix.count >= 4 else { return false }
        let magic = Array(prefix.prefix(4))
        return magic == [0xCA, 0xFE, 0xBA, 0xBF] || magic == [0xBF, 0xBA, 0xFE, 0xCA] || magic == [0xBE, 0xBA, 0xFE, 0xCA]
    }

    /// Returns the arm64 slice (cpusubtype 0), else arm64e (2); a thin file is returned unchanged.
    static func thin(_ data: Data) throws -> Data {
        if isUnsupportedFat(data) { throw SigningError.machO("this universal binary uses a format Wax cannot read, so it was not signed") }
        guard isFat(data) else { _ = try MachO(data); return data }
        guard data.count >= 8 else { throw SigningError.machO("universal binary header is cut short") }
        let count = CheckedBytes.be32(data, 4)
        guard count > 0, count <= 64, count <= (data.count - 8) / 20 else {
            throw SigningError.machO("universal binary architecture table is incomplete")
        }
        let tableEnd = 8 + count * 20
        var best: (rank: Int, cpu: UInt32, subtype: UInt32, range: Range<Int>)?
        var ranges: [Range<Int>] = []
        var architectures: Set<UInt64> = []
        for i in 0..<count {
            let base = 8 + 20 * i
            let cpu = UInt32(CheckedBytes.be32(data, base)), sub = UInt32(CheckedBytes.be32(data, base + 4))
            let off = CheckedBytes.be32(data, base + 8), size = CheckedBytes.be32(data, base + 12)
            let alignment = CheckedBytes.be32(data, base + 16)
            guard off >= tableEnd, size > 0, CheckedBytes.contains(off, size, in: data.count),
                  alignment <= 31, UInt64(off) % (UInt64(1) << alignment) == 0 else {
                throw SigningError.machO("universal binary slice has invalid bounds or alignment")
            }
            let range = off..<(off + size)
            guard !ranges.contains(where: { $0.overlaps(range) }),
                  architectures.insert(UInt64(cpu) << 32 | UInt64(sub)).inserted else {
                throw SigningError.machO("universal binary has overlapping slices or duplicate architectures")
            }
            ranges.append(range)
            guard cpu == cpuTypeARM64, [UInt32(0), 2].contains(sub & 0x00FF_FFFF) else { continue }
            let rank = sub & 0x00FF_FFFF == 0 ? 0 : 1
            if best == nil || rank < best!.rank { best = (rank, cpu, sub, range) }
        }
        guard let pick = best else { throw SigningError.machO("this universal binary has no supported arm64 slice") }
        let slice = Data(data[(data.startIndex + pick.range.lowerBound)..<(data.startIndex + pick.range.upperBound)])
        _ = try MachO(slice)
        guard slice.u32(4) == pick.cpu, slice.u32(8) == pick.subtype else {
            throw SigningError.machO("universal architecture metadata does not match its Mach-O slice")
        }
        return slice
    }

    /// Replaces every universal binary under `root` with its arm64 slice. Returns one note per file changed.
    static func thinTree(at root: URL, scratchDirectory: URL? = nil, checkpoint: () throws -> Void = {}, beforeWrite: (Int) throws -> Void = { _ in }) throws -> [String] {
        try checkpoint()
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        let base = root.resolvingSymlinksInPath().path
        let staging = (scratchDirectory ?? fm.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var validated: [(source: URL, staged: URL, attributes: [FileAttributeKey: Any])] = []
        for case let url as URL in walker {
            try checkpoint()
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard v.isRegularFile == true, v.isSymbolicLink != true else { continue }
            let handle = try FileHandle(forReadingFrom: url)
            let head: Data
            do { head = try handle.read(upToCount: 4) ?? Data(); try handle.close() }
            catch { try? handle.close(); throw error }
            if isUnsupportedFat(head) { throw SigningError.machO("unsupported universal binary: \(url.lastPathComponent)") }
            guard isFat(head) else { continue }
            let output = try thin(Data(contentsOf: url, options: .mappedIfSafe))
            let staged = staging.appendingPathComponent(String(validated.count))
            try checkpoint()
            try beforeWrite(output.count)
            try output.write(to: staged)
            validated.append((url, staged, try fm.attributesOfItem(atPath: url.path)))
        }
        var notes: [String] = []
        for item in validated {
            try checkpoint()
            let url = item.source
            let bytes = try Data(contentsOf: item.staged, options: .mappedIfSafe)
            try beforeWrite(bytes.count)
            try bytes.write(to: url, options: .atomic)
            if let mode = item.attributes[.posixPermissions] { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            notes.append("Removed unused architectures from \(full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent)")
        }
        return notes
    }
}
