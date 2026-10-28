import CredentialKit
import CryptoKit
import Foundation

/// Builds the detached CMS SignedData Apple code signatures carry (slot 0x10000), laid out as
/// Apple's `codesign` produces it: contentType, signingTime, messageDigest, and the two Apple
/// cdhash attributes. Signing uses `CodeSigningIdentity`, so no key material is handled here.
enum CMS {
    static func detachedSignature(over codeDirectory: Data, identity: CodeSigningIdentity, now: Date) throws -> Data {
        guard let leafDER = identity.certificateChainDER.first,
              let leaf = try? ASN1.parse(leafDER), let tbs = try? leaf.children().first,
              var fields = try? tbs.children() else { throw SigningError.bundle("signing certificate is unreadable") }
        if fields.first?.tag == 0xA0 { fields.removeFirst() }
        guard fields.count >= 3 else { throw SigningError.bundle("signing certificate is unreadable") }
        let serial = fields[0].encoded
        let issuer = fields[2].encoded

        let digest = Data(SHA256.hash(data: codeDirectory))
        let cdhash = digest.prefix(20)
        let cdhashPlist = try PropertyListSerialization.data(
            fromPropertyList: ["cdhashes": [Data(cdhash)]], format: .xml, options: 0)

        let sha256OID = "2.16.840.1.101.3.4.2.1"
        func attr(_ oid: String, _ value: Data) -> Data { DER.sequence([DER.oid(oid), DER.setOf([value])]) }
        let attributes = [
            attr("1.2.840.113549.1.9.3", DER.oid("1.2.840.113549.1.7.1")),                  // contentType: data
            attr("1.2.840.113549.1.9.5", DER.utcTime(now)),                                  // signingTime
            attr("1.2.840.113549.1.9.4", DER.octetString(digest)),                           // messageDigest
            attr("1.2.840.113635.100.9.2", DER.sequence([DER.oid(sha256OID), DER.octetString(digest)])),
            attr("1.2.840.113635.100.9.1", DER.octetString(cdhashPlist)),
        ]
        let attributeSet = DER.setOf(attributes)            // tag 0x31: the bytes that are signed
        let signature = try identity.signRSAPKCS1SHA256(attributeSet)

        let sha256Alg = DER.sequence([DER.oid(sha256OID), DER.null])
        var implicitAttributes = attributeSet
        implicitAttributes[implicitAttributes.startIndex] = 0xA0 // [0] IMPLICIT, same content

        let signerInfo = DER.sequence([
            DER.integer(1),
            DER.sequence([issuer, serial]),
            sha256Alg,
            implicitAttributes,
            DER.sequence([DER.oid("1.2.840.113549.1.1.1"), DER.null]),   // rsaEncryption
            DER.octetString(signature),
        ])

        let certificates = DER.tlv(0xA0, identity.certificateChainDER.reduce(Data(), +))
        let signedData = DER.sequence([
            DER.integer(1),
            DER.setOf([sha256Alg]),
            DER.sequence([DER.oid("1.2.840.113549.1.7.1")]),                // detached: no content
            certificates,
            DER.setOf([signerInfo]),
        ])
        return DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xA0, signedData)])
    }
}
