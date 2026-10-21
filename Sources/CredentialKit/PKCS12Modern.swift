import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Reads PKCS#12 files that Apple's importer will not open, and re-encodes them in the classic format it does.
///
/// Why: iOS's `SecPKCS12Import` reports "wrong password" or "cannot decode" for some valid files (observed with a
/// distribution certificate that other apps open). Wax therefore checks the file's own MAC with the typed password:
/// if the MAC fails, the password really is wrong; if it passes, the password is right and the file is re-encoded
/// (3DES + SHA-1 MAC, like `openssl pkcs12 -legacy`) in memory and handed back to Apple's importer.
/// Keys exist only in memory here; nothing is written anywhere.

// MARK: - Hash plumbing

enum PKCS12Hash {
    case sha1, sha256, sha384, sha512

    init?(oid: String) {
        switch oid {
        case "1.3.14.3.2.26": self = .sha1
        case "2.16.840.1.101.3.4.2.1": self = .sha256
        case "2.16.840.1.101.3.4.2.2": self = .sha384
        case "2.16.840.1.101.3.4.2.3": self = .sha512
        default: return nil
        }
    }

    var u: Int { switch self { case .sha1: 20; case .sha256: 32; case .sha384: 48; case .sha512: 64 } }
    var v: Int { switch self { case .sha1, .sha256: 64; case .sha384, .sha512: 128 } }

    func digest(_ d: [UInt8]) -> [UInt8] {
        switch self {
        case .sha1: return Array(Insecure.SHA1.hash(data: d))
        case .sha256: return Array(SHA256.hash(data: d))
        case .sha384: return Array(SHA384.hash(data: d))
        case .sha512: return Array(SHA512.hash(data: d))
        }
    }

    func hmac(key: [UInt8], data: [UInt8]) -> [UInt8] {
        let k = SymmetricKey(data: key)
        switch self {
        case .sha1: return Array(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: k))
        case .sha256: return Array(HMAC<SHA256>.authenticationCode(for: data, using: k))
        case .sha384: return Array(HMAC<SHA384>.authenticationCode(for: data, using: k))
        case .sha512: return Array(HMAC<SHA512>.authenticationCode(for: data, using: k))
        }
    }
}

/// RFC 7292 appendix B.2 key derivation (not PBKDF2). `password` is the already-encoded password bytes.
enum PKCS12KDF {
    enum InvalidIterations: Error { case outOfRange }
    static let maxIterations = 5_000_000

    static func derive(password: [UInt8], salt: [UInt8], iterations: Int, id: UInt8, length n: Int, hash: PKCS12Hash) throws -> [UInt8] {
        guard (1...maxIterations).contains(iterations) else { throw InvalidIterations.outOfRange }
        let u = hash.u, v = hash.v
        func fill(_ x: [UInt8]) -> [UInt8] {
            guard !x.isEmpty else { return [] }
            let total = v * ((x.count + v - 1) / v)
            return (0..<total).map { x[$0 % x.count] }
        }
        var I = fill(salt) + fill(password)
        let D = [UInt8](repeating: id, count: v)
        var out: [UInt8] = []
        while out.count < n {
            var A = hash.digest(D + I)
            if iterations > 1 { for _ in 1..<iterations { A = hash.digest(A) } }
            out += A
            if out.count >= n { break }
            let B = (0..<v).map { A[$0 % u] }
            for j in 0..<(I.count / v) {
                var carry = 1
                for k in stride(from: v - 1, through: 0, by: -1) {
                    let s = Int(I[j * v + k]) + Int(B[k]) + carry
                    I[j * v + k] = UInt8(s & 0xff); carry = s >> 8
                }
            }
        }
        return Array(out.prefix(n))
    }
}

// MARK: - Minimal DER building

enum DER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { Array(ASN1(tag: tag, content: content).encoded) }
    static func seq(_ parts: [[UInt8]]) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func set(_ parts: [[UInt8]]) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }
    static func octet(_ b: [UInt8]) -> [UInt8] { tlv(0x04, b) }
    static func ctx(_ n: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xA0 | n, content) }
    static let null: [UInt8] = [0x05, 0x00]

    static func int(_ v: Int) -> [UInt8] {
        var b: [UInt8] = []; var x = v
        repeat { b.insert(UInt8(x & 0xff), at: 0); x >>= 8 } while x > 0
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, b)
    }

    static func oid(_ dotted: String) -> [UInt8] { tlv(0x06, ASN1.oidBytes(dotted)) }
}


