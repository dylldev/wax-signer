import XCTest
@testable import InstallKit

/// Before signing, Wax compares with the last copy it signed of the same app: update, separate app, or a team change.
final class IdentityContinuityTests: XCTestCase {
    private func entry(_ record: SigningRecord?, kind: LibraryEntry.Kind = .signed) -> LibraryEntry {
        LibraryEntry(id: UUID(), kind: kind, name: "Demo", version: "1", bundleID: record?.finalBundleID ?? "x", size: 1, added: Date(),
                     fileName: "f.ipa", sha256: nil, build: nil, provenance: .waxSigned, record: record)
    }
    private func record(original: String = "com.example.app", final: String = "app.fit.example", team: String = "TEAM1",
                        prefix: String = "TEAM1", at seconds: TimeInterval = 1_800_000_000) -> SigningRecord {
        SigningRecordTests.record(original: original, final: final, team: team, prefix: prefix, signedAt: Date(timeIntervalSince1970: seconds))
    }

    func testThePreviousCopyIsTheNewestSignedRecordOfTheSameApp() {
        let old = record(at: 1_700_000_000), newer = record(at: 1_800_000_000), other = record(original: "com.other", at: 1_900_000_000)
        let found = IdentityContinuity.previous(for: "com.example.app", in: [entry(old), entry(newer), entry(other), entry(nil)])
        XCTAssertEqual(found?.signedAt, newer.signedAt)
    }

    func testReSigningAWaxSignedCopyFindsTheCopyByItsSignedID() {
        // The shelf copy already carries the renamed ID; signing it again starts from that ID.
        XCTAssertNotNil(IdentityContinuity.previous(for: "app.fit.example", in: [entry(record())]))
    }

    func testNoPreviousCopyGivesNoAssessment() {
        XCTAssertNil(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "app.fit.example", teamID: "TEAM1",
                                               appIDPrefix: "TEAM1", entries: [entry(nil, kind: .unsigned)]))
    }

    func testSameIDAndTeamIsAnUpdate() throws {
        let a = try XCTUnwrap(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "app.fit.example",
                                                        teamID: "TEAM1", appIDPrefix: "TEAM1", entries: [entry(record())]))
        XCTAssertFalse(a.isWarning)
        XCTAssertTrue(a.title.lowercased().contains("update"), a.title)
    }

    func testADifferentFinalIDInstallsASeparateApp() throws {
        let a = try XCTUnwrap(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "com.example.app",
                                                        teamID: "TEAM1", appIDPrefix: "TEAM1", entries: [entry(record())]))
        XCTAssertTrue(a.isWarning)
        XCTAssertTrue(a.title.lowercased().contains("separate app"), a.title)
        XCTAssertTrue(a.detail.contains("app.fit.example") && a.detail.contains("com.example.app"), a.detail)
    }

    func testADifferentTeamOrPrefixWithTheSameIDWarnsAboutTheUpdateAndKeychain() throws {
        for (team, prefix) in [("TEAM2", "TEAM2"), ("TEAM1", "OLDPREFIX")] {
            let a = try XCTUnwrap(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "app.fit.example",
                                                            teamID: team, appIDPrefix: prefix, entries: [entry(record())]))
            XCTAssertTrue(a.isWarning, "\(team) \(prefix)")
            XCTAssertTrue(a.detail.lowercased().contains("keychain"), a.detail)
        }
    }

    func testUnknownTeamOnEitherSideIsNotReportedAsAChange() throws {
        let a = try XCTUnwrap(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "app.fit.example",
                                                        teamID: nil, appIDPrefix: nil, entries: [entry(record())]))
        XCTAssertFalse(a.isWarning, "missing evidence is not a change")
    }

    func testAnotherAppAlreadySignedWithTheSameFinalIDIsReplaced() throws {
        // Rename to fit with a one-app-ID profile gives every app that profile's ID: installing one replaces the other.
        var other = entry(record(original: "com.other.game", final: "app.fit.example"))
        other = LibraryEntry(id: other.id, kind: .signed, name: "Other Game", version: "1", bundleID: "app.fit.example", size: 1,
                             added: Date(), fileName: "o.ipa", sha256: nil, build: nil, provenance: .waxSigned, record: other.record)
        let a = try XCTUnwrap(IdentityContinuity.assess(originalBundleID: "com.example.app", finalBundleID: "app.fit.example",
                                                        teamID: "TEAM1", appIDPrefix: "TEAM1", entries: [other]))
        XCTAssertTrue(a.isWarning)
        XCTAssertTrue(a.title.lowercased().contains("replaces"), a.title)
        XCTAssertTrue(a.detail.contains("Other Game"), a.detail)
    }
}
