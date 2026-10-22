import Foundation

enum CRC32 {
    /// Eight tables, so the loop below can fold eight bytes per step ("slice by 8"). Table 0 is the usual one-byte table.
    private static let tables: [[UInt32]] = {
        var t = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 8)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            t[0][i] = c
        }
        for i in 0..<256 {
            for s in 1..<8 { t[s][i] = (t[s - 1][i] >> 8) ^ t[0][Int(t[s - 1][i] & 0xff)] }
        }
        return t
    }()
    /// One flat copy of the tables: 8 * 256 entries, table `s` starting at `s * 256`.
    private static let flat: [UInt32] = tables.flatMap { $0 }

    static func begin() -> UInt32 { 0xFFFF_FFFF }

    static func update(_ state: UInt32, _ data: Data) -> UInt32 {
        var c = state
        flat.withUnsafeBufferPointer { t in
            data.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self)
                var i = 0
                let n = p.count
                // Eight bytes at a time. Read byte by byte (not as a UInt64) so alignment never matters.
                while i + 8 <= n {
                    let lo = c ^ (UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24)
                    c = t[7 * 256 + Int(lo & 0xff)] ^ t[6 * 256 + Int((lo >> 8) & 0xff)]
                        ^ t[5 * 256 + Int((lo >> 16) & 0xff)] ^ t[4 * 256 + Int(lo >> 24)]
                        ^ t[3 * 256 + Int(p[i + 4])] ^ t[2 * 256 + Int(p[i + 5])]
                        ^ t[1 * 256 + Int(p[i + 6])] ^ t[Int(p[i + 7])]
                    i += 8
                }
                while i < n { c = t[Int((c ^ UInt32(p[i])) & 0xff)] ^ (c >> 8); i += 1 }
            }
        }
        return c
    }

    static func finish(_ state: UInt32) -> UInt32 { state ^ 0xFFFF_FFFF }

    static func checksum(_ data: Data) -> UInt32 { finish(update(begin(), data)) }
}
