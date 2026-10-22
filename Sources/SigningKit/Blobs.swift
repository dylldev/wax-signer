import CredentialKit
import CryptoKit
import Foundation

/// Code-signature container formats (big-endian). Constants follow Apple's published `cs_blobs.h`.
enum Blob {
    static let embeddedSignature: UInt32 = 0xfade0cc0
    static let codeDirectory: UInt32 = 0xfade0c02
    static let requirementSet: UInt32 = 0xfade0c01
    static let requirement: UInt32 = 0xfade0c00
    static let entitlementsXML: UInt32 = 0xfade7171
    static let entitlementsDER: UInt32 = 0xfade7172
    static let cmsWrapper: UInt32 = 0xfade0b01

    static func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]) }
    static func be64(_ v: UInt64) -> Data { be32(UInt32(v >> 32)) + be32(UInt32(v & 0xffff_ffff)) }

    static func wrap(_ magic: UInt32, _ payload: Data) -> Data {
        be32(magic) + be32(UInt32(payload.count + 8)) + payload
    }

    /// Slot types inside the embedded signature SuperBlob.
    enum Slot {
        static let codeDirectory: UInt32 = 0
        static let requirements: UInt32 = 2
        static let entitlementsXML: UInt32 = 5
        static let entitlementsDER: UInt32 = 7
        static let cms: UInt32 = 0x10000
    }

    static func superBlob(magic: UInt32, entries: [(slot: UInt32, blob: Data)]) -> Data {
        let headerSize = 12 + 8 * entries.count
        var index = Data()
        var body = Data()
        for e in entries {
            index += be32(e.slot) + be32(UInt32(headerSize + body.count))
            body += e.blob
        }
        return be32(magic) + be32(UInt32(headerSize + body.count)) + be32(UInt32(entries.count)) + index + body
    }
}

/// `identifier "<id>" and certificate root = H"<sha1 of root cert>"`, encoded as Apple's codesign does
/// for a certificate that does not chain to Apple. Chains to Apple would use `anchor apple generic`.
enum Requirements {
    static func designated(identifier: String, rootCertificateDER: Data) -> Data {
        func padded(_ d: Data) -> Data { d + Data(count: (4 - d.count % 4) % 4) }
        let id = Data(identifier.utf8)
        let sha1 = Data(Insecure.SHA1.hash(data: rootCertificateDER))
        var expr = Blob.be32(6)                                             // opAnd
        expr += Blob.be32(2) + Blob.be32(UInt32(id.count)) + padded(id)     // opIdent
        expr += Blob.be32(4) + Blob.be32(0xffff_ffff)                       // opAnchorHash, slot -1 (root)
        expr += Blob.be32(UInt32(sha1.count)) + padded(sha1)
        let requirement = Blob.wrap(Blob.requirement, Blob.be32(1) + expr)  // kind 1: expression
        return Blob.superBlob(magic: Blob.requirementSet, entries: [(3, requirement)])  // 3: designated
    }

    static let appleWWDR = "Apple Worldwide Developer Relations Certification Authority"
    static let appleRoot = "Apple Root CA"

    /// True when the chain is leaf (an Apple Development / iPhone Developer certificate), the Apple WWDR
    /// intermediate, then Apple Root CA, by subject name. Names are only used to choose the requirement
    /// form; trust is decided by iOS, never by this check.
    static func isAppleDevelopmentChain(commonNames: [String?]) -> Bool {
        guard commonNames.count >= 3, let leaf = commonNames[0] else { return false }
        return (leaf.hasPrefix("Apple Development") || leaf.hasPrefix("iPhone Developer"))
            && commonNames[1] == appleWWDR && commonNames.last == appleRoot
    }

    /// `identifier "<id>" and anchor apple generic and certificate leaf[subject.CN] = "<cn>"
    ///  and certificate 1[field.1.2.840.113635.100.6.2.1]`, laid out exactly as Xcode's codesign writes it
    /// (right-nested `and`). Verified byte-for-byte against a requirement blob Xcode produced.
    static func appleDevelopment(identifier: String, leafCommonName: String) -> Data {
        func padded(_ d: Data) -> Data { d + Data(count: (4 - d.count % 4) % 4) }
        func string(_ s: String) -> Data { let d = Data(s.utf8); return Blob.be32(UInt32(d.count)) + padded(d) }
        let wwdrMarkerOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x63, 0x64, 0x06, 0x02, 0x01]) // 1.2.840.113635.100.6.2.1
        var expr = Blob.be32(6)                                              // and
        expr += Blob.be32(2) + string(identifier)                            // identifier
        expr += Blob.be32(6) + Blob.be32(15)                                 // and, anchor apple generic
        expr += Blob.be32(6)                                                 // and
        expr += Blob.be32(11) + Blob.be32(0) + string("subject.CN")          // certificate leaf[subject.CN]
        expr += Blob.be32(1) + string(leafCommonName)                        //   = "<cn>"
        expr += Blob.be32(14) + Blob.be32(1)                                 // certificate 1[field.<oid>]
        expr += Blob.be32(UInt32(wwdrMarkerOID.count)) + padded(wwdrMarkerOID)
        expr += Blob.be32(0)                                                 //   /* exists */
        let requirement = Blob.wrap(Blob.requirement, Blob.be32(1) + expr)
        return Blob.superBlob(magic: Blob.requirementSet, entries: [(3, requirement)])
    }

    /// Chooses the designated requirement for the chain the identity supplies.
    static func designated(identifier: String, chainDER: [Data]) -> Data {
        let names = chainDER.map { CertificateSubject.commonName(of: $0) }
        if isAppleDevelopmentChain(commonNames: names), let cn = names[0] {
            return appleDevelopment(identifier: identifier, leafCommonName: cn)
        }
        return designated(identifier: identifier, rootCertificateDER: chainDER.last!)
    }
}
