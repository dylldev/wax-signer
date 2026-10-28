import CredentialKit
import IPAKit
import XCTest
@testable import SigningKit

final class IPASignerTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("ipasigner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func sign(_ ipa: URL, p12: Data = FixtureData.p12ValidLegacy, profile: Data = FixtureData.profileWildcardAll,
                      options: SigningOptions = SigningOptions(), edits: AppEdits = AppEdits()) throws -> IPASigningOutcome {
        let creds = try TestCredentials(p12: p12)
        return try IPASigner.sign(ipa: ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                  profiles: ProfileSet(single: try ProvisioningProfile.parse(profile)), options: options, edits: edits,
                                  output: work.appendingPathComponent("signed.ipa"), workDirectory: work)
    }

    func testSignsAnIPAWithTheLibraryOnly() throws {
        let out = try sign(Fixtures.ipa)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.output.path))
        XCTAssertFalse(out.inputArchive.hasCodeSignature)
        XCTAssertTrue(out.outputArchive.hasCodeSignature)
        XCTAssertTrue(out.outputArchive.hasEmbeddedProfile)
        XCTAssertEqual(out.signing.items.map(\.kind), [.framework, .appExtension, .app])
        XCTAssertTrue(out.selfCheck.passed, "\(out.selfCheck.failures)")
        XCTAssertEqual(out.outputArchive.bundleIdentifier, out.inputArchive.bundleIdentifier)
    }

    func testSigningOptionsChangeTheAppAndStillPassTheSelfCheck() throws {
        var e = AppEdits(); e.displayName = "Renamed"; e.bundleIdentifier = "com.edited.app"; e.removeExtensions = true
        let out = try sign(Fixtures.ipa, edits: e)
        XCTAssertEqual(out.outputArchive.bundleIdentifier, "com.edited.app")
        XCTAssertEqual(out.outputArchive.displayName, "Renamed")
        XCTAssertEqual(out.signing.items.map(\.kind), [.framework, .app], "the extension was removed before signing")
        XCTAssertTrue(out.selfCheck.passed, "\(out.selfCheck.failures)")
        XCTAssertFalse(out.editNotes.isEmpty)
    }

    func testNoSigningOptionsLeaveTheOutputUnchangedAndNoNotes() throws {
        let out = try sign(Fixtures.ipa)
        XCTAssertTrue(out.editNotes.isEmpty)
        XCTAssertEqual(out.outputArchive.bundleIdentifier, out.inputArchive.bundleIdentifier)
    }

    func testDefaultsKeepOnlyTheSwitchesNotPerAppFields() {
        var e = AppEdits(); e.displayName = "X"; e.bundleIdentifier = "a.b"; e.version = "1"; e.minimumOSVersion = "15.0"
        e.removeURLSchemes = true; e.enableProMotion = true
        let d = e.defaultsOnly()
        XCTAssertNil(d.displayName); XCTAssertNil(d.bundleIdentifier); XCTAssertNil(d.version); XCTAssertNil(d.minimumOSVersion)
        XCTAssertTrue(d.removeURLSchemes); XCTAssertTrue(d.enableProMotion)
    }

    func testWorkDirectoryIsCleanedUp() throws {
        _ = try sign(Fixtures.ipa)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: work.path).filter { $0.hasPrefix("sign-") }
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testPreparationDoesNotChangeIPAAndSigningReusesItsWorktree() throws {
        let creds = try TestCredentials()
        let profiles = ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll))
        let sourceBefore = try Data(contentsOf: Fixtures.ipa)
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: profiles, workDirectory: work)
        XCTAssertTrue(prepared.preflight.canContinue, "\(prepared.preflight.findings)")
        XCTAssertEqual(try Data(contentsOf: Fixtures.ipa), sourceBefore)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.path).contains { $0.hasPrefix("Wax-PreparedSigning-") })

        let output = work.appendingPathComponent("prepared-signed.ipa")
        let result = try IPASigner.sign(prepared: prepared, output: output)
        XCTAssertTrue(result.selfCheck.passed, "\(result.selfCheck.failures)")
        XCTAssertEqual(try Data(contentsOf: Fixtures.ipa), sourceBefore)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: work.path).contains { $0.hasPrefix("Wax-PreparedSigning-") })
    }

    func testFinishedTreesAreDeletedInTheBackgroundAndLeftoversSweptLater() throws {
        let creds = try TestCredentials()
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll)),
                                            workDirectory: work)
        prepared.discard()
        func scratch() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: work.path).filter { $0.hasPrefix("Wax-") }
        }
        let deadline = Date().addingTimeInterval(10)
        while try !scratch().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(try scratch(), [], "a discarded tree must be gone soon after, not left behind")

        let leftover = work.appendingPathComponent("Wax-Trash-stale", isDirectory: true)     // app suspended mid-delete
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        IPASigner.removeStalePreparations(in: work)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    func testPreparationExposesThePlannedProfileAndFinalBundleIDPerBundle() throws {
        let creds = try TestCredentials()
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll)),
                                            workDirectory: work)
        defer { prepared.discard() }
        let main = try XCTUnwrap(prepared.preflight.selections.first { $0.bundlePath == "." }, "\(prepared.preflight.selections)")
        XCTAssertFalse(main.bundleIdentifier.isEmpty)
        XCTAssertEqual(main.profileName, try ProvisioningProfile.parse(FixtureData.profileWildcardAll).info.name)
        XCTAssertGreaterThan(prepared.preflight.selections.count, 1, "the fixture's extension has its own selection")
    }

    func testPreparationReportsEditsAndUsesTheEditedMinimumOSVersion() throws {
        let creds = try TestCredentials()
        var edits = AppEdits()
        edits.minimumOSVersion = "99.0"
        edits.displayName = "Reviewed name"
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll)),
                                            edits: edits, workDirectory: work)
        defer { prepared.discard() }
        XCTAssertEqual(prepared.minimumOSVersion, "99.0")
        XCTAssertTrue(prepared.preflight.findings.contains { $0.id == "app-edits" && $0.status == .warning
            && $0.detail.contains("Reviewed name") && $0.detail.contains("99.0") })
    }

    func testDiscardRemovesPreparedTreeAndStaleCleanupLeavesUnrelatedDirectoriesAlone() throws {
        let creds = try TestCredentials()
        let profiles = ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll))
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: profiles, workDirectory: work)
        prepared.discard()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: work.path).contains { $0.hasPrefix("Wax-PreparedSigning-") })

        let stale = work.appendingPathComponent("Wax-PreparedSigning-stale", isDirectory: true)
        let unrelated = work.appendingPathComponent("user-data", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        IPASigner.removeStalePreparations(in: work)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testBlockedPreparationCannotWriteOutput() throws {
        let creds = try TestCredentials()
        let prepared = try IPASigner.prepare(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                            profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileExactTestExt)),
                                            workDirectory: work)
        XCTAssertFalse(prepared.preflight.canContinue)
        let output = work.appendingPathComponent("blocked.ipa")
        XCTAssertThrowsError(try IPASigner.sign(prepared: prepared, output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRefusalWritesNoOutput() throws {
        XCTAssertThrowsError(try sign(Fixtures.ipa, profile: FixtureData.profileExactTestExt))   // cannot sign the main app
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("signed.ipa").path))
    }

    func testRejectsANonIPABeforeDoingAnyWork() throws {
        let junk = work.appendingPathComponent("junk.ipa")
        try Data("not a zip".utf8).write(to: junk)
        XCTAssertThrowsError(try sign(junk)) { XCTAssertEqual($0 as? IPAError, .notAZip) }
    }

    #if os(macOS)
    func testOutputPassesAppleCodesignAfterNativeRepack() throws {
        let out = try sign(Fixtures.ipa)
        let dir = work.appendingPathComponent("check")
        try IPAExtractor.extract(ipa: out.output, to: dir)
        let r = Process.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-vv",
                                                  dir.appendingPathComponent("Payload/SigningTestApp.app").path])
        XCTAssertEqual(r.status, 0, r.output)
    }

    func testSystemUnzipAcceptsTheSignedArchive() throws {
        let out = try sign(Fixtures.ipa)
        let r = Process.run("/usr/bin/unzip", ["-tq", out.output.path])
        XCTAssertEqual(r.status, 0, r.output)
    }
    #endif

    func testSigningTwiceReplacesTheOutputWithAValidIPA() throws {
        let first = try sign(Fixtures.ipa)
        let firstBytes = try Data(contentsOf: first.output)
        var e = AppEdits(); e.version = "9.9.9"
        let second = try sign(Fixtures.ipa, edits: e)
        XCTAssertEqual(second.output, first.output)
        XCTAssertNotEqual(try Data(contentsOf: second.output), firstBytes)
        XCTAssertEqual(try IPAInspector.inspect(url: second.output).version, "9.9.9")
    }

    func testExistingOutputSurvivesWhenTheReplacementCannotBeWritten() throws {
        let first = try sign(Fixtures.ipa)
        let before = try Data(contentsOf: first.output)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: work.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.path) }
        var e = AppEdits(); e.version = "9.9.9"
        _ = try? sign(Fixtures.ipa, edits: e)
        XCTAssertEqual(try Data(contentsOf: first.output), before, "the previous signed IPA must not be lost")
    }
    func testMutationAfterSelfCheckCannotReachPublishedIPA() throws {
        let first = try sign(Fixtures.ipa)
        let previous = try Data(contentsOf: first.output)
        let creds = try TestCredentials(p12: FixtureData.p12ValidLegacy)
        for resource in ["SigningTestApp", "_CodeSignature/CodeResources"] {
            var changed = false
            XCTAssertThrowsError(try IPASigner.sign(ipa: Fixtures.ipa, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                profiles: ProfileSet(single: try ProvisioningProfile.parse(FixtureData.profileWildcardAll)),
                output: first.output, workDirectory: work, progress: { state in
                    guard state.message == "Packing…", !changed else { return }
                    let jobs = try! FileManager.default.contentsOfDirectory(at: self.work, includingPropertiesForKeys: nil)
                    let job = jobs.first { $0.lastPathComponent.hasPrefix("sign-") || $0.lastPathComponent.hasPrefix("Wax-PreparedSigning-") }!
                    let file = job.appendingPathComponent("tree/Payload/SigningTestApp.app/" + resource)
                    try! Data("changed after verification".utf8).write(to: file)
                    changed = true
                })) { error in
                    guard case IPAError.integrity = error else { return XCTFail("expected integrity rejection, got \(error)") }
                }
            XCTAssertTrue(changed)
            XCTAssertEqual(try Data(contentsOf: first.output), previous)
        }
    }

}
