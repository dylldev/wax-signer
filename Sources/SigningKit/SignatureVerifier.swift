import CredentialKit
import CryptoKit
import Foundation
import IPAKit

public struct VerificationCheck: Equatable {
    public let name: String
    public let passed: Bool
    public let detail: String
}

public struct VerificationReport: Equatable {
    public var checks: [VerificationCheck] = []
    /// SHA-1 (uppercase hex) of every signer certificate seen, once each.
    public var signerSHA1s: [String] = []
    public var passed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }
    public var failures: [VerificationCheck] { checks.filter { !$0.passed } }

    mutating func record(_ name: String, _ ok: Bool, _ detail: String = "") {
        checks.append(VerificationCheck(name: name, passed: ok, detail: detail))
    }
}

/// Re-reads a signed bundle from disk and checks it against itself: CodeDirectory page hashes, special
/// slots, the CMS signature over the CodeDirectory, entitlement blobs, and the resource seal.
///
/// This is a SELF-CHECK. It shares our understanding of the format and does not replace Apple's
/// verifier (macOS `codesign`, or the device). It does not evaluate certificate trust, the provisioning
/// profile, revocation or entitlement approval. It exists so iOS, which has no `codesign`, can still
/// detect a signature that does not match its own contents.
public enum SignatureVerifier {
    /// - `expectedSignerSHA1`: if given, every signature must be made by exactly this certificate
    ///   (uppercase hex SHA-1 of its DER). Without it the report lists the signers but does not judge them.
    public static func verifyBundle(at bundle: URL, expectedSignerSHA1: String? = nil) -> VerificationReport {
        var report = VerificationReport()
        var covered = Set<String>()
        verify(bundle: bundle, label: bundle.lastPathComponent, expected: expectedSignerSHA1, covered: &covered, into: &report)
        reportUncoveredCode(in: bundle, covered: covered, into: &report)
        return report
    }

    private static func key(_ url: URL) -> String { FileKey.of(url) }