// MARK: - Assessment

enum PKCS12Assessment {
    /// The file's own MAC does not match this password.
    case wrongPassword
    /// Password is right; the same identity re-encoded in the classic format.
    case legacyEquivalent(Data)
    /// Not something this fallback can read (classic format, unsupported algorithm, or damaged).
    case unsupported
}

enum ModernPKCS12 {
    private struct Unsupported: Error {}
    private struct BadPassword: Error {}

    private enum OID {
        static let data = "1.2.840.113549.1.7.1"
        static let encryptedData = "1.2.840.113549.1.7.6"
        static let keyBag = "1.2.840.113549.1.12.10.1.1"
        static let shroudedKeyBag = "1.2.840.113549.1.12.10.1.2"
        static let certBag = "1.2.840.113549.1.12.10.1.3"
        static let x509Cert = "1.2.840.113549.1.9.22.1"
        static let localKeyID = "1.2.840.113549.1.9.21"
        static let pbes2 = "1.2.840.113549.1.5.13"
        static let pbkdf2 = "1.2.840.113549.1.5.12"
        static let pbe3DES = "1.2.840.113549.1.12.1.3"
        static let sha1 = "1.3.14.3.2.26"
    }

    private struct Contents {
        var certs: [(der: [UInt8], keyID: [UInt8]?)] = []
        var keys: [(pkcs8: [UInt8], keyID: [UInt8]?)] = []
    }

    static func assess(_ data: Data, password: String) -> PKCS12Assessment {
        do {
            let contents = try read(data, password: password)
            guard !contents.keys.isEmpty, !contents.certs.isEmpty else { return .unsupported }
            return .legacyEquivalent(try encodeClassic(contents, password: password))
        } catch is BadPassword { return .wrongPassword } catch { return .unsupported }
    }

    // MARK: reading

    private static func passwordCandidates(_ pw: String) -> [[UInt8]] {
        var bmp: [UInt8] = []
        for u in pw.utf16 { bmp += [UInt8(u >> 8), UInt8(u & 0xff)] }
        var c: [[UInt8]] = [bmp + [0, 0]]
        if pw.isEmpty { c.append([]) }
        c.append(Array(pw.utf8))
        return c
    }

    private static func read(_ data: Data, password: String) throws -> Contents {
        guard let pfx = try? ASN1.parse(data), pfx.tag == 0x30, let top = try? pfx.children(), top.count >= 3,
              top[0].intValue == 3, top[1].tag == 0x30, top[2].tag == 0x30,
              let authSafe = try? top[1].children(), authSafe.count == 2, authSafe[0].oidString == OID.data,
              let wrapped = try? authSafe[1].children(), wrapped.count == 1, wrapped[0].tag == 0x04
        else { throw Unsupported() }
        let authBytes = wrapped[0].content

        // MAC
        guard let mac = try? top[2].children(), mac.count >= 2, let di = try? mac[0].children(), di.count == 2,
              let alg = try? di[0].children(), let hOID = alg.first?.oidString, let hash = PKCS12Hash(oid: hOID),
              di[1].tag == 0x04, mac[1].tag == 0x04
        else { throw Unsupported() }
        let iterations = mac.count > 2 ? (mac[2].intValue ?? 1) : 1
        guard iterations <= PKCS12KDF.maxIterations else { throw Unsupported() }
        var matched = false
        for cand in passwordCandidates(password) {
            let key = try PKCS12KDF.derive(password: cand, salt: mac[1].content, iterations: iterations, id: 3, length: hash.u, hash: hash)
            if hash.hmac(key: key, data: authBytes) == di[1].content { matched = true; break }
        }
        guard matched else { throw BadPassword() }

        // Contents (decrypting with whichever encoding of the password matched)
        guard let infos = try? ASN1.parse(Data(authBytes)).children() else { throw Unsupported() }
        var out = Contents()
        for info in infos {
            guard let parts = try? info.children(), parts.count == 2, let type = parts[0].oidString,
                  let inner = try? parts[1].children(), inner.count == 1 else { throw Unsupported() }
            let safeContents: [UInt8]
            switch type {
            case OID.data:
                guard inner[0].tag == 0x04 else { throw Unsupported() }
                safeContents = inner[0].content
            case OID.encryptedData:
                guard let ed = try? inner[0].children(), ed.count == 2, let eci = try? ed[1].children(), eci.count == 3,
                      let alg = try? eci[1].children(), eci[2].tag == 0x80 || eci[2].tag == 0xA0 else { throw Unsupported() }
                safeContents = try decrypt(alg: alg, ciphertext: eci[2].content, password: password)
            default: throw Unsupported()
            }
            try collectBags(safeContents, password: password, into: &out)
        }
        return out
    }

