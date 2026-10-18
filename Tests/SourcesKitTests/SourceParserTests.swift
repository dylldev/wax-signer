import XCTest
@testable import SourcesKit

final class SourceParserTests: XCTestCase {
    private func parse(_ json: String) throws -> SourceRepo { try SourceParser.parse(Data(json.utf8)) }

    private let versionsLayout = """
    {"name":"Test Repo","apps":[
     {"name":"Alpha","bundleIdentifier":"com.a.alpha","developerName":"Dev","localizedDescription":"Alpha app","iconURL":"https://e.test/a.png",
      "versions":[{"version":"1.0","date":"2026-01-01T10:00:00Z","size":1000,"downloadURL":"https://e.test/a1.ipa"},
                  {"version":"2.0","date":"2026-03-01T10:00:00.123Z","size":2000,"downloadURL":"https://e.test/a2.ipa"}]},
     {"name":"NoDownload","bundleIdentifier":"com.a.nodl","versions":[{"version":"1","date":"2026-01-01T00:00:00Z"}]},
     {"name":"StringSize","bundleIdentifier":"com.a.str","versions":[{"version":"1","size":"1234","downloadURL":"https://e.test/s.ipa"}]}
    ]}
    """

    func testVersionsLayoutPicksNewestVersionWithADownload() throws {
        let repo = try parse(versionsLayout)
        XCTAssertEqual(repo.name, "Test Repo")
        let alpha = try XCTUnwrap(repo.apps.first { $0.bundleID == "com.a.alpha" })
        XCTAssertEqual(alpha.version, "2.0")
        XCTAssertEqual(alpha.downloadURL.absoluteString, "https://e.test/a2.ipa")
        XCTAssertEqual(alpha.size, 2000)
        XCTAssertEqual(alpha.summary, "Alpha app")
        XCTAssertEqual(alpha.iconURL?.absoluteString, "https://e.test/a.png")
        XCTAssertNotNil(alpha.date)
    }

    func testAnAbsurdSizeIsIgnoredNotATrap() throws {
        let repo = try parse("""
        {"apps":[{"name":"Big","bundleIdentifier":"com.a.big","versions":[{"version":"1","size":1e300,"downloadURL":"https://e.test/b.ipa"}]},
                 {"name":"Huge","bundleIdentifier":"com.a.huge","versions":[{"version":"1","size":99999999999999999999,"downloadURL":"https://e.test/h.ipa"}]},
                 {"name":"NaNish","bundleIdentifier":"com.a.n","versions":[{"version":"1","size":-1e999,"downloadURL":"https://e.test/n.ipa"}]}]}
        """)
        XCTAssertEqual(repo.apps.count, 3, "the apps still list; only the unusable size is dropped")
    }

    func testLegacyLayoutReadsAppLevelDownloadURL() throws {
        let repo = try parse("""
        {"name":"Flyinghead","apps":[{"name":"Flycast","bundleIdentifier":"com.flycast","version":"7.1","versionDate":"2026-02-02","size":50000,"downloadURL":"https://e.test/f.ipa"}]}
        """)
        XCTAssertEqual(repo.apps.count, 1)
        XCTAssertEqual(repo.apps[0].version, "7.1")
        XCTAssertEqual(repo.apps[0].downloadURL.absoluteString, "https://e.test/f.ipa")
        XCTAssertEqual(repo.apps[0].size, 50000)
    }

    func testAppsWithoutADownloadAreSkipped() throws {
        XCTAssertNil(try parse(versionsLayout).apps.first { $0.bundleID == "com.a.nodl" })
    }

    func testNullAndStringSizesAndMissingIconAreFine() throws {
        let repo = try parse("""
        {"name":"R","apps":[{"name":"X","bundleIdentifier":"com.x","iconURL":null,"versions":[{"version":"1","size":null,"downloadURL":"https://e.test/x.ipa"}]}]}
        """)
        XCTAssertNil(repo.apps[0].size); XCTAssertNil(repo.apps[0].iconURL)
        XCTAssertEqual(try parse(versionsLayout).apps.first { $0.bundleID == "com.a.str" }?.size, 1234)
    }

    func testDuplicateBundleIDsAreKeptAsSeparateRowsWithDistinctIDs() throws {
        let repo = try parse("""
        {"name":"R","apps":[
         {"name":"Dup","bundleIdentifier":"com.d","versions":[{"version":"1","downloadURL":"https://e.test/1.ipa"}]},
         {"name":"Dup","bundleIdentifier":"com.d","versions":[{"version":"1","downloadURL":"https://e.test/2.ipa"}]}]}
        """)
        XCTAssertEqual(repo.apps.count, 2)
        XCTAssertEqual(Set(repo.apps.map(\.id)).count, 2)
    }

    func testHTMLInsteadOfJSONThrowsNotJSON() {
        XCTAssertThrowsError(try parse("<html><body>Not found</body></html>")) { XCTAssertEqual($0 as? SourceError, .notJSON) }
    }

    func testJSONWithoutAppsThrowsNoApps() {
        XCTAssertThrowsError(try parse(#"{"name":"Empty"}"#)) { XCTAssertEqual($0 as? SourceError, .noApps) }
    }

    func testOnlyHTTPSDownloadsAreKept() throws {
        let repo = try parse("""
        {"name":"R","apps":[{"name":"Plain","bundleIdentifier":"com.p","versions":[{"version":"1","downloadURL":"http://e.test/p.ipa"}]}]}
        """)
        XCTAssertTrue(repo.apps.isEmpty)
    }
}
