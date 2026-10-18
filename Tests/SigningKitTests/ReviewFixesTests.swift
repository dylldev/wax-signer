import CredentialKit
import XCTest
@testable import SigningKit

/// Defects found in the 2026-10-17 whole-repo review (Codex, space-bunny, deepseek) and checked against the code.
final class ReviewFixesTests: XCTestCase {
    private func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }

    // A signature blob that lies about its slot count or offsets must be refused, not crash the app.
    func testMalformedSignatureBlobsAreRefusedNotTrapped() {
        let magic = BlobReader.embeddedSignatureMagic
        // Claims 1000 slots in a 12-byte blob.
        XCTAssertNil(BlobReader.entitlements(inSignature: Data(be32(magic) + be32(12) + be32(1000))))
        // One slot whose offset points past the end.
        XCTAssertNil(BlobReader.entitlements(inSignature: Data(be32(magic) + be32(20) + be32(1) + be32(5) + be32(9999))))
        // Too short to hold a header.
        XCTAssertNil(BlobReader.entitlements(inSignature: Data(be32(magic))))
    }

    func testWellFormedSignatureBlobStillYieldsEntitlements() throws {
        let xml = try PropertyListSerialization.data(fromPropertyList: ["get-task-allow": true], format: .xml, options: 0)
        let entBlob = be32(BlobReader.entitlementsMagic) + be32(UInt32(8 + xml.count)) + [UInt8](xml)
        let header = be32(BlobReader.embeddedSignatureMagic) + be32(UInt32(20 + entBlob.count)) + be32(1)
            + be32(BlobReader.entitlementsSlot) + be32(20)
        let out = BlobReader.entitlements(inSignature: Data(header + entBlob))
        XCTAssertEqual(out?["get-task-allow"] as? Bool, true)
    }

    // A symlink to a directory elsewhere in the bundle is sealed under its own path.
    func testSymlinkToAnotherDirectoryIsSealedUnderItsOwnPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("seal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("Other/data.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Sub/Assets").path, withDestinationPath: "../Other")
        let plist = try PropertyListSerialization.propertyList(
            from: try CodeResources.build(bundleRoot: root, executable: nil), format: nil) as! [String: Any]
        let files2 = plist["files2"] as! [String: Any]
        XCTAssertNotNil((files2["Sub/Assets"] as? [String: Any])?["symlink"], "\(files2.keys.sorted())")
        XCTAssertNotNil(files2["Other/data.txt"])
    }

    // An extension kept under Extensions/ follows a bundle ID edit, as the signer expects.
    func testBundleIDEditAlsoMovesExtensionsFolderBundles() throws {
        let app = try makeWorkingApp()
        let src = app.appendingPathComponent("PlugIns/TestExt.appex")
        let dest = app.appendingPathComponent("Extensions/TestExt.appex")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: src, to: dest)
        var e = AppEdits(); e.bundleIdentifier = "com.new.app"
        _ = try AppEditor.apply(e, to: app)
        let p = try PropertyListSerialization.propertyList(from: Data(contentsOf: dest.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
        XCTAssertTrue((p["CFBundleIdentifier"] as? String ?? "").hasPrefix("com.new.app."), "\(p["CFBundleIdentifier"] ?? "")")
    }

    // Bundle ID edits are reported, so entitlements named after the old IDs can follow them into the signer.
    func testBundleIDEditReportsEveryRename() throws {
        let app = try makeWorkingApp()
        let old = try XCTUnwrap((try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as? [String: Any])?["CFBundleIdentifier"] as? String)
        var e = AppEdits(); e.bundleIdentifier = "com.new.app"
        let r = try AppEditor.applyDetailed(e, to: app)
        XCTAssertEqual(r.renames[old], "com.new.app")
        XCTAssertTrue(r.renames.values.contains { $0.hasPrefix("com.new.app.") }, "\(r.renames)")
    }

    // Two bundles that end up with the same identifier (for example after an ID edit) must be refused, naming both.
    func testTwoBundlesWithTheSameFinalIdentifierAreRefusedWithBothNamed() throws {
        let app = try makeWorkingApp()
        let src = app.appendingPathComponent("PlugIns/TestExt.appex")
        let twin = app.appendingPathComponent("PlugIns/TwinExt.appex")
        try FileManager.default.copyItem(at: src, to: twin)   // same CFBundleIdentifier as TestExt
        let creds = try TestCredentials()
        XCTAssertThrowsError(try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                                   profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll)),
                                                   options: SigningOptions())) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("TestExt.appex") && text.contains("TwinExt.appex"), text)
        }
    }

    // MARK: Custom entitlements (a user-chosen set replaces the app's own)

    func testCustomEntitlementsReplaceTheAppsOwnAndReachTheSignedApp() throws {
        let app = try makeWorkingApp()
        let creds = try TestCredentials()
        var o = SigningOptions()
        o.overrideEntitlements = ["com.apple.security.application-groups": ["group.com.example.shared"]]
        _ = try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                  profile: try ProvisioningProfile.parse(FixtureData.profileRich), options: o)
        let ents = try signedEntitlements(of: app)
        XCTAssertEqual(ents["com.apple.security.application-groups"] as? [String], ["group.com.example.shared"])
    }

    func testCustomEntitlementsTheProfileDoesNotGrantAreDroppedWithAWarning() throws {
        let app = try makeWorkingApp()
        let creds = try TestCredentials()
        var o = SigningOptions()
        o.overrideEntitlements = ["com.apple.developer.healthkit": true]
        let r = try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                      profile: try ProvisioningProfile.parse(FixtureData.profileWildcardAll), options: o)
        XCTAssertNil(try signedEntitlements(of: app)["com.apple.developer.healthkit"])
        XCTAssertFalse(r.warnings.isEmpty)
    }

    private func signedEntitlements(of app: URL) throws -> [String: Any] {
        let exe = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil)
            as? [String: Any])["CFBundleExecutable"] as? String
        let macho = try MachO(Data(contentsOf: app.appendingPathComponent(try XCTUnwrap(exe))))
        let sig = try XCTUnwrap(macho.existingSignature)
        return try XCTUnwrap(BlobReader.entitlements(inSignature: macho.data[sig.offset..<(sig.offset + sig.size)]))
    }
}