    private static func collectBags(_ safeContents: [UInt8], password: String, into out: inout Contents) throws {
        guard let bags = try? ASN1.parse(Data(safeContents)).children() else { throw Unsupported() }
        for bag in bags {
            guard let parts = try? bag.children(), parts.count >= 2, let id = parts[0].oidString,
                  let valueWrap = try? parts[1].children(), valueWrap.count == 1 else { throw Unsupported() }
            var keyID: [UInt8]?
            if parts.count > 2, let attrs = try? parts[2].children() {
                for a in attrs {
                    if let kv = try? a.children(), kv.count == 2, kv[0].oidString == OID.localKeyID,
                       let vals = try? kv[1].children(), let v = vals.first, v.tag == 0x04 { keyID = v.content }
                }
            }
            switch id {
            case OID.certBag:
                guard let cb = try? valueWrap[0].children(), cb.count == 2, cb[0].oidString == OID.x509Cert,
                      let der = try? cb[1].children(), der.count == 1, der[0].tag == 0x04 else { throw Unsupported() }
                out.certs.append((der[0].content, keyID))
            case OID.shroudedKeyBag:
                guard let epki = try? valueWrap[0].children(), epki.count == 2, let alg = try? epki[0].children(),
                      epki[1].tag == 0x04 else { throw Unsupported() }
                out.keys.append((try decrypt(alg: alg, ciphertext: epki[1].content, password: password), keyID))
            case OID.keyBag:
                out.keys.append((Array(valueWrap[0].encoded), keyID))
            default: continue
            }
        }
    }

    // MARK: PBES2 and classic PBE decryption

