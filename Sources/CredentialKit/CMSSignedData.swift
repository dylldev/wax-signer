import CryptoKit
import Foundation
import Security

/// Parsed CMS SignedData (RFC 5652), enough to check signatures with public Security APIs.
/// iOS has no public CMS decoder (`CMSDecoder.h` is not in the iOS SDK), so this is hand-parsed.
public struct CMSSignedData {
    public struct Signer {
        public let issuerAndSerial: Data         // DER of IssuerAndSerialNumber
        public let digestAlgorithmOID: String
        public let signatureAlgorithmOID: String
        public let signedAttributes: Data?       // re-tagged as SET (0x31), the bytes that are signed
        public let signature: Data
        public let messageDigest: Data?          // from the signed attributes
        public let signingTime: Date?
    }

    public let encapsulatedContent: Data?
    public let certificatesDER: [Data]
    public let signers: [Signer]

    public enum ParseError: Error, Equatable { case notSignedData, malformed }

    public static func parse(_ data: Data) throws -> CMSSignedData {
        do {
            let root = try ASN1.parse(data)
            let top = try root.children()
            guard root.tag == 0x30, top.count == 2, top[0].tag == 0x06, top[0].content == ASN1.oidBytes("1.2.840.113549.1.7.2"),
                  top[1].tag == 0xA0, let sd = try top[1].children().first, sd.tag == 0x30 else { throw ParseError.notSignedData }

            var parts = try sd.children()
            guard parts.count >= 4 else { throw ParseError.malformed }
            parts.removeFirst(2) // version, digestAlgorithms

            let encap = try parts.removeFirst().children()
            var content: Data?
            if encap.count == 2, encap[1].tag == 0xA0, let octets = try encap[1].children().first {
                if octets.tag == 0x04 { content = Data(octets.content) }
                else if octets.tag == 0x24 { content = Data(try octets.children().flatMap(\.content)) }
            }

            var certs: [Data] = []
            if let first = parts.first, first.tag == 0xA0 {
                certs = try first.children().map(\.encoded)
                parts.removeFirst()
            }
            if let first = parts.first, first.tag == 0xA1 { parts.removeFirst() } // CRLs, ignored
            guard let signerSet = parts.first, signerSet.tag == 0x31 else { throw ParseError.malformed }

            let signers = try signerSet.children().map(Self.parseSigner)
            return CMSSignedData(encapsulatedContent: content, certificatesDER: certs, signers: signers)
        } catch is ASN1.Malformed {
            throw ParseError.malformed
        }
    }

    private static func parseSigner(_ node: ASN1) throws -> Signer {
        var f = try node.children()
        guard f.count >= 5 else { throw ParseError.malformed }
        f.removeFirst()                                  // version
        let issuer = f.removeFirst().encoded
        let digestAlg = try f.removeFirst().children().first.map { ASN1.oidString($0.content) } ?? ""
        var attrsDER: Data?
        var digest: Data?
        var time: Date?
        if let a = f.first, a.tag == 0xA0 {
            f.removeFirst()
            var set = a.encoded
            set[set.startIndex] = 0x31
            attrsDER = set
            for attr in try a.children() {
                let kv = try attr.children()
                guard kv.count == 2, let value = try kv[1].children().first else { continue }
                switch ASN1.oidString(kv[0].content) {
                case "1.2.840.113549.1.9.4": digest = Data(value.content)
                case "1.2.840.113549.1.9.5": time = utcDate(value)
                default: break
                }
            }
        }
        guard f.count >= 2 else { throw ParseError.malformed }
        let sigAlg = try f.removeFirst().children().first.map { ASN1.oidString($0.content) } ?? ""
        let sig = Data(f.removeFirst().content)
        return Signer(issuerAndSerial: issuer, digestAlgorithmOID: digestAlg, signatureAlgorithmOID: sigAlg,
                      signedAttributes: attrsDER, signature: sig, messageDigest: digest, signingTime: time)
    }

