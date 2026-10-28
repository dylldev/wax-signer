import CredentialKit
import XCTest
@testable import SigningKit

/// Each test here pins a defect found by reading the signing path (see the audit in the spec, section 15).
/// They were written to fail against the code as of b6d8f1d.
final class AuditRegressionTests: XCTestCase {
    // MARK: helpers

    private func sign(_ app: URL, p12: Data = FixtureData.p12ValidLegacy,
                      profile: Data = FixtureData.profileWildcardAll, options: SigningOptions = SigningOptions()) throws -> SigningResult {
        let creds = try TestCredentials(p12: p12)
        return try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                     profile: try ProvisioningProfile.parse(profile), options: options)
    }

    private func signedApp() throws -> URL {
        let app = try makeWorkingApp()
        _ = try sign(app)
        return app
    }

    private func snapshot(_ app: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])!
        for case let url as URL in e {
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if v.isRegularFile == true, v.isSymbolicLink != true { out[url.path] = try Data(contentsOf: url) }
        }
        return out
    }

    private func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> UInt32(8 * $0)) & 0xff) }) }

    /// Minimal thin arm64 executable. `cryptid` adds LC_ENCRYPTION_INFO_64; `trailer` appends bytes after __LINKEDIT.
    private func syntheticMachO(cryptid: UInt32? = nil, signature: Bool = false, trailer: Int = 0) -> Data {
        func u32(_ v: UInt32) -> Data { le32(v) }
        func u64(_ v: UInt64) -> Data { Data((0..<8).map { UInt8((v >> UInt64(8 * $0)) & 0xff) }) }
        func cat(_ parts: [Data]) -> Data { parts.reduce(Data(), +) }      // arrays type-check quickly; long `+` chains do not on older compilers
        func name(_ s: String) -> Data { Data(s.utf8) + Data(count: 16 - s.utf8.count) }
        let textCmd = 72 + 80, linkCmd = 72
        let encCmd = cryptid != nil ? 24 : 0, sigCmd = signature ? 16 : 0
        let cmds = textCmd + linkCmd + encCmd + sigCmd
        let sectionOffset = 32 + cmds + 64
        let textSize = 0x4000
        let sigSize = signature ? 64 : 0
        let linkSize = 16 + sigSize
        var d = Data()
        d += cat([u32(0xFEED_FACF), u32(0x0100_000C), u32(0), u32(2)])
        let extraCommands: Int = (cryptid != nil ? 1 : 0) + (signature ? 1 : 0)
        d += cat([u32(UInt32(2 + extraCommands)), u32(UInt32(cmds)), u32(0), u32(0)])
        d += cat([u32(0x19), u32(UInt32(textCmd)), name("__TEXT"), u64(0x1_0000_0000), u64(0x4000)])
        d += cat([u64(0), u64(UInt64(textSize)), u32(5), u32(5), u32(1), u32(0)])
        d += cat([name("__text"), name("__TEXT"), u64(0x1_0000_0000 + UInt64(sectionOffset)), u64(16)])
        d += cat([u32(UInt32(sectionOffset)), Data(count: 28)])
        d += cat([u32(0x19), u32(UInt32(linkCmd)), name("__LINKEDIT"), u64(0x1_0000_4000), u64(0x4000)])
        d += cat([u64(UInt64(textSize)), u64(UInt64(linkSize)), u32(1), u32(1), u32(0), u32(0)])
        if let cryptid { d += cat([u32(0x2C), u32(24), u32(0x4000), u32(0x10), u32(cryptid), u32(0)]) }
        if signature { d += cat([u32(0x1d), u32(16), u32(UInt32(textSize + 16)), u32(UInt32(sigSize))]) }
        d += Data(count: textSize - d.count)
        let sigBytes: Data = signature ? Data(repeating: 0xBB, count: sigSize) : Data()
        d += Data(repeating: 0xAA, count: 16) + sigBytes
        return d + Data(repeating: 0xCC, count: trailer)
    }

    // MARK: A. encrypted binaries

    func testEncryptedBinaryIsDetected() throws {
        XCTAssertTrue(try MachO(syntheticMachO(cryptid: 1)).isEncrypted)
        XCTAssertFalse(try MachO(syntheticMachO(cryptid: 0)).isEncrypted)
        XCTAssertFalse(try MachO(syntheticMachO()).isEncrypted)
    }

    func testSigningAnEncryptedAppIsRefusedAndNothingIsModified() throws {
        let app = try makeWorkingApp()
        try syntheticMachO(cryptid: 1).write(to: app.appendingPathComponent("SigningTestApp"))
        let before = try snapshot(app)
        XCTAssertThrowsError(try sign(app)) {
            XCTAssertTrue(($0 as? SigningError)?.errorDescription?.lowercased().contains("encrypted") == true, "\($0)")
        }
        XCTAssertEqual(try snapshot(app), before)
    }

    // MARK: B. existing signature with trailing data

    func testTrailingBytesAfterTheSignatureAreNeverDeleted() throws {
        var m = try MachO(syntheticMachO(signature: true, trailer: 32))
        XCTAssertThrowsError(try m.prepareForSignature(size: 100)) {
            XCTAssertTrue(($0 as? SigningError)?.errorDescription?.contains("not at the end") == true, "\($0)")
        }
    }

    // MARK: C. code outside the places we sign

    func testUnsignedExecutableCodeOutsideKnownLocationsIsRefused() throws {
        let app = try makeWorkingApp()
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app.appendingPathComponent("Frameworks/TestKit.framework/TestKit"),
                                         to: app.appendingPathComponent("Resources/helper.dylib"))
        let before = try snapshot(app)
        XCTAssertThrowsError(try sign(app)) {
            let text = ($0 as? SigningError)?.errorDescription ?? "\($0)"
            XCTAssertTrue(text.contains("Resources/helper.dylib"), text)
        }
        XCTAssertEqual(try snapshot(app), before)
    }

    func testVerifierFlagsUnsignedCodeOutsideKnownLocations() throws {
        let app = try signedApp()
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixtures.appDirectory.appendingPathComponent("Frameworks/TestKit.framework/TestKit"),
                                         to: app.appendingPathComponent("Resources/helper.dylib"))
        let report = SignatureVerifier.verifyBundle(at: app)
        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.failures.contains { $0.name.contains("Resources/helper.dylib") }, "\(report.failures)")
    }

    // MARK: D. symlinks must not redirect writes

    func testSymlinkedProfileSlotCannotOverwriteAFileOutsideTheApp() throws {
        let app = try makeWorkingApp()
        let victim = FileManager.default.temporaryDirectory.appendingPathComponent("victim-\(UUID().uuidString)")
        try Data("do not touch".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("embedded.mobileprovision"), withDestinationURL: victim)
        XCTAssertThrowsError(try sign(app))
        XCTAssertEqual(try Data(contentsOf: victim), Data("do not touch".utf8))
    }

    func testSymlinkedExecutableCannotBeRewrittenThroughTheLink() throws {
        let app = try makeWorkingApp()
        let victim = FileManager.default.temporaryDirectory.appendingPathComponent("victim-\(UUID().uuidString).dylib")
        try FileManager.default.copyItem(at: app.appendingPathComponent("Frameworks/TestKit.framework/TestKit"), to: victim)
        let original = try Data(contentsOf: victim)
        let link = app.appendingPathComponent("Frameworks/TestKit.framework/TestKit")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        XCTAssertThrowsError(try sign(app))
        XCTAssertEqual(try Data(contentsOf: victim), original)
    }

    func testSymlinkEscapingTheAppIsRefused() throws {
        let app = try makeWorkingApp()
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("outside").path, withDestinationPath: "/etc")
        XCTAssertThrowsError(try sign(app)) {
            XCTAssertTrue(($0 as? SigningError)?.errorDescription?.contains("outside") == true, "\($0)")
        }
    }

    // MARK: E. the signing certificate itself

    func testExpiredSigningCertificateIsRefused() throws {
        XCTAssertThrowsError(try sign(try makeWorkingApp(), p12: FixtureData.p12Expired)) {
            guard case .certificateExpired = $0 as? SigningError else { return XCTFail("\($0)") }
        }
    }

    func testNotYetValidSigningCertificateIsRefused() throws {
        XCTAssertThrowsError(try sign(try makeWorkingApp(), p12: FixtureData.p12NotYetValid)) {
            guard case .certificateNotYetValid = $0 as? SigningError else { return XCTFail("\($0)") }
        }
    }

    // MARK: F. profile trust is reported, not assumed

    func testSelectionReportsProfileSignatureStatus() throws {
        let r = try sign(try makeWorkingApp())
        let main = try XCTUnwrap(r.profileSelections.first { $0.bundlePath == "." })
        guard case .signatureValidButUntrusted = main.signatureStatus else { return XCTFail("\(main.signatureStatus)") }
    }

    // MARK: G. requested-false entitlement needs no grant

    func testRequestedFalseEntitlementNeedsNoGrantAndNoWarning() throws {
        var o = SigningOptions()
        o.requestedEntitlements = ["com.apple.developer.some-capability": false]
        let r = try sign(try makeWorkingApp(), options: o)
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }

    // MARK: H. identifier rewrite keeps companion references consistent

    func testRewriteUpdatesWatchCompanionReferences() throws {
        let app = try makeWorkingApp()
        // a minimal Watch app + extension pointing at the main app and at each other
        let watch = app.appendingPathComponent("Watch/Companion.app")
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app.appendingPathComponent("PlugIns/TestExt.appex/TestExt"),
                                         to: watch.appendingPathComponent("Companion"))
        let watchInfo: [String: Any] = [
            "CFBundleIdentifier": "dev.localsigner.testapp.watchkitapp", "CFBundleExecutable": "Companion",
            "WKCompanionAppBundleIdentifier": "dev.localsigner.testapp", "WKWatchKitApp": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: watchInfo, format: .xml, options: 0)
            .write(to: watch.appendingPathComponent("Info.plist"))

        var o = SigningOptions()
        o.rewriteBundleIdentifier = true
        _ = try sign(app, profile: FixtureData.profileWildcardPrefix, options: o)

        func plist(_ url: URL) throws -> [String: Any] {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
        }
        let w = try plist(watch)
        XCTAssertEqual(w["CFBundleIdentifier"] as? String, "com.example.testapp.watchkitapp")
        XCTAssertEqual(w["WKCompanionAppBundleIdentifier"] as? String, "com.example.testapp")
    }

    func testRewriteMovesBackgroundTaskIdentifiersWithTheBundleID() throws {
        let app = try makeWorkingApp()
        let infoURL = app.appendingPathComponent("Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
        info["BGTaskSchedulerPermittedIdentifiers"] = ["dev.localsigner.testapp.signing", "other.id.*"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)

        var o = SigningOptions()
        o.rewriteBundleIdentifier = true
        _ = try sign(app, profile: FixtureData.profileWildcardPrefix, options: o)

        let out = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
        XCTAssertEqual(out["BGTaskSchedulerPermittedIdentifiers"] as? [String], ["com.example.testapp.signing", "other.id.*"])
    }

    // MARK: H2. bundle-scoped entitlement groups follow an identifier rewrite

    func testRewriteMovesBundleScopedGroupsAndLeavesOtherValuesAlone() {
        let renames = ["com.old.app": "com.new.app", "com.old.app.ext": "com.new.app.ext"]
        let out = EntitlementsPolicy.rewriteBundleScoped([
            "keychain-access-groups": ["ABCDE12345.com.old.app", "ABCDE12345.com.old.app.ext", "ABCDE12345.com.other"],
            "com.apple.security.application-groups": ["group.com.old.app", "group.com.shared"],
            "com.apple.developer.associated-domains": ["applinks:old.example.com"],
        ], renames: renames)
        XCTAssertEqual(out["keychain-access-groups"] as? [String], ["ABCDE12345.com.new.app", "ABCDE12345.com.new.app.ext", "ABCDE12345.com.other"])
        XCTAssertEqual(out["com.apple.security.application-groups"] as? [String], ["group.com.new.app", "group.com.shared"])
        XCTAssertEqual(out["com.apple.developer.associated-domains"] as? [String], ["applinks:old.example.com"])
    }

    // MARK: I. verifier must not accept malformed signature containers

    private struct SlotEdit { let index: Int; let newType: UInt32? ; let newOffset: UInt32? }

    private func editSuperBlob(of app: URL, _ edit: SlotEdit) throws {
        let url = app.appendingPathComponent("SigningTestApp")
        var exe = try Data(contentsOf: url)
        let sig = try XCTUnwrap(try MachO(exe).existingSignature)
        let entry = sig.offset + 12 + 8 * edit.index
        if let t = edit.newType { exe.replaceSubrange(entry..<(entry + 4), with: Data([UInt8(t >> 24), UInt8((t >> 16) & 0xff), UInt8((t >> 8) & 0xff), UInt8(t & 0xff)])) }
        if let o = edit.newOffset { exe.replaceSubrange((entry + 4)..<(entry + 8), with: Data([UInt8(o >> 24), UInt8((o >> 16) & 0xff), UInt8((o >> 8) & 0xff), UInt8(o & 0xff)])) }
        try exe.write(to: url)
    }

    func testVerifierRejectsAnUnexpectedAlternateCodeDirectorySlot() throws {
        let app = try signedApp()
        // slot index 1 is requirements (type 2): retype it as an alternate CodeDirectory (0x1000)
        try editSuperBlob(of: app, SlotEdit(index: 1, newType: 0x1000, newOffset: nil))
        let r = SignatureVerifier.verifyBundle(at: app)
        XCTAssertTrue(r.failures.contains { $0.name.contains("only expected blob slots") }, "\(r.failures)")
    }

    func testVerifierRejectsDuplicateSlots() throws {
        let app = try signedApp()
        try editSuperBlob(of: app, SlotEdit(index: 2, newType: 2, newOffset: nil))      // XML entitlements retyped as requirements
        let r = SignatureVerifier.verifyBundle(at: app)
        XCTAssertTrue(r.failures.contains { $0.name.contains("no duplicate blob slots") }, "\(r.failures)")
    }

    func testVerifierRejectsBlobIndexEntryOutsideTheSignature() throws {
        let app = try signedApp()
        try editSuperBlob(of: app, SlotEdit(index: 1, newType: nil, newOffset: 0x00FF_FFFF))
        let r = SignatureVerifier.verifyBundle(at: app)
        XCTAssertTrue(r.failures.contains { $0.name.contains("blob index is within the signature") }, "\(r.failures)")
    }

    func testVerifierRequiresTheExpectedSigner() throws {
        let app = try signedApp()
        let creds = try TestCredentials()
        let sha1 = X509Fingerprint.sha1(creds.signer.certificateChainDER[0])
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app, expectedSignerSHA1: sha1).passed)
        let other = SignatureVerifier.verifyBundle(at: app, expectedSignerSHA1: String(repeating: "0", count: 40))
        XCTAssertFalse(other.passed)
        XCTAssertTrue(other.failures.contains { $0.name.contains("signed by the expected certificate") }, "\(other.failures)")
    }

    func testVerifierReportIncludesSignerFingerprint() throws {
        let r = SignatureVerifier.verifyBundle(at: try signedApp())
        let creds = try TestCredentials()
        XCTAssertTrue(r.signerSHA1s.contains(X509Fingerprint.sha1(creds.signer.certificateChainDER[0])))
    }

    // MARK: Apple-issued chains: requirement form

    /// Xcode's requirement set for an Apple Development signature, with the real common name replaced by a
    /// same-length fake. The structure and every other byte are Apple's.
    private static let appleRequirementVector = "fade0c01000000c8000000010000000300000014fade0c00000000b4000000010000000600000002000000196465762e6c6f63616c7369676e65722e74302e676468706332000000000000060000000f000000060000000b000000000000000a7375626a6563742e434e000000000001000000384170706c6520446576656c6f706d656e743a20746573742e706572736f6e73406578616d706c652e6f7267202841423132434433344546290000000e000000010000000a2a864886f76364060201000000000000"

    func testAppleDevelopmentRequirementMatchesXcodeByteForByte() {
        let built = Requirements.appleDevelopment(identifier: "dev.localsigner.t0.gdhpc2",
                                                  leafCommonName: "Apple Development: test.persons@example.org (AB12CD34EF)")
        XCTAssertEqual(built, hex(Self.appleRequirementVector))
    }

    func testAppleChainDetectionUsesNamesOnlyToPickTheForm() {
        let ok: [String?] = ["Apple Development: A (ID)", "Apple Worldwide Developer Relations Certification Authority", "Apple Root CA"]
        XCTAssertTrue(Requirements.isAppleDevelopmentChain(commonNames: ok))
        XCTAssertFalse(Requirements.isAppleDevelopmentChain(commonNames: Array(ok.prefix(2))), "root missing")
        XCTAssertFalse(Requirements.isAppleDevelopmentChain(commonNames: ["Some Dev", ok[1], ok[2]]), "leaf not Apple Development")
        XCTAssertFalse(Requirements.isAppleDevelopmentChain(commonNames: [ok[0], "Other CA", ok[2]]))
        XCTAssertFalse(Requirements.isAppleDevelopmentChain(commonNames: [nil, ok[1], ok[2]]))
    }

    func testNonAppleChainKeepsTheRootHashForm() throws {
        let creds = try TestCredentials()
        let blob = try Requirements.designated(identifier: "x.y", chainDER: creds.signer.certificateChainDER)
        XCTAssertEqual(blob, Requirements.designated(identifier: "x.y", rootCertificateDER: creds.signer.certificateChainDER.last!))
    }

    func testDesignatedRequirementRejectsAnEmptyChain() {
        XCTAssertThrowsError(try Requirements.designated(identifier: "x.y", chainDER: [])) {
            XCTAssertTrue($0.localizedDescription.contains("certificate chain"), $0.localizedDescription)
        }
    }

    // MARK: Chain completion for leaf-only .p12 files

    private func names(_ chain: [Data]) -> [String?] { chain.map { CertificateSubject.commonName(of: $0) } }

    func testEmbeddedAuthoritiesCompleteAnIntermediateToItsRoot() throws {
        let all = AppleCertificateAuthorities.all
        XCTAssertEqual(all.count, 5)
        let g3 = try XCTUnwrap(all.first { CertificateSubject.commonName(of: $0) == Requirements.appleWWDR
            && X509Fingerprint.sha1($0).hasPrefix("06EC") })
        let completed = AppleCertificateAuthorities.complete(chain: [g3])
        XCTAssertEqual(names(completed), [Requirements.appleWWDR, "Apple Root CA"])
    }

    func testRootAndUnknownIssuersAreLeftAlone() throws {
        let root = try XCTUnwrap(AppleCertificateAuthorities.all.first { CertificateSubject.commonName(of: $0) == "Apple Root CA" })
        XCTAssertEqual(AppleCertificateAuthorities.complete(chain: [root]), [root])
        let fixture = try TestCredentials().signer.certificateChainDER
        XCTAssertEqual(AppleCertificateAuthorities.complete(chain: fixture), fixture, "a self-signed fixture gets no Apple chain")
    }

    func testChainCompletionDoesNotChangeFixtureSigningOutput() throws {
        let creds = try TestCredentials()
        XCTAssertEqual(creds.signer.certificateChainDER.count, 1)
    }
}
