import CredentialKit
import CryptoKit
import IPAKit
import XCTest
@testable import SigningKit

final class SigningTests: XCTestCase {
    private func profile(_ data: Data) throws -> ProvisioningProfile { try ProvisioningProfile.parse(data) }

    private func sign(_ app: URL, p12: Data = FixtureData.p12ValidLegacy, profile data: Data = FixtureData.profileWildcardAll,
                      options: SigningOptions = SigningOptions()) throws -> SigningResult {
        let creds = try TestCredentials(p12: p12)
        return try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                     profile: profile(data), options: options)
    }

    // MARK: Building blocks against Apple's own output

    func testDEREntitlementsMatchAppleByteForByte() throws {
        let one = Blob.wrap(Blob.entitlementsDER, try EntitlementsDER.encode(Fixtures.entitlements1))
        XCTAssertEqual(one, hex(Fixtures.appleDER1))
        let two = Blob.wrap(Blob.entitlementsDER, try EntitlementsDER.encode(Fixtures.entitlements2))
        XCTAssertEqual(two, hex(Fixtures.appleDER2), "nested dict / array / int / bool encoding must match codesign")
    }

    func testAppIdentifierPermission() {
        let p = EntitlementsPolicy.permits
        XCTAssertTrue(p("T.com.a.b", "T", "com.a.b"))
        XCTAssertFalse(p("T.com.a.b", "T", "com.a.b.ext"))
        XCTAssertTrue(p("T.*", "T", "anything.at.all"))
        XCTAssertTrue(p("T.com.a.*", "T", "com.a.b.ext"))
        XCTAssertFalse(p("T.com.a.*", "T", "com.other.b"))
        XCTAssertFalse(p("U.com.a.b", "T", "com.a.b"))
    }

    func testMachORejectsFatAndGarbage() {
        XCTAssertThrowsError(try MachO(Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 1] + [UInt8](repeating: 0, count: 40))))
        XCTAssertThrowsError(try MachO(Data(repeating: 7, count: 100)))
        XCTAssertThrowsError(try MachO(Data()))
    }

    // MARK: Signing, verified by independent tools (macOS only)

    #if os(macOS)
    private func codesign(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try! p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func verify(_ url: URL) -> (status: Int32, output: String) {
        codesign(["--verify", "--deep", "--strict", "-vvvv", url.path])
    }

    func testControlUnsignedAppFailsVerification() throws {
        let app = try makeWorkingApp()
        XCTAssertNotEqual(verify(app).status, 0)
    }

    func testSignedAppPassesAppleCodesignVerification() throws {
        let app = try makeWorkingApp()
        let result = try sign(app)

        // nested code is signed before the code that seals it
        XCTAssertEqual(result.items.map(\.kind), [.framework, .appExtension, .app])
        let v = verify(app)
        XCTAssertEqual(v.status, 0, v.output)

        let info = codesign(["-dvvv", app.path]).output
        XCTAssertTrue(info.contains("TeamIdentifier=FIXT123456"), info)
        XCTAssertTrue(info.contains("Sealed Resources version=2"), info)
        XCTAssertTrue(info.contains("CodeDirectory v=20400"), info)

        for nested in ["Frameworks/TestKit.framework", "PlugIns/TestExt.appex"] {
            let r = codesign(["--verify", "--strict", "-vv", app.appendingPathComponent(nested).path])
            XCTAssertEqual(r.status, 0, "\(nested): \(r.output)")
        }
    }

    func testEntitlementsAndAppIdentifierAreResolvedFromProfile() throws {
        let app = try makeWorkingApp()
        _ = try sign(app)
        let ents = codesign(["-d", "--entitlements", "-", "--xml", app.path]).output
        XCTAssertTrue(ents.contains("FIXT123456.dev.localsigner.testapp"), ents)
        XCTAssertTrue(ents.contains("<key>get-task-allow</key><true/>"), ents)
        XCTAssertTrue(ents.contains("com.apple.developer.team-identifier"), ents)

        let appex = codesign(["-d", "--entitlements", "-", "--xml", app.appendingPathComponent("PlugIns/TestExt.appex").path]).output
        XCTAssertTrue(appex.contains("FIXT123456.dev.localsigner.testapp.TestExt"), appex)

        // frameworks carry no entitlements
        let fw = codesign(["-d", "--entitlements", "-", "--xml", app.appendingPathComponent("Frameworks/TestKit.framework").path]).output
        XCTAssertFalse(fw.contains("application-identifier"), fw)
    }

    func testProfileIsEmbeddedInAppAndExtensionOnly() throws {
        let app = try makeWorkingApp()
        _ = try sign(app)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path))
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("PlugIns/TestExt.appex/embedded.mobileprovision").path))
        XCTAssertFalse(fm.fileExists(atPath: app.appendingPathComponent("Frameworks/TestKit.framework/embedded.mobileprovision").path))
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision")), FixtureData.profileWildcardAll)
    }

    func testTamperingAfterSigningIsDetected() throws {
        // modify a sealed resource
        var app = try makeWorkingApp()
        _ = try sign(app)
        try Data("changed".utf8).write(to: app.appendingPathComponent("note.txt"))
        XCTAssertNotEqual(verify(app).status, 0, "modified resource")

        // modify the executable
        app = try makeWorkingApp()
        _ = try sign(app)
        let exe = app.appendingPathComponent("SigningTestApp")
        var bytes = try Data(contentsOf: exe)
        bytes[200] ^= 0xFF
        try bytes.write(to: exe)
        XCTAssertNotEqual(verify(app).status, 0, "modified executable")

        // modify a nested framework binary
        app = try makeWorkingApp()
        _ = try sign(app)
        let fw = app.appendingPathComponent("Frameworks/TestKit.framework/TestKit")
        var fbytes = try Data(contentsOf: fw)
        fbytes[300] ^= 0xFF
        try fbytes.write(to: fw)
        XCTAssertNotEqual(verify(app).status, 0, "modified nested code")

        // add an unsealed file
        app = try makeWorkingApp()
        _ = try sign(app)
        try Data("x".utf8).write(to: app.appendingPathComponent("extra.txt"))
        XCTAssertNotEqual(verify(app).status, 0, "added file")
    }

    func testCMSSignatureVerifiesWithIndependentTool() throws {
        let openssl = "/usr/bin/openssl"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: openssl), "no openssl")
        let app = try makeWorkingApp()
        _ = try sign(app)

        let exe = try Data(contentsOf: app.appendingPathComponent("SigningTestApp"))
        let sig = try XCTUnwrap(try MachO(exe).existingSignature)
        let blob = exe[sig.offset..<(sig.offset + sig.size)]
        func be32(_ o: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(blob[blob.startIndex + o + $1]) } }
        var cd = Data(), cms = Data()
        for i in 0..<be32(8) {
            let type = be32(12 + 8 * i), off = be32(16 + 8 * i), len = be32(off + 4)
            let body = blob[(blob.startIndex + off)..<(blob.startIndex + off + len)]
            if type == 0 { cd = Data(body) }
            if type == 0x10000 { cms = Data(body.dropFirst(8)) }
        }
        XCTAssertFalse(cd.isEmpty); XCTAssertFalse(cms.isEmpty)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try cd.write(to: dir.appendingPathComponent("cd"))
        try cms.write(to: dir.appendingPathComponent("cms"))
        func run(_ extra: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: openssl)
            p.arguments = ["cms", "-verify", "-binary", "-inform", "DER", "-in", dir.appendingPathComponent("cms").path,
                           "-content", dir.appendingPathComponent("cd").path, "-noverify", "-out", "/dev/null"] + extra
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            try! p.run(); let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return (p.terminationStatus, String(decoding: out, as: UTF8.self))
        }
        let good = run([])
        XCTAssertEqual(good.0, 0, good.1)

        // control: the same signature must fail against a different CodeDirectory
        var other = cd; other[other.count - 1] ^= 1
        try other.write(to: dir.appendingPathComponent("cd"))
        XCTAssertNotEqual(run([]).0, 0)
    }

    func testArchiveIntegrityIsCheckedSeparatelyFromCodeSignature() throws {
        // 1. input archive passes IPAKit's structural checks and has no signature files
        let before = try IPAInspector.inspect(url: Fixtures.ipa)
        XCTAssertFalse(before.hasCodeSignature)
        XCTAssertFalse(before.hasEmbeddedProfile)

        // 2. unpack, sign, repack with system tools (prototype only)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ipa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try runTool("/usr/bin/unzip", ["-q", Fixtures.ipa.path, "-d", work.path])
        let app = work.appendingPathComponent("Payload/SigningTestApp.app")
        _ = try sign(app)
        let out = work.appendingPathComponent("signed.ipa")
        try runTool("/usr/bin/zip", ["-q", "-r", "-y", out.path, "Payload"], cwd: work)

        // 3. output archive: structure fine, signature and profile files now present.
        //    IPAKit says only that the files exist, never that they are valid.
        let after = try IPAInspector.inspect(url: out)
        XCTAssertTrue(after.hasCodeSignature)
        XCTAssertTrue(after.hasEmbeddedProfile)
        XCTAssertEqual(after.bundleIdentifier, before.bundleIdentifier)

        // 4. code-signature validity comes from Apple's tool, on a fresh extraction of the output IPA
        let check = work.appendingPathComponent("check")
        try runTool("/usr/bin/unzip", ["-q", out.path, "-d", check.path])
        XCTAssertEqual(verify(check.appendingPathComponent("Payload/SigningTestApp.app")).status, 0)
    }

    private func runTool(_ path: String, _ args: [String], cwd: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = cwd
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "\(path) failed")
    }

    func testRewriteBundleIdentifierWithPrefixProfile() throws {
        let app = try makeWorkingApp()
        var options = SigningOptions()
        options.rewriteBundleIdentifier = true
        let result = try sign(app, profile: FixtureData.profileWildcardPrefix, options: options)

        XCTAssertEqual(result.bundleIdentifierChanges["dev.localsigner.testapp"], "com.example.testapp")
        XCTAssertEqual(result.bundleIdentifierChanges["dev.localsigner.testapp.TestExt"], "com.example.testapp.TestExt")
        XCTAssertEqual(verify(app).status, 0)

        func bundleID(_ rel: String) throws -> String {
            let d = try Data(contentsOf: app.appendingPathComponent(rel).appendingPathComponent("Info.plist"))
            return (try PropertyListSerialization.propertyList(from: d, format: nil) as! [String: Any])["CFBundleIdentifier"] as! String
        }
        XCTAssertEqual(try bundleID("."), "com.example.testapp")
        XCTAssertEqual(try bundleID("PlugIns/TestExt.appex"), "com.example.testapp.TestExt")
        XCTAssertEqual(try bundleID("Frameworks/TestKit.framework"), "dev.localsigner.testapp.TestKit", "frameworks keep their id")

        let ents = codesign(["-d", "--entitlements", "-", "--xml", app.path]).output
        XCTAssertTrue(ents.contains("FIXT123456.com.example.testapp"), ents)
    }
    #endif

    // MARK: Policy and refusal paths (all platforms)

    func testMismatchedExplicitProfileIsRefusedUnlessRewriteRequested() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, profile: FixtureData.profileValidBER)) {
            guard case .appIdentifierMismatch(_, let id, _) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(id, "dev.localsigner.testapp")
        }
        // nothing was modified on failure
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path))
    }

    func testExtensionNeedsItsOwnPermission() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, profile: FixtureData.profileExactTestApp)) {
            guard case .appIdentifierMismatch(let bundle, let id, _) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(bundle, "PlugIns/TestExt.appex")
            XCTAssertEqual(id, "dev.localsigner.testapp.TestExt")
        }
    }

    func testProfileMustListTheSigningCertificate() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, p12: FixtureData.p12SecondIdentity)) {
            XCTAssertEqual($0 as? SigningError, .profileDoesNotListCertificate)
        }
    }

    func testRequestedEntitlementsNotGrantedByProfileAreDroppedWithWarning() throws {
        let app = try makeWorkingApp()
        var options = SigningOptions()
        options.requestedEntitlements = ["com.apple.developer.associated-domains": ["applinks:example.com"]]
        let result = try sign(app, options: options)
        XCTAssertTrue(result.warnings.contains { $0.contains("com.apple.developer.associated-domains") }, "\(result.warnings)")
    }

    func testSigningTwiceReplacesTheSignature() throws {
        let app = try makeWorkingApp()
        let first = try sign(app)
        let second = try sign(app)
        XCTAssertEqual(first.items.count, second.items.count)
        let exe = try Data(contentsOf: app.appendingPathComponent("SigningTestApp"))
        let m = try MachO(exe)
        let sig = try XCTUnwrap(m.existingSignature)
        XCTAssertEqual(sig.offset + sig.size, exe.count, "signature is last and nothing is left over from the first pass")
        #if os(macOS)
        XCTAssertEqual(verify(app).status, 0)
        #endif
    }
}
