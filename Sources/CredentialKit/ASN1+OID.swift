import Foundation

extension ASN1 {
    /// Dotted form of DER OID content bytes. Empty input yields "".
    static func oidString(_ b: [UInt8]) -> String {
        guard let first = b.first else { return "" }
        var parts = [Int(first) / 40, Int(first) % 40]
        var v = 0
        for byte in b.dropFirst() {
            v = v << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 { parts.append(v); v = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    /// DER OID content bytes for a dotted string. Malformed input yields [].
    static func oidBytes(_ dotted: String) -> [UInt8] {
        let p = dotted.split(separator: ".").compactMap { Int($0) }
        guard p.count >= 2 else { return [] }
        var out: [UInt8] = [UInt8(p[0] * 40 + p[1])]
        for var v in p.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(v & 0x7f)]
            v >>= 7
            while v > 0 { chunk.insert(UInt8(v & 0x7f) | 0x80, at: 0); v >>= 7 }
            out += chunk
        }
        return out
    }

    /// Dotted form when this node is an OID node.
    var oidString: String? {
        guard tag == 0x06, !content.isEmpty else { return nil }
        return ASN1.oidString(content)
    }

    /// Small non-negative integer content.
    var intValue: Int? {
        guard tag == 0x02, content.count <= 4 else { return nil }
        return content.reduce(0) { $0 << 8 | Int($1) }
    }
}