    /// Any Mach-O file that none of the checks above looked at is code the signature does not vouch for.
    private static func reportUncoveredCode(in bundle: URL, covered: Set<String>, into report: inout VerificationReport) {
        let root = bundle.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                                          options: []) else { return }
        for case let url as URL in walker {
            guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  v.isRegularFile == true, v.isSymbolicLink != true,
                  let h = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? h.read(upToCount: 4)) ?? Data()
            try? h.close()
            guard MachO.looksLikeMachO(head), !covered.contains(key(url)) else { continue }
            let rel = String(key(url).dropFirst(root.count + 1))
            report.record("\(rel) is covered by a verified signature", false,
                          "Mach-O file in a location that is neither a bundle executable nor a container dylib")
        }
    }

    private static func verify(bundle: URL, label: String, expected: String?, covered: inout Set<String>,
                               into report: inout VerificationReport) {
        let fm = FileManager.default
        guard let infoData = try? Data(contentsOf: bundle.appendingPathComponent("Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let exeName = info["CFBundleExecutable"] as? String else {
            report.record("\(label): Info.plist", false, "missing, unreadable or without CFBundleExecutable")
            return
        }
        let sealURL = bundle.appendingPathComponent("_CodeSignature/CodeResources")
        let sealData = try? Data(contentsOf: sealURL)

        let exe = bundle.appendingPathComponent(exeName)
        covered.insert(key(exe))
        verifyExecutable(exe, label: label, infoPlist: infoData, codeResources: sealData, expected: expected, into: &report)

        // Resource seal: rebuild it from what is on disk and require it to match the stored one.
        if let sealData, let stored = try? PropertyListSerialization.propertyList(from: sealData, format: nil) as? [String: Any],
           let rebuilt = try? CodeResources.build(bundleRoot: bundle, executable: exeName),
           let fresh = try? PropertyListSerialization.propertyList(from: rebuilt, format: nil) as? [String: Any] {
            let same = (stored["files"] as? NSDictionary) == (fresh["files"] as? NSDictionary)
                && (stored["files2"] as? NSDictionary) == (fresh["files2"] as? NSDictionary)
            report.record("\(label): resource seal matches files on disk", same,
                          same ? "" : "a sealed file was changed, added or removed")
        } else {
            report.record("\(label): resource seal", false, "CodeResources missing or unreadable")
        }

        for container in BundleLayout.containers {
            let dir = bundle.appendingPathComponent(container)
            let items = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.path < $1.path }
            for item in items {
                if ["framework", "appex", "app"].contains(item.pathExtension), BundleLayout.isLink(item) {
                    report.record("\(label)/\(container)/\(item.lastPathComponent): nested bundle", false, "is a symbolic link, not a bundle folder")
                    continue
                }
                switch item.pathExtension {
                case "framework", "appex", "app":
                    verify(bundle: item, label: "\(label)/\(container)/\(item.lastPathComponent)", expected: expected,
                           covered: &covered, into: &report)
                case "dylib":
                    covered.insert(key(item))
                    verifyExecutable(item, label: "\(label)/\(container)/\(item.lastPathComponent)", infoPlist: nil,
                                     codeResources: nil, expected: expected, into: &report)
                default: break
                }
            }
        }
    }

    private static let expectedSlots: Set<Int> = [0, 2, 5, 7, 0x10000]

    static func verifyExecutable(_ url: URL, label: String, infoPlist: Data?, codeResources: Data?, expected: String? = nil,
                                 into report: inout VerificationReport) {
        let name = "\(label): \(url.lastPathComponent)"
        guard let file = try? Data(contentsOf: url), let macho = try? MachO(file) else {
            report.record("\(name) is a readable Mach-O", false, "")
            return
        }
        guard let sig = macho.existingSignature, CheckedBytes.contains(sig.offset, sig.size, in: file.count), sig.size >= 20 else {
            report.record("\(name) has a code signature", false, "none, or outside the file")
            return
        }
        report.record("\(name) has a code signature", true)
        report.record("\(name) signature is the last thing in the file", sig.offset == file.count - sig.size)
        report.record("\(name) __LINKEDIT covers the signature",
                      macho.linkeditFileOffset <= UInt64(file.count) && macho.linkeditFileSize == UInt64(file.count) - macho.linkeditFileOffset,
                      "__LINKEDIT \(macho.linkeditFileOffset)+\(macho.linkeditFileSize), file size \(file.count)")
        report.record("\(name) binary is not FairPlay-encrypted", !macho.isEncrypted)

        let blob = file[sig.offset..<(sig.offset + sig.size)]
        let slots: [Int: Data]
        do { slots = try SignatureLayout.slots(blob) }
        catch {
            report.record("\(name) blob index is within the signature and has no duplicate blob slots", false, "\(error)")
            return
        }
        report.record("\(name) blob index is within the signature", true)
        report.record("\(name) no duplicate blob slots", true)
        let unexpected = slots.keys.filter { !expectedSlots.contains($0) }
        report.record("\(name) only expected blob slots are present", unexpected.isEmpty,
                      "slots \(unexpected.map { String($0, radix: 16) }) are not produced or evaluated by this verifier")
        let magics = [0: Blob.codeDirectory, 2: Blob.requirementSet, 5: Blob.entitlementsXML,
                      7: Blob.entitlementsDER, 0x10000: Blob.cmsWrapper]
        for (slot, bytes) in slots {
            if let magic = magics[slot], CheckedBytes.be32(bytes, 0) != Int(magic) {
                report.record("\(name) signature blob has the expected magic", false, "slot \(slot)")
                return
            }
        }
        guard let cd = slots[0] else {
            report.record("\(name) CodeDirectory present", false, "")
            return
        }
        let layout: SignatureLayout.CodeDirectory
        do { layout = try SignatureLayout.CodeDirectory(cd) }
        catch { report.record("\(name) CodeDirectory geometry", false, "\(error)"); return }
        report.record("\(name) CodeDirectory length field matches its blob", true)

        // CodeDirectory geometry and page hashes
        let hashOffset = layout.hashOffset, nSpecial = layout.specialCount, nCode = layout.codeCount, codeLimit = layout.codeLimit
        let hashSize = Int(cd[cd.startIndex + 36]), hashType = Int(cd[cd.startIndex + 37]), pageLog2 = Int(cd[cd.startIndex + 39])
        report.record("\(name) CodeDirectory uses SHA-256", hashType == 2 && hashSize == 32, "hash type \(hashType), size \(hashSize)")
        report.record("\(name) code limit equals signature offset", codeLimit == sig.offset, "\(codeLimit) vs \(sig.offset)")
        func be64(_ o: Int) -> UInt64 { (0..<8).reduce(0) { $0 << 8 | UInt64(cd[cd.startIndex + o + $1]) } }
        if cd.count >= 88 {
            report.record("\(name) executable segment matches __TEXT",
                          be64(64) == macho.textFileOffset && be64(72) == macho.textFileSize,
                          "CodeDirectory \(be64(64))+\(be64(72)), __TEXT \(macho.textFileOffset)+\(macho.textFileSize)")
        }
        guard pageLog2 >= 12, pageLog2 < 32 else { report.record("\(name) page size is sane", false, "pageLog2 \(pageLog2)"); return }
        let pageSize = layout.pageSize
        var pagesOK = hashType == 2 && hashSize == 32 && pageLog2 >= 12 && nCode == codeLimit / pageSize + (codeLimit % pageSize == 0 ? 0 : 1)
            && hashOffset + nCode * 32 <= cd.count && codeLimit <= file.count
        if pagesOK {
            for p in 0..<nCode {
                let s = p * pageSize, e = min(s + pageSize, codeLimit)
                let want = cd[(cd.startIndex + hashOffset + p * 32)..<(cd.startIndex + hashOffset + (p + 1) * 32)]
                if Data(SHA256.hash(data: file[s..<e])) != Data(want) { pagesOK = false; break }
            }
        }
        report.record("\(name) page hashes match the file", pagesOK)

        // Special slots
        func special(_ n: Int) -> Data? {
            guard n <= nSpecial else { return nil }
            let start = cd.startIndex + hashOffset - n * 32
            guard CheckedBytes.contains(start - cd.startIndex, 32, in: cd.count) else { return nil }
            let h = Data(cd[start..<(start + 32)])
            return h == Data(count: 32) ? nil : h
        }
        func check(_ slot: Int, _ label: String, _ content: Data?) {
            switch (special(slot), content) {
            case (let h?, let c?): report.record("\(name) \(label) hash", h == Data(SHA256.hash(data: c)))
            case (nil, nil): break
            case (_?, nil): report.record("\(name) \(label) hash", false, "sealed but content missing")
            case (nil, _?): report.record("\(name) \(label) hash", false, "content present but not sealed")
            }
        }
        check(1, "Info.plist", infoPlist)
        check(2, "requirements", slots[2])
        check(3, "CodeResources", codeResources)
        check(5, "XML entitlements", slots[5])
        check(7, "DER entitlements", slots[7])

        if let xml = slots[5], let der = slots[7] {
            let plist = (try? PropertyListSerialization.propertyList(from: xml.dropFirst(8), format: nil)) as? [String: Any]
            let encoded = plist.flatMap { try? EntitlementsDER.encode($0) }
            report.record("\(name) XML and DER entitlements agree",
                          encoded.map { Blob.wrap(Blob.entitlementsDER, $0) == der } ?? false)
        }

        // CMS signature over the CodeDirectory
        guard let cmsBlob = slots[0x10000], cmsBlob.count > 8,
              (try? SignatureLayout.validateCMS(Data(cmsBlob.dropFirst(8)))) != nil,
              let cms = try? CMSSignedData.parse(cmsBlob.dropFirst(8)) else {
            report.record("\(name) CMS signature present and parseable", false, "")
            return
        }
        report.record("\(name) CMS signature present and parseable", cms.signers.count == 1)
        let verdict = cms.checkSignature(content: cd)
        report.record("\(name) CMS signature is valid over the CodeDirectory", verdict == .valid, "\(verdict)")
        let cdhash = Data(SHA256.hash(data: cd))
        report.record("\(name) CMS carries the CodeDirectory hash", cms.signers.first?.messageDigest == cdhash)

        if let signer = cms.signers.first, let der = cms.signerCertificateDER(signer) {
            let sha1 = X509Fingerprint.sha1(der)
            if !report.signerSHA1s.contains(sha1) { report.signerSHA1s.append(sha1) }
            if let expected {
                report.record("\(name) signed by the expected certificate", sha1 == expected.uppercased(),
                              "signer \(sha1)")
            }
        } else if expected != nil {
            report.record("\(name) signed by the expected certificate", false, "signer certificate not found in the message")
        }
    }
}

/// SHA-1 certificate fingerprint helper (uppercase hex), the form profiles list.
public enum X509Fingerprint {
    public static func sha1(_ der: Data) -> String { Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined() }
}