    // MARK: Cryptographic check (not trust)

    public enum SignatureCheck: Equatable {
        case valid
        case invalid(String)
    }

    /// Checks the digest and the RSA signature of `signer` with the Security framework.
    /// This establishes that the content was signed by the key in the embedded certificate.
    /// It says nothing about who that certificate belongs to. See `ProfileTrust` for that.
    public func checkSignature(of index: Int = 0, content override: Data? = nil) -> SignatureCheck {
        guard signers.indices.contains(index) else { return .invalid("no signer") }
        let signer = signers[index]
        guard let content = override ?? encapsulatedContent else { return .invalid("no content to verify") }

        guard let certDER = signerCertificateDER(signer), let cert = SecCertificateCreateWithData(nil, certDER as CFData),
              let key = SecCertificateCopyKey(cert) else { return .invalid("signer certificate not found in the message") }

        let signed: Data
        if let attrs = signer.signedAttributes {
            guard let expected = Self.digest(content, oid: signer.digestAlgorithmOID) else {
                return .invalid("unsupported digest algorithm \(signer.digestAlgorithmOID)")
            }
            guard signer.messageDigest == expected else { return .invalid("message digest does not match the content") }
            signed = attrs
        } else {
            signed = content
        }

        guard let algorithm = Self.rsaAlgorithm(digestOID: signer.digestAlgorithmOID) else {
            return .invalid("unsupported digest algorithm \(signer.digestAlgorithmOID)")
        }
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(key, algorithm, signed as CFData, signer.signature as CFData, &error)
        return ok ? .valid : .invalid("signature does not verify")
    }

    public func signerCertificateDER(_ signer: Signer) -> Data? {
        for der in certificatesDER {
            guard let cert = try? ASN1.parse(der), let tbs = try? cert.children().first, var f = try? tbs.children() else { continue }
            if f.first?.tag == 0xA0 { f.removeFirst() }
            guard f.count >= 3 else { continue }
            let ias = DERHelper.sequence([f[2].encoded, f[0].encoded])
            if ias == signer.issuerAndSerial { return der }
        }
        return nil
    }

    // MARK: Helpers

    private static func digest(_ data: Data, oid: String) -> Data? {
        switch oid {
        case "1.3.14.3.2.26": return Data(Insecure.SHA1.hash(data: data))
        case "2.16.840.1.101.3.4.2.1": return Data(SHA256.hash(data: data))
        case "2.16.840.1.101.3.4.2.2": return Data(SHA384.hash(data: data))
        case "2.16.840.1.101.3.4.2.3": return Data(SHA512.hash(data: data))
        default: return nil
        }
    }

    private static func rsaAlgorithm(digestOID: String) -> SecKeyAlgorithm? {
        switch digestOID {
        case "1.3.14.3.2.26": return .rsaSignatureMessagePKCS1v15SHA1
        case "2.16.840.1.101.3.4.2.1": return .rsaSignatureMessagePKCS1v15SHA256
        case "2.16.840.1.101.3.4.2.2": return .rsaSignatureMessagePKCS1v15SHA384
        case "2.16.840.1.101.3.4.2.3": return .rsaSignatureMessagePKCS1v15SHA512
        default: return nil
        }
    }

    private static func utcDate(_ n: ASN1) -> Date? {
        guard n.tag == 0x17 || n.tag == 0x18, let s = String(bytes: n.content, encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = n.tag == 0x17 ? (s.count == 13 ? "yyMMddHHmmss'Z'" : "yyMMddHHmm'Z'") : "yyyyMMddHHmmss'Z'"
        return f.date(from: s)
    }
}

private enum DERHelper {
    static func sequence(_ items: [Data]) -> Data {
        var body = Data(); items.forEach { body.append($0) }
        return ASN1(tag: 0x30, content: [UInt8](body)).encoded
    }
}
