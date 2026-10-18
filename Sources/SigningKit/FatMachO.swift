import Foundation

/// Universal ("fat") Mach-O files hold several architectures. An iPhone only runs one, so signing keeps the arm64
/// slice (else arm64e) and drops the rest, instead of refusing the whole app.
enum FatMachO {
    private static let cpuTypeARM64: UInt32 = 0x0100000C

    /// True when the file starts with the fat magic (stored big-endian: CA FE BA BE).
    static func isFat(_ prefix: Data) -> Bool {
        prefix.count >= 4 && Array(prefix.prefix(4)) == [0xCA, 0xFE, 0xBA, 0xBE]
    }

    /// Returns the arm64 slice (cpusubtype 0), else arm64e (2); a thin file is returned unchanged.
    static func thin(_ data: Data) throws -> Data {
        guard isFat(data) else { return data }
        func u32(_ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= data.count else { return nil }
            return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(data[data.startIndex + o + $1]) }
        }
        guard let count = u32(4), count > 0, count <= 64 else { throw SigningError.machO("universal binary header is not valid") }
        var best: (rank: Int, offset: Int, size: Int)?
        for i in 0..<Int(count) {
            let base = 8 + 20 * i
            guard let cpu = u32(base), let sub = u32(base + 4), let off = u32(base + 8), let size = u32(base + 12) else {
                throw SigningError.machO("universal binary header is cut short")
            }
            guard cpu == cpuTypeARM64 else { continue }
            let rank = (sub & 0x00FF_FFFF) == 0 ? 0 : ((sub & 0x00FF_FFFF) == 2 ? 1 : 2)
            if best == nil || rank < best!.rank { best = (rank, Int(off), Int(size)) }
        }
        guard let pick = best else { throw SigningError.machO("this universal binary has no arm64 slice, so it cannot run on an iPhone") }
        guard pick.offset >= 0, pick.size > 0, pick.offset + pick.size <= data.count else {
            throw SigningError.machO("universal binary slice lies outside the file")
        }
        return Data(data[(data.startIndex + pick.offset)..<(data.startIndex + pick.offset + pick.size)])
    }

    /// Replaces every universal binary under `root` with its arm64 slice. Returns one note per file changed.
    static func thinTree(at root: URL) throws -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        let base = root.resolvingSymlinksInPath().path
        var notes: [String] = []
        for case let url as URL in walker {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? handle.read(upToCount: 4)) ?? Data()
            try? handle.close()
            guard isFat(head) else { continue }
            let attrs = try fm.attributesOfItem(atPath: url.path)
            try thin(Data(contentsOf: url)).write(to: url, options: .atomic)
            if let mode = attrs[.posixPermissions] { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            notes.append("Removed unused architectures from \(full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent)")
        }
        return notes
    }
}
