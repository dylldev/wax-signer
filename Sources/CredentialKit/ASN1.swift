import Foundation

/// Minimal BER/DER reader: enough for X.509 certificates and the CMS wrapper around a provisioning profile.
/// Handles definite and indefinite lengths (Apple-issued profiles use indefinite-length BER).
public struct ASN1 {
    public struct Malformed: Error {}

    public let tag: UInt8
    public let content: [UInt8]
    private let depth: Int

    public init(tag: UInt8, content: [UInt8]) {
        self.tag = tag; self.content = content; self.depth = 0
    }

    private init(tag: UInt8, content: [UInt8], depth: Int) {
        self.tag = tag; self.content = content; self.depth = depth
    }

    private static let maxDepth = 24

    public var isConstructed: Bool { tag & 0x20 != 0 }

    /// Re-encoded with a definite length. Identical to the input for DER (certificates).
    public var encoded: Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 { out.append(UInt8(n)) } else {
            var bytes: [UInt8] = []
            var v = n
            while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
            out.append(0x80 | UInt8(bytes.count)); out.append(contentsOf: bytes)
        }
        out.append(contentsOf: content)
        return out
    }

    public static func parse(_ data: Data) throws -> ASN1 {
        var pos = 0
        return try read([UInt8](data), &pos, depth: 0)
    }

    public func children() throws -> [ASN1] {
        guard isConstructed else { throw Malformed() }
        var pos = 0
        var out: [ASN1] = []
        while pos < content.count { out.append(try Self.read(content, &pos, depth: depth + 1)) }
        return out
    }

    private static func read(_ b: [UInt8], _ pos: inout Int, depth: Int) throws -> ASN1 {
        guard depth <= maxDepth, pos + 2 <= b.count else { throw Malformed() }
        let tag = b[pos]; pos += 1
        guard tag & 0x1f != 0x1f else { throw Malformed() } // multi-byte tags are not used by anything we read
        let first = b[pos]; pos += 1

        if first == 0x80 { // indefinite length, constructed only, ends with 00 00
            guard tag & 0x20 != 0 else { throw Malformed() }
            let start = pos
            while true {
                guard pos + 2 <= b.count else { throw Malformed() }
                if b[pos] == 0, b[pos + 1] == 0 {
                    let node = ASN1(tag: tag, content: Array(b[start..<pos]), depth: depth)
                    pos += 2
                    return node
                }
                _ = try read(b, &pos, depth: depth + 1)
            }
        }

        var length = Int(first)
        if first & 0x80 != 0 {
            let n = Int(first & 0x7f)
            guard (1...4).contains(n), pos + n <= b.count else { throw Malformed() }
            length = 0
            for _ in 0..<n { length = length << 8 | Int(b[pos]); pos += 1 }
        }
        guard pos + length <= b.count else { throw Malformed() }
        let node = ASN1(tag: tag, content: Array(b[pos..<pos + length]), depth: depth)
        pos += length
        return node
    }
}
