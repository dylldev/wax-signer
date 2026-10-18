import Foundation

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func begin() -> UInt32 { 0xFFFF_FFFF }

    static func update(_ state: UInt32, _ data: Data) -> UInt32 {
        var c = state
        table.withUnsafeBufferPointer { t in
            data.withUnsafeBytes { raw in
                for b in raw.bindMemory(to: UInt8.self) { c = t[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
            }
        }
        return c
    }

    static func finish(_ state: UInt32) -> UInt32 { state ^ 0xFFFF_FFFF }

    static func checksum(_ data: Data) -> UInt32 { finish(update(begin(), data)) }
}
