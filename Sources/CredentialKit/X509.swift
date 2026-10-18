import CryptoKit
import Foundation

/// The few X.509 fields we need. iOS has no public API for validity dates or subject RDNs.
struct X509Summary {
    var commonName: String?
    var organization: String?
    var organizationalUnit: String?
    var country: String?
    var serial: [UInt8]
    var notBefore: Date
    var notAfter: Date

    static func parse(der: Data) throws -> X509Summary {
        let cert = try ASN1.parse(der)
        guard cert.tag == 0x30, let tbs = try cert.children().first, tbs.tag == 0x30 else { throw ASN1.Malformed() }
        var f = try tbs.children()
        if f.first?.tag == 0xA0 { f.removeFirst() }            // [0] version
        // serial, signature, issuer, validity, subject
        guard f.count >= 5, f[0].tag == 0x02, f[3].tag == 0x30, f[4].tag == 0x30 else { throw ASN1.Malformed() }
        let validity = try f[3].children()
        guard validity.count == 2 else { throw ASN1.Malformed() }

        var s = X509Summary(serial: f[0].content, notBefore: try Self.time(validity[0]),
                            notAfter: try Self.time(validity[1]))
        for rdn in try f[4].children() {
            for atv in try rdn.children() {
                let parts = try atv.children()
                guard parts.count == 2, parts[0].tag == 0x06, let text = Self.string(parts[1]) else { continue }
                switch Self.oid(parts[0].content) {
                case "2.5.4.3": s.commonName = s.commonName ?? text
                case "2.5.4.10": s.organization = s.organization ?? text
                case "2.5.4.11": s.organizationalUnit = s.organizationalUnit ?? text
                case "2.5.4.6": s.country = s.country ?? text
                default: break
                }
            }
        }
        return s
    }

    static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    private static func oid(_ b: [UInt8]) -> String {
        guard let first = b.first else { return "" }
        var parts = [Int(first) / 40, Int(first) % 40]
        var v = 0
        for byte in b.dropFirst() {
            v = v << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 { parts.append(v); v = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    private static func string(_ n: ASN1) -> String? {
        switch n.tag {
        case 0x0C: return String(bytes: n.content, encoding: .utf8)
        case 0x13, 0x16: return String(bytes: n.content, encoding: .ascii)
        case 0x14: return String(bytes: n.content, encoding: .isoLatin1)
        case 0x1E: return String(bytes: n.content, encoding: .utf16BigEndian)
        default: return nil
        }
    }

    private static func time(_ n: ASN1) throws -> Date {
        guard let text = String(bytes: n.content, encoding: .ascii), text.hasSuffix("Z") else { throw ASN1.Malformed() }
        let digits = Array(text.dropLast())
        guard digits.allSatisfy(\.isNumber) else { throw ASN1.Malformed() }
        let d = digits.map { Int(String($0))! }
        func num(_ r: Range<Int>) -> Int { d[r].reduce(0) { $0 * 10 + $1 } }
        var c = DateComponents()
        switch (n.tag, d.count) {
        case (0x17, 10), (0x17, 12): // UTCTime YYMMDDHHMM[SS]
            let yy = num(0..<2)
            c.year = yy >= 50 ? 1900 + yy : 2000 + yy
            c.month = num(2..<4); c.day = num(4..<6); c.hour = num(6..<8); c.minute = num(8..<10)
            c.second = d.count == 12 ? num(10..<12) : 0
        case (0x18, 14): // GeneralizedTime YYYYMMDDHHMMSS
            c.year = num(0..<4); c.month = num(4..<6); c.day = num(6..<8)
            c.hour = num(8..<10); c.minute = num(10..<12); c.second = num(12..<14)
        default: throw ASN1.Malformed()
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: c) else { throw ASN1.Malformed() }
        return date
    }
}
