import CredentialKit
import CryptoKit
import XCTest
@testable import SigningKit

final class ProfileSelectionTests: XCTestCase {
    private func parse(_ data: Data) throws -> ProvisioningProfile { try ProvisioningProfile.parse(data) }

    private func sign(_ app: URL, pool: [Data], overrides: [String: Data] = [:],
                      options: SigningOptions = SigningOptions()) throws -> SigningResult {
        let creds = try TestCredentials()
        let set = ProfileSet(pool: try pool.map(parse), overrides: try overrides.mapValues(parse))
        return try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                     profiles: set, options: options)
    }

    private func item(_ r: SigningResult, _ path: String) throws -> SignedItem {
        try XCTUnwrap(r.items.first { $0.relativePath == path }, "no item \(path)")
    }

    private let identityKeys = ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow"]

    func testPreflightReportsSelectedProfileWithoutSigningTheApp() throws {
        let app = try makeWorkingApp()
        let before = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        let creds = try TestCredentials()
        let report = BundleSigner.preflight(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileWildcardAll)))

        XCTAssertTrue(report.canContinue, "\(report.findings)")
        XCTAssertTrue(report.findings.contains { $0.status == .pass && $0.title.contains("profile fits") })
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Info.plist")), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path))
    }

    func testPreflightExplainsWhyOtherProfilesWereNotSelected() throws {
        let creds = try TestCredentials()
        let profiles = try [FixtureData.profileWildcardAll, FixtureData.profileTvOS, FixtureData.profileListsOtherCert].map(parse)
        let report = BundleSigner.preflight(appDirectory: try makeWorkingApp(), identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID, profiles: ProfileSet(pool: profiles))

        let selected = try XCTUnwrap(report.findings.first { $0.id == "profile-." })
        XCTAssertTrue(selected.evidence.contains("Fixture tvOS: is for tvOS, not iOS"), selected.evidence)
        XCTAssertTrue(selected.evidence.contains("does not list the signing certificate"), selected.evidence)
    }

    func testPreflightBlocksWhenTheProfileDoesNotListTheCertificate() throws {
        let creds = try TestCredentials()
        let report = BundleSigner.preflight(appDirectory: try makeWorkingApp(), identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileListsOtherCert)))

        XCTAssertFalse(report.canContinue)
        XCTAssertTrue(report.findings.contains { $0.status == .blocked && $0.detail.contains("does not list the signing certificate") },
                      "\(report.findings)")
    }

    func testABlockedPreflightStillExplainsDevicesAndRevocation() throws {
        let creds = try TestCredentials()
        let report = BundleSigner.preflight(appDirectory: try makeWorkingApp(), identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileListsOtherCert)))
        XCTAssertFalse(report.canContinue)
        XCTAssertTrue(report.findings.contains { $0.id == "device-membership" }, "\(report.findings)")
        XCTAssertTrue(report.findings.contains { $0.id == "revocation" }, "\(report.findings)")
    }

    func testPreflightDisclosesEntitlementsTheProfileWillDrop() throws {
        let creds = try TestCredentials()
        var options = SigningOptions()
        options.requestedEntitlements = ["com.apple.security.application-groups": ["group.fixture"]]
        let report = BundleSigner.preflight(appDirectory: try makeWorkingApp(), identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileWildcardAll)), options: options)

        XCTAssertTrue(report.canContinue)
        XCTAssertTrue(report.findings.contains { $0.status == .warning && $0.title.contains("permissions")
            && $0.detail.contains("com.apple.security.application-groups") }, "\(report.findings)")
    }

    // MARK: Profile kind

    func testPreflightWarnsWhenKeepingAnIdentifierTheProfileDoesNotPermit() throws {
        let creds = try TestCredentials()
        var options = SigningOptions()
        options.keepBundleIdentifier = true
        let report = BundleSigner.preflight(appDirectory: try makeWorkingApp(), identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileValidBER)), options: options)
        XCTAssertTrue(report.canContinue)
        XCTAssertTrue(report.findings.contains { $0.status == .warning && $0.id == "bundle-id-."
            && $0.evidence.contains("dev.localsigner.testapp")
            && $0.evidence.contains("com.example.fixture") })
        XCTAssertFalse(report.findings.contains { $0.detail.contains("permits this bundle ID") })
        // The text must tell the user the practical consequence and the way out (found on a real iPhone: a silent
        // refusal when updating an app that is already installed under another application identifier).
        let warning = try XCTUnwrap(report.findings.first { $0.id == "bundle-id-." })
        XCTAssertTrue(warning.detail.contains("already installed"), warning.detail)
        XCTAssertTrue(warning.detail.contains("Rename to fit"), warning.detail)
    }

    func testPreflightDisclosesAutomaticBundleIdentifierChanges() throws {
        let creds = try TestCredentials()
        let app = try makeWorkingApp()
        try FileManager.default.removeItem(at: app.appendingPathComponent("PlugIns"))
        var options = SigningOptions()
        options.rewriteBundleIdentifier = true
        let report = BundleSigner.preflight(appDirectory: app, identity: creds.signer,
                                            certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try parse(FixtureData.profileValidBER)), options: options)
        XCTAssertTrue(report.canContinue, "\(report.findings)")
        XCTAssertTrue(report.findings.contains { $0.id == "bundle-id-." && $0.status == .warning
            && $0.evidence.contains("dev.localsigner.testapp") && $0.evidence.contains("com.example.fixture") })
    }

    func testAppStoreProfileIsNotEligibleToSign() throws {
        let creds = try TestCredentials()
        let profile = try parse(FixtureData.profileAppStore)
        let why = ProfileSelector.eligibility(profile, leafSHA1: Insecure.SHA1.hash(data: creds.loaded.certificateDER).map { String(format: "%02X", $0) }.joined(), certificateTeam: creds.loaded.teamID, now: Date())
        XCTAssertEqual(why, .appStoreProfile)
        XCTAssertTrue(ProfileRejection.appStoreProfile.description.contains("App Store"))
    }

    func testSigningWithOnlyAnAppStoreProfileSaysWhy() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, pool: [FixtureData.profileAppStore])) {
            XCTAssertTrue($0.localizedDescription.contains("App Store"), $0.localizedDescription)
        }
    }

    func testDevelopmentProfileWinsOverAnAppStoreProfileForTheSameCertificate() throws {
        let app = try makeWorkingApp()
        let r = try sign(app, pool: [FixtureData.profileAppStore, FixtureData.profileWildcardAll])
        XCTAssertNotEqual(try item(r, ".").profileName, try parse(FixtureData.profileAppStore).info.name)
    }

    // MARK: Per-bundle selection

    func testEachBundleGetsItsOwnExactProfile() throws {
        let app = try makeWorkingApp()
        let r = try sign(app, pool: [FixtureData.profileExactTestApp, FixtureData.profileExactTestExt])

        XCTAssertEqual(try item(r, ".").profileName, "Fixture Exact")
        XCTAssertEqual(try item(r, "PlugIns/TestExt.appex").profileName, "Fixture Exact Ext")
        XCTAssertNil(try item(r, "Frameworks/TestKit.framework").profileName)

        let fm = FileManager.default
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision")), FixtureData.profileExactTestApp)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("PlugIns/TestExt.appex/embedded.mobileprovision")),
                       FixtureData.profileExactTestExt)
        XCTAssertFalse(fm.fileExists(atPath: app.appendingPathComponent("Frameworks/TestKit.framework/embedded.mobileprovision").path))
        XCTAssertEqual(r.profileSelections.count, 2)
        #if os(macOS)
        let v = Process.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-vv", app.path])
        XCTAssertEqual(v.status, 0, v.output)
        #endif
    }

    func testMostSpecificProfileWinsRegardlessOfOrder() throws {
        for pool in [[FixtureData.profileWildcardAll, FixtureData.profileExactTestApp],
                     [FixtureData.profileExactTestApp, FixtureData.profileWildcardAll]] {
            let r = try sign(try makeWorkingApp(), pool: pool)
            XCTAssertEqual(try item(r, ".").profileName, "Fixture Exact")
            XCTAssertEqual(try item(r, "PlugIns/TestExt.appex").profileName, "Fixture Wildcard", "exact profile cannot serve the extension")
        }
    }

    func testProfileGrantingMoreRequestedEntitlementsIsPreferred() throws {
        var o = SigningOptions()
        o.requestedEntitlements = ["com.apple.security.application-groups": ["group.com.example.shared"]]
        let r = try sign(try makeWorkingApp(), pool: [FixtureData.profileWildcardAll, FixtureData.profileRich], options: o)
        XCTAssertEqual(try item(r, ".").profileName, "Fixture Rich")
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }

    func testSelectionReportExplainsRejectedProfiles() throws {
        let r = try sign(try makeWorkingApp(), pool: [FixtureData.profileWildcardAll, FixtureData.profileTvOS, FixtureData.profileListsOtherCert])
        let main = try XCTUnwrap(r.profileSelections.first { $0.bundlePath == "." })
        XCTAssertEqual(main.profileName, "Fixture Wildcard")
        let reasons = main.rejected.map { "\($0.profile): \($0.reason)" }.joined(separator: "\n")
        XCTAssertTrue(reasons.contains("Fixture tvOS: is for tvOS, not iOS"), reasons)
        XCTAssertTrue(reasons.contains("does not list the signing certificate"), reasons)
    }

    // MARK: Keep the app's own bundle ID under a profile that names a different one

    func testKeepBundleIdentifierSignsWithTheProfilesOwnApplicationIdentifier() throws {
        let app = try makeWorkingApp()
        var o = SigningOptions()
        o.keepBundleIdentifier = true
        let r = try sign(app, pool: [FixtureData.profileValidBER], options: o)
        XCTAssertTrue(r.bundleIdentifierChanges.isEmpty, "\(r.bundleIdentifierChanges)")
        let info = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as? [String: Any]
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "dev.localsigner.testapp")
        XCTAssertEqual(try item(r, ".").profileName, "Fixture Dev Profile")
        let profile = try parse(FixtureData.profileValidBER)
        #if os(macOS)
        let e = Process.run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", app.path])
        XCTAssertTrue(e.output.contains(profile.info.applicationIdentifier), e.output)
        #endif
    }

    func testWithoutKeepTheSameProfileStillRefusesTheApp() throws {
        XCTAssertThrowsError(try sign(try makeWorkingApp(), pool: [FixtureData.profileValidBER]))
    }

    // MARK: Refusals, each with a specific reason

    func testPinnedProfileIsCheckedAndNeverQuietlyReplaced() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, pool: [FixtureData.profileWildcardAll],
                                      overrides: ["PlugIns/TestExt.appex": FixtureData.profileExactTestApp])) {
            guard case .appIdentifierMismatch(let bundle, let id, let profile) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(bundle, "PlugIns/TestExt.appex")
            XCTAssertEqual(id, "dev.localsigner.testapp.TestExt")
            XCTAssertEqual(profile, "FIXT123456.dev.localsigner.testapp")
        }
    }

    func testNoCompatibleProfileListsEveryReason() throws {
        let app = try makeWorkingApp()
        XCTAssertThrowsError(try sign(app, pool: [FixtureData.profileValidBER, FixtureData.profileTvOS, FixtureData.profileListsOtherCert])) {
            guard case .noCompatibleProfile(let bundle, let id, let reasons) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(bundle, ".")
            XCTAssertEqual(id, "dev.localsigner.testapp")
            XCTAssertEqual(reasons.count, 3)
            XCTAssertTrue(reasons.contains { $0.contains("does not permit dev.localsigner.testapp") }, "\(reasons)")
            XCTAssertTrue(reasons.contains { $0.contains("not iOS") }, "\(reasons)")
            XCTAssertTrue(reasons.contains { $0.contains("does not list the signing certificate") }, "\(reasons)")
        }
    }

    func testEmptyPoolSaysSo() throws {
        XCTAssertThrowsError(try sign(try makeWorkingApp(), pool: [])) {
            guard case .noCompatibleProfile(_, _, let reasons) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(reasons, ["no provisioning profiles were supplied"])
        }
    }

    func testExpiryIsEvaluatedAtSigningTime() throws {
        var o = SigningOptions()
        o.now = Date().addingTimeInterval(86400 * 365 * 3)
        XCTAssertThrowsError(try sign(try makeWorkingApp(), pool: [FixtureData.profileWildcardAll], options: o)) {
            guard case .profileRejected(_, let name, let reason) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertEqual(name, "Fixture Wildcard")
            XCTAssertTrue(reason.hasPrefix("expired on"), reason)
        }
    }

    func testWrongPlatformIsRejected() throws {
        XCTAssertThrowsError(try sign(try makeWorkingApp(), pool: [FixtureData.profileTvOS])) {
            guard case .profileRejected(_, _, let reason) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("not iOS"), reason)
        }
    }

    func testRefusalLeavesTheAppUntouched() throws {
        let app = try makeWorkingApp()
        let plistBefore = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        let exeBefore = try Data(contentsOf: app.appendingPathComponent("SigningTestApp"))
        XCTAssertThrowsError(try sign(app, pool: [FixtureData.profileExactTestApp]))   // extension not permitted
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Info.plist")), plistBefore)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("SigningTestApp")), exeBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("_CodeSignature").path))
    }

    // MARK: Entitlements are never added without a request and a grant

    func testProfileGrantsAreNotAddedUnlessRequested() throws {
        let r = try sign(try makeWorkingApp(), pool: [FixtureData.profileRich])
        // the rich profile also grants associated-domains and keychain groups, none were requested
        XCTAssertEqual(try item(r, ".").entitlementKeys, identityKeys.sorted())
        XCTAssertEqual(try item(r, "PlugIns/TestExt.appex").entitlementKeys, identityKeys.sorted())
    }

    func testRequestedAndGrantedEntitlementIsKept() throws {
        var o = SigningOptions()
        o.requestedEntitlements = ["com.apple.security.application-groups": ["group.com.example.shared", "group.com.example.team.a"]]
        let r = try sign(try makeWorkingApp(), pool: [FixtureData.profileRich], options: o)
        XCTAssertEqual(try item(r, ".").entitlementKeys, (identityKeys + ["com.apple.security.application-groups"]).sorted())
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testRequestedValueOutsideTheGrantIsDroppedNotWidened() throws {
        var o = SigningOptions()
        o.requestedEntitlements = ["com.apple.security.application-groups": ["group.com.example.shared", "group.someone.else"]]
        let r = try sign(try makeWorkingApp(), pool: [FixtureData.profileRich], options: o)
        XCTAssertEqual(try item(r, ".").entitlementKeys, identityKeys.sorted(), "partially granted list must not be signed")
        XCTAssertTrue(r.warnings.contains { $0.contains("com.apple.security.application-groups") }, "\(r.warnings)")
    }

    func testRejectPolicyTurnsUnmetEntitlementsIntoARefusal() throws {
        var o = SigningOptions()
        o.entitlementPolicy = .reject
        o.requestedEntitlements = ["aps-environment": "development"]
        XCTAssertThrowsError(try sign(try makeWorkingApp(), pool: [FixtureData.profileWildcardAll], options: o)) {
            guard case .profileRejected(_, _, let reason) = $0 as? SigningError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("does not grant requested entitlements: aps-environment"), reason)
        }
    }

    func testKeychainGroupsMoveOntoTheProfileTeam() {
        let t = EntitlementsPolicy.teamPrefixed(
            ["OLDTEAM123.com.example.shared", "com.example.plain", "FIXT123456.already"], teamID: "FIXT123456")
        XCTAssertEqual(t, ["FIXT123456.com.example.shared", "FIXT123456.com.example.plain", "FIXT123456.already"])
    }

    func testGrantMatchingRules() {
        let g = EntitlementsPolicy.granted
        XCTAssertTrue(g("k", ["a", "b"], ["k": ["a", "b", "c"]]))
        XCTAssertFalse(g("k", ["a", "z"], ["k": ["a", "b"]]))
        XCTAssertTrue(g("k", ["group.x.y"], ["k": ["group.x.*"]]))
        XCTAssertFalse(g("k", ["group.z.y"], ["k": ["group.x.*"]]))
        XCTAssertTrue(g("k", false, ["k": false]))
        XCTAssertFalse(g("k", true, ["k": false]))
        XCTAssertFalse(g("missing", "x", [:]))
        XCTAssertTrue(g("k", "development", ["k": "development"]))
        XCTAssertFalse(g("k", "production", ["k": "development"]))
    }
}

#if os(macOS)
extension Process {
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try! p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
#endif

final class SigningErrorMessageTests: XCTestCase {
    func testNoCompatibleProfileMessageIsPlainAndSuggestsTheFix() {
        let e = SigningError.noCompatibleProfile(
            bundle: ".", id: "com.example.thirdparty",
            reasons: ["P1: does not list the signing certificate", "P2: application identifier TEAM.app.fixed does not permit com.example.thirdparty"])
        let text = e.localizedDescription
        XCTAssertFalse(text.contains("sign ."), text)
        XCTAssertTrue(text.contains("the app (com.example.thirdparty)"), text)
        XCTAssertTrue(text.contains("Rename to fit"), text)
    }

    func testNoHintWhenTheBundleIDIsNotTheProblem() {
        let e = SigningError.noCompatibleProfile(bundle: "PlugIns/X.appex", id: "a.b.c", reasons: ["P1: expired on Jan 1"])
        XCTAssertFalse(e.localizedDescription.contains("Rename to fit"))
        XCTAssertTrue(e.localizedDescription.contains("PlugIns/X.appex"))
    }
}