    private static func decrypt(alg: [ASN1], ciphertext: [UInt8], password: String) throws -> [UInt8] {
        guard let oid = alg.first?.oidString, alg.count == 2 else { throw Unsupported() }
        if oid == OID.pbes2 {
            guard let p = try? alg[1].children(), p.count == 2, let kdf = try? p[0].children(), kdf.count == 2,
                  kdf[0].oidString == OID.pbkdf2, let kp = try? kdf[1].children(), kp.count >= 2, kp[0].tag == 0x04,
                  let iter = kp[1].intValue, iter > 0, iter <= PKCS12KDF.maxIterations, let enc = try? p[1].children(), enc.count == 2,
                  let encOID = enc[0].oidString, enc[1].tag == 0x04
            else { throw Unsupported() }
            var prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            var keyLen: Int?
            for extra in kp.dropFirst(2) {
                if extra.tag == 0x02 { keyLen = extra.intValue }
                else if extra.tag == 0x30, let a = try? extra.children(), let o = a.first?.oidString {
                    switch o {
                    case "1.2.840.113549.2.7": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
                    case "1.2.840.113549.2.8": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
                    case "1.2.840.113549.2.9": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
                    case "1.2.840.113549.2.10": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
                    case "1.2.840.113549.2.11": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
                    default: throw Unsupported()
                    }
                }
            }
            let (algo, size): (Int, Int)
            switch encOID {
            case "2.16.840.1.101.3.4.1.2": (algo, size) = (kCCAlgorithmAES, 16)
            case "2.16.840.1.101.3.4.1.22": (algo, size) = (kCCAlgorithmAES, 24)
            case "2.16.840.1.101.3.4.1.42": (algo, size) = (kCCAlgorithmAES, 32)
            case "1.2.840.113549.3.7": (algo, size) = (kCCAlgorithm3DES, 24)
            default: throw Unsupported()
            }
            if let keyLen, keyLen != size { throw Unsupported() }
            var key = [UInt8](repeating: 0, count: size)
            let passwordByteCount = password.utf8.count
            let rc = password.withCString { passwordPointer in
                kp[0].content.withUnsafeBufferPointer { sp in
                    key.withUnsafeMutableBufferPointer { kptr in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordPointer, passwordByteCount,
                                             sp.baseAddress, sp.count, prf, UInt32(iter), kptr.baseAddress, size)
                    }
                }
            }
            guard rc == kCCSuccess else { throw Unsupported() }
            return try crypt(CCOperation(kCCDecrypt), algo, key: key, iv: enc[1].content, data: ciphertext)
        }
        // Classic PKCS#12 PBE with 3-key 3DES (the format Apple's own tools write).
        if oid == OID.pbe3DES {
            guard let p = try? alg[1].children(), p.count == 2, p[0].tag == 0x04, let iter = p[1].intValue,
                  (1...PKCS12KDF.maxIterations).contains(iter) else { throw Unsupported() }
            for cand in passwordCandidates(password) {
                let key = try PKCS12KDF.derive(password: cand, salt: p[0].content, iterations: iter, id: 1, length: 24, hash: .sha1)
                let iv = try PKCS12KDF.derive(password: cand, salt: p[0].content, iterations: iter, id: 2, length: 8, hash: .sha1)
                if let pt = try? crypt(CCOperation(kCCDecrypt), kCCAlgorithm3DES, key: key, iv: iv, data: ciphertext) { return pt }
            }
        }
        throw Unsupported()
    }

    private static func crypt(_ op: CCOperation, _ algo: Int, key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> [UInt8] {
        let block = algo == kCCAlgorithmAES ? kCCBlockSizeAES128 : kCCBlockSize3DES
        guard iv.count == block else { throw Unsupported() }
        var out = [UInt8](repeating: 0, count: data.count + block)
        var moved = 0
        let rc = CCCrypt(op, CCAlgorithm(algo), CCOptions(kCCOptionPKCS7Padding), key, key.count, iv, data, data.count,
                         &out, out.count, &moved)
        guard rc == kCCSuccess else { throw Unsupported() }
        return Array(out.prefix(moved))
    }

    // MARK: writing the classic format

    private static func random(_ n: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b
    }

    private static func encodeClassic(_ c: Contents, password: String) throws -> Data {
        let pw = passwordCandidates(password)[0]
        let iterations = 2048
        func pbe(_ plain: [UInt8]) throws -> (alg: [UInt8], cipher: [UInt8]) {
            let salt = random(8)
            let key = try PKCS12KDF.derive(password: pw, salt: salt, iterations: iterations, id: 1, length: 24, hash: .sha1)
            let iv = try PKCS12KDF.derive(password: pw, salt: salt, iterations: iterations, id: 2, length: 8, hash: .sha1)
            let cipher = try crypt(CCOperation(kCCEncrypt), kCCAlgorithm3DES, key: key, iv: iv, data: plain)
            return (DER.seq([DER.oid(OID.pbe3DES), DER.seq([DER.octet(salt), DER.int(iterations)])]), cipher)
        }
        func attrs(_ keyID: [UInt8]?) -> [[UInt8]] {
            guard let keyID else { return [] }
            return [DER.set([DER.seq([DER.oid(OID.localKeyID), DER.set([DER.octet(keyID)])])])]
        }

        let certBags = c.certs.map { cert in
            DER.seq([DER.oid(OID.certBag),
                     DER.ctx(0, DER.seq([DER.oid(OID.x509Cert), DER.ctx(0, DER.octet(cert.der))]))] + attrs(cert.keyID))
        }
        let certEnc = try pbe(DER.seq(certBags))
        let encryptedData = DER.seq([DER.oid(OID.encryptedData), DER.ctx(0, DER.seq([
            DER.int(0), DER.seq([DER.oid(OID.data), certEnc.alg, DER.tlv(0x80, certEnc.cipher)])]))])

        let keyBags = try c.keys.map { key -> [UInt8] in
            let enc = try pbe(key.pkcs8)
            return DER.seq([DER.oid(OID.shroudedKeyBag),
                            DER.ctx(0, DER.seq([enc.alg, DER.octet(enc.cipher)]))] + attrs(key.keyID))
        }
        let keyData = DER.seq([DER.oid(OID.data), DER.ctx(0, DER.octet(DER.seq(keyBags)))])

        let authSafe = DER.seq([encryptedData, keyData])
        let macSalt = random(8)
        let macKey = try PKCS12KDF.derive(password: pw, salt: macSalt, iterations: iterations, id: 3, length: 20, hash: .sha1)
        let digest = PKCS12Hash.sha1.hmac(key: macKey, data: authSafe)
        return Data(DER.seq([
            DER.int(3),
            DER.seq([DER.oid(OID.data), DER.ctx(0, DER.octet(authSafe))]),
            DER.seq([DER.seq([DER.seq([DER.oid(OID.sha1), DER.null]), DER.octet(digest)]), DER.octet(macSalt), DER.int(iterations)]),
        ]))
    }
}
