import XCTest
@testable import InstallKit

/// A signed shelf entry keeps what Wax signed it with, so later signings can be compared with it.
final class SigningRecordTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("signing-record-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    static func record(original: String = "com.example.app", final: String = "app.fit.example", team: String = "TEAM123456",
                       prefix: String = "TEAM123456", profile: UUID = UUID(), signedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> SigningRecord {
        SigningRecord(signedAt: signedAt, originalBundleID: original, finalBundleID: final, teamID: team, appIDPrefix: prefix,
                      certificateSHA1: "AB12", certificateExpires: Date(timeIntervalSince1970: 1_830_000_000),
                      profiles: [.init(id: profile, name: "Fixture", kind: "Ad Hoc", expires: Date(timeIntervalSince1970: 1_810_000_000))])
    }

    func testTheRecordSurvivesTheSignedShelfTransactionAndAReload() throws {
        let root = base.appendingPathComponent("Library"), lib = IPALibrary(root: root)
        let pending = try lib.reserve(kind: .signed, name: "Demo", provenance: .waxSigned)
        try Data("signed bytes".utf8).write(to: try lib.pendingURL(pending.id))
        let record = Self.record()
        try lib.setRecord(record, for: pending.id)
        _ = try lib.complete(pending.id, name: "Demo", version: "1.0", bundleID: "app.fit.example", build: "7", provenance: .waxSigned)
        let saved = try lib.commit(pending.id)
        XCTAssertEqual(saved.entry.record, record)
        XCTAssertEqual(IPALibrary(root: root).entries(.signed).first?.record, record, "the record must be in the saved index")
    }

    func testEntriesWithoutARecordStillLoad() throws {
        let root = base.appendingPathComponent("Library"), lib = IPALibrary(root: root)
        let file = base.appendingPathComponent("in.ipa"); try Data("x".utf8).write(to: file)
        _ = try lib.save(file: file, kind: .unsigned, name: "Demo", version: "1", bundleID: "com.demo", build: "1", provenance: .fileImport)
        let index = try String(contentsOf: root.appendingPathComponent("index.json"), encoding: .utf8)
        XCTAssertFalse(index.contains("record"), "an entry without a record must not write one, so older Wax versions read the index unchanged")
        XCTAssertNil(IPALibrary(root: root).entries(.unsigned).first?.record)
    }

    func testTheRecordHoldsNoSecretsOrPersonalNames() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.record()), as: UTF8.self)
        for key in ["password", "privateKey", "p12", "commonName", "udid", "token"] {
            XCTAssertFalse(json.lowercased().contains(key.lowercased()), "\(key) must never be stored: \(json)")
        }
    }
}
