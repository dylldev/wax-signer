import CredentialKit
import CryptoKit
import XCTest
@testable import SigningKit

final class AppIDPrefixTests: XCTestCase {
    private let prefix = "OLDP123456"
    private let team = "FIXT123456"

    /// Unsigned synthetic CMS for structural/entitlement tests only; never an Apple trust fixture.
    private func bytes(pattern: String = "*", declared: Any? = ["OLDP123456"]) throws -> Data {
        let content = try XCTUnwrap(try CMSSignedData.parse(FixtureData.profileWildcardAll).encapsulatedContent)
        var plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: content, format: nil) as? [String: Any])
        plist["ApplicationIdentifierPrefix"] = declared
        var entitlements = try XCTUnwrap(plist["Entitlements"] as? [String: Any])
        entitlements["application-identifier"] = prefix + "." + pattern
        entitlements["keychain-access-groups"] = [prefix + ".*"]
        plist["Entitlements"] = entitlements
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xa0, DER.sequence([
            DER.integer(1), DER.setOf([]), DER.sequence([DER.oid("1.2.840.113549.1.7.1"), DER.tlv(0xa0, DER.octetString(xml))]), DER.setOf([])
        ]))])
    }
    func testDistinctPrefixParsesWithoutChangingTeamOrLegacyMetadataShape() throws {
        let profile = try ProvisioningProfile.parse(bytes(pattern: "com.example.*"))
        XCTAssertEqual(profile.info.teamID, team)
        XCTAssertEqual(profile.info.applicationIdentifierPrefix, prefix)
        XCTAssertEqual(profile.info.bundleIdentifierPattern, "com.example.*")
        let legacy = try JSONEncoder().encode(profile.info)
        XCTAssertEqual(try JSONDecoder().decode(ProfileInfo.self, from: legacy).applicationIdentifierPrefix, prefix)
        if case .appleChainVerified = ProfileTrust.evaluate(profile.rawData) { XCTFail("synthetic profile is not trusted") }
    }
    func testMissingDeclaredPrefixUsesTheActualEntitlementPrefix() throws {
        XCTAssertEqual(try ProvisioningProfile.parse(bytes(declared: nil)).info.applicationIdentifierPrefix, prefix)
    }
    func testMalformedOrInconsistentDeclaredPrefixesAreRejected() throws {
        let invalid: [Any] = [[String](), [""], ["not-a-prefix"], [team], [prefix, prefix], prefix]
        for value in invalid {
            XCTAssertThrowsError(try ProvisioningProfile.parse(bytes(declared: value))) {
                XCTAssertEqual($0 as? CredentialError, .profileInvalidPlist)
            }
        }
    }
    func testMultipleDeclaredPrefixesAreBoundToTheActualApplicationIdentifier() throws {
        XCTAssertEqual(try ProvisioningProfile.parse(bytes(declared: [team, prefix])).info.applicationIdentifierPrefix, prefix)
    }
    func testExactPrefixWildcardAndFullWildcardUseAppPrefix() {
        for pattern in ["com.example.app", "com.example.*", "*"] {
            XCTAssertTrue(ProfileFitness.permits(bundleIdentifier: "com.example.app", profileApplicationIdentifier: prefix + "." + pattern, applicationIdentifierPrefix: prefix))
            XCTAssertFalse(ProfileFitness.permits(bundleIdentifier: "com.example.app", profileApplicationIdentifier: prefix + "." + pattern, applicationIdentifierPrefix: team))
        }
        XCTAssertEqual(ProfileFitness.rewrittenIdentifier(profileApplicationIdentifier: prefix + ".com.example.*", applicationIdentifierPrefix: prefix, original: "other.app"), "com.example.app")
    }
    func testKeychainPrefixIsIndependentOfTeamAndNeverBroadensTheGrant() {
        let requested: [String: Any] = ["keychain-access-groups": [team + ".com.example.app"]]
        let granted: [String: Any] = ["keychain-access-groups": [prefix + ".com.example.*"]]
        let result = EntitlementsPolicy.resolve(requested: requested, profile: granted, teamID: team, resolvedApplicationIdentifier: prefix + ".com.example.app", applicationIdentifierPrefix: prefix)
        XCTAssertEqual(result.entitlements["com.apple.developer.team-identifier"] as? String, team)
        XCTAssertEqual(result.entitlements["keychain-access-groups"] as? [String], [prefix + ".com.example.app"])
        XCTAssertTrue(EntitlementsPolicy.unmet(requested: requested, profile: granted, teamID: team, applicationIdentifierPrefix: prefix).isEmpty)
        let denied = EntitlementsPolicy.resolve(requested: ["keychain-access-groups": ["other.group"]], profile: granted, teamID: team, resolvedApplicationIdentifier: prefix + ".com.example.app", applicationIdentifierPrefix: prefix)
        XCTAssertNil(denied.entitlements["keychain-access-groups"])
    }
    func testSignedBundleAndNestedEntitlementsUsePrefixWhileCodeDirectoryKeepsTeam() throws {
        let app = try makeWorkingApp(); defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let credentials = try TestCredentials(), profile = try ProvisioningProfile.parse(bytes())
        var options = SigningOptions()
        options.requestedEntitlements = ["application-identifier": team + ".dev.localsigner.testapp", "keychain-access-groups": [team + ".dev.localsigner.testapp"]]
        let result = try BundleSigner.sign(appDirectory: app, identity: credentials.signer, certificateTeamID: credentials.loaded.teamID, profile: profile, options: options)
        XCTAssertTrue(result.warnings.contains { $0.contains("keychain data") })
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).passed)
        for (path, identifier) in [("SigningTestApp", "dev.localsigner.testapp"), ("PlugIns/TestExt.appex/TestExt", "dev.localsigner.testapp.TestExt")] {
            let image = try MachO(Data(contentsOf: app.appendingPathComponent(path)))
            let signature = try XCTUnwrap(image.existingSignature)
            let entitlements = try XCTUnwrap(BlobReader.entitlements(inSignature: image.data[signature.offset..<(signature.offset + signature.size)]))
            XCTAssertEqual(entitlements["application-identifier"] as? String, prefix + "." + identifier)
            XCTAssertEqual(entitlements["com.apple.developer.team-identifier"] as? String, team)
        }
        #if os(macOS)
        let verify = Process.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-vv", app.path])
        XCTAssertEqual(verify.status, 0, verify.output)
        let description = Process.run("/usr/bin/codesign", ["-d", "--verbose=4", app.path])
        XCTAssertTrue(description.output.contains("TeamIdentifier=" + team), description.output)
        #endif
    }
    func testKeepIDAndRenameModesUseDistinctAppPrefix() throws {
        let credentials = try TestCredentials()
        for keep in [true, false] {
            let app = try makeWorkingApp(); defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
            // A single-bundle fixture isolates fixed-ID keep/rename behavior.
            try FileManager.default.removeItem(at: app.appendingPathComponent("PlugIns"))
            let profile = try ProvisioningProfile.parse(bytes(pattern: "com.example.renamed"))
            var options = SigningOptions(); options.keepBundleIdentifier = keep; options.rewriteBundleIdentifier = !keep
            let result = try BundleSigner.sign(appDirectory: app, identity: credentials.signer, certificateTeamID: credentials.loaded.teamID, profile: profile, options: options)
            XCTAssertEqual(result.bundleIdentifierChanges.isEmpty, keep)
            let image = try MachO(Data(contentsOf: app.appendingPathComponent("SigningTestApp"))), signature = try XCTUnwrap(image.existingSignature)
            let entitlements = try XCTUnwrap(BlobReader.entitlements(inSignature: image.data[signature.offset..<(signature.offset + signature.size)]))
            XCTAssertEqual(entitlements["application-identifier"] as? String, prefix + ".com.example.renamed")
            XCTAssertEqual(entitlements["com.apple.developer.team-identifier"] as? String, team)
        }
    }
}
