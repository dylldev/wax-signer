import CredentialKit
import IPAKit
import XCTest
@testable import SigningKit

final class SigningPlanTests: XCTestCase {
    private var app: URL!
    override func setUpWithError() throws { app = try makeWorkingApp() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
    private func snapshot() throws -> IPAArchiveManifest { try .capture(directory: app.deletingLastPathComponent(), rootFolder: app.lastPathComponent) }
    private func plan(_ credentials: TestCredentials, options: SigningOptions = SigningOptions(), maxBundles: Int = 256) throws -> SigningPlan {
        try BundleSigner.plan(appDirectory: app, certificateChainDER: credentials.signer.certificateChainDER,
            certificateTeamID: credentials.loaded.teamID, profiles: ProfileSet(single: .parse(FixtureData.profileWildcardAll)),
            options: options, profilePolicy: .allowInvalidForTesting, maxBundles: maxBundles)
    }
    func testPreviewIsReadOnlyAndNeedsOnlyPublicCertificateBytes() throws {
        let before = try snapshot(), credentials = try TestCredentials()
        let preview = try plan(credentials)
        XCTAssertEqual(preview.bundles.map(\.path), [".", "PlugIns/TestExt.appex"])
        XCTAssertTrue(preview.installationAssessment.contains("Not determined"))
        XCTAssertEqual(preview.bundles[0].profile.profileName, try ProvisioningProfile.parse(FixtureData.profileWildcardAll).info.name)
        try before.verifyTree()
    }
    func testPlanExecutionUsesExactlyPreviewedProfilesAndEntitlements() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials)
        let result = try BundleSigner.sign(plan: preview, identity: credentials.signer)
        for bundle in preview.bundles {
            let signed = try XCTUnwrap(result.items.first { $0.relativePath == bundle.path })
            let entitlements = try XCTUnwrap(try PropertyListSerialization.propertyList(from: bundle.signedEntitlementsXML, format: nil) as? [String: Any])
            XCTAssertEqual(signed.identifier, bundle.identifier); XCTAssertEqual(signed.profileName, bundle.profile.profileName)
            XCTAssertEqual(signed.entitlementKeys, entitlements.keys.sorted())
        }
        XCTAssertEqual(result.profileSelections, preview.bundles.map(\.profile))
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).passed)
    }
    func testUnknownRequestedCapabilityIsShownDroppedAndStrictPolicyRejectsReadOnly() throws {
        let credentials = try TestCredentials(), before = try snapshot()
        var options = SigningOptions(); options.overrideEntitlements = ["fixture.ungranted": true]
        let preview = try plan(credentials, options: options)
        let decision = try XCTUnwrap(preview.bundles[0].entitlements.first { $0.key == "fixture.ungranted" })
        XCTAssertEqual(decision.disposition, .dropped); XCTAssertNotNil(decision.requestedValueXML); XCTAssertNil(decision.signedValueXML)
        options.entitlementPolicy = .reject
        XCTAssertThrowsError(try plan(credentials, options: options))
        try before.verifyTree()
    }
    func testChangedResourceRejectsBeforeAnySigningMutation() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials)
        try Data("new resource".utf8).write(to: app.appendingPathComponent("new-resource"))
        let changed = try snapshot()
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: credentials.signer)) {
            XCTAssertTrue($0.localizedDescription.contains("changed"))
        }
        try changed.verifyTree()
    }
    func testChangedExecutableRejectsBeforeSignatureReplacement() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials)
        // Resolve fixture executable instead of assuming a project/product spelling.
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as? [String: Any])
        let path = app.appendingPathComponent(try XCTUnwrap(plist["CFBundleExecutable"] as? String))
        var bytes = try Data(contentsOf: path); bytes.append(0); try bytes.write(to: path)
        let changed = try snapshot()
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: credentials.signer))
        try changed.verifyTree(); XCTAssertEqual(try Data(contentsOf: path), bytes)
    }
    func testChangedModeRejectsWithoutRestoringOrRewritingUserChanges() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.path)
        let changed = try snapshot()
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: credentials.signer))
        try changed.verifyTree()
    }
    func testChangedSymlinkTargetRejectsBeforeMutation() throws {
        let a = app.appendingPathComponent("a"), b = app.appendingPathComponent("b"), link = app.appendingPathComponent("link")
        try Data([1]).write(to: a); try Data([2]).write(to: b)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "a")
        let credentials = try TestCredentials(), preview = try plan(credentials)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "b")
        let changed = try snapshot()
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: credentials.signer)); try changed.verifyTree()
    }
    func testDifferentSigningChainIsRejectedBeforePrivateKeyUse() throws {
        struct WrongChain: CodeSigningIdentity {
            let certificateChainDER = [Data([1,2,3])]
            func signRSAPKCS1SHA256(_ message: Data) throws -> Data { XCTFail("must refuse before signing"); return Data() }
        }
        let credentials = try TestCredentials(), before = try snapshot(), preview = try plan(credentials)
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: WrongChain())) {
            XCTAssertTrue($0.localizedDescription.contains("chain changed"))
        }
        try before.verifyTree()
    }
    func testPlanIsOnceOnlyEvenIfCopied() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials), copy = preview
        _ = try BundleSigner.sign(plan: preview, identity: credentials.signer)
        let signed = try snapshot()
        XCTAssertThrowsError(try BundleSigner.sign(plan: copy, identity: credentials.signer)) {
            XCTAssertTrue($0.localizedDescription.contains("already attempted"))
        }
        try signed.verifyTree()
    }
    func testCertificateExpirationSincePreviewIsRechecked() throws {
        let credentials = try TestCredentials(), before = try snapshot(), preview = try plan(credentials)
        XCTAssertThrowsError(try BundleSigner.sign(plan: preview, identity: credentials.signer, now: .distantFuture)) {
            guard case SigningError.certificateExpired = $0 else { return XCTFail("expected expired certificate: \($0)") }
        }
        try before.verifyTree()
    }
    func testPreviewReportHasExplicitBundleAndEntitlementBounds() throws {
        let credentials = try TestCredentials(), before = try snapshot()
        XCTAssertThrowsError(try plan(credentials, maxBundles: 1))
        var options = SigningOptions(); options.overrideEntitlements = ["oversized": String(repeating: "x", count: 300_000)]
        XCTAssertThrowsError(try plan(credentials, options: options)); try before.verifyTree()
    }
    func testMalformedCMSIsRejectedByDefaultWithoutClaimingUnknownTrustIsInvalid() throws {
        let credentials = try TestCredentials(), before = try snapshot()
        let cms = try CMSSignedData.parse(FixtureData.profileWildcardAll)
        let content = try XCTUnwrap(cms.encapsulatedContent)
        let unsigned = DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xa0, DER.sequence([
            DER.integer(1), DER.setOf([]), DER.sequence([DER.oid("1.2.840.113549.1.7.1"), DER.tlv(0xa0, DER.octetString(content))]), DER.setOf([])
        ]))])
        let profiles = try ProfileSet(single: .parse(unsigned))
        XCTAssertThrowsError(try BundleSigner.plan(appDirectory: app, certificateChainDER: credentials.signer.certificateChainDER,
            certificateTeamID: credentials.loaded.teamID, profiles: profiles)) { XCTAssertTrue($0.localizedDescription.contains("CMS signature invalid")) }
        let explicitFixture = try BundleSigner.plan(appDirectory: app, certificateChainDER: credentials.signer.certificateChainDER,
            certificateTeamID: credentials.loaded.teamID, profiles: profiles, profilePolicy: .allowInvalidForTesting)
        guard case .invalid = explicitFixture.bundles[0].profile.signatureStatus else { return XCTFail("must preserve invalid, never promote fixture trust") }
        try before.verifyTree()
    }
    #if os(macOS)
    func testPlannedOutputPassesIndependentAppleCodesign() throws {
        let credentials = try TestCredentials(), preview = try plan(credentials)
        _ = try BundleSigner.sign(plan: preview, identity: credentials.signer)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: output, as: UTF8.self))
    }
    #endif
}
