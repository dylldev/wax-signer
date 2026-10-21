import Foundation

/// Minimal DER writer for CMS and DER entitlements.
enum DER {
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag] + length(content.count)) + content
    }

    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }

    /// SET OF: members sorted by encoding, as DER requires.
    static func setOf(_ items: [Data]) -> Data {
        tlv(0x31, items.sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +))
    }

    static func octetString(_ d: Data) -> Data { tlv(0x04, d) }
    static func utf8(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func boolean(_ b: Bool) -> Data { tlv(0x01, Data([b ? 0xFF : 0x00])) }
    static let null = Data([0x05, 0x00])

    /// Non-negative integers only.
    static func integer(_ v: Int) -> Data {
        var bytes: [UInt8] = []
        var n = v
        repeat { bytes.insert(UInt8(n & 0xff), at: 0); n >>= 8 } while n > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, Data(bytes))
    }

    static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").map { Int($0)! }
        var body: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for var v in parts.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(v & 0x7f)]
            v >>= 7
            while v > 0 { chunk.insert(UInt8(v & 0x7f) | 0x80, at: 0); v >>= 7 }
            body += chunk
        }
        return tlv(0x06, Data(body))
    }

    /// UTCTime, valid for years 1950-2049.
    static func utcTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(f.string(from: date).utf8))
    }
}
