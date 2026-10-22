import Foundation
import CredentialKit
import InstallKit
import IPAKit
import SourcesKit
import XCTest
@testable import LocalIPASigner

@MainActor
final class SourceAppDetailsTests: XCTestCase {
    private func app(url: String = "https://downloads.example.test/app.ipa?token=private", bundle: String = "com.example.app", version: String = "1", size: Int? = 10,
                     summary: String = "A description", developer: String = "A developer") -> SourceApp {
        SourceApp(id: "same@1", name: "App", bundleID: bundle, version: version, size: size, iconURL: nil,
                  downloadURL: URL(string: url)!, date: nil, summary: summary, developer: developer)
    }
    private func entry(bundle: String = "com.example.app", version: String = "1", size: Int = 10) throws -> LibraryEntry {
        let value: [String: Any] = ["id": UUID().uuidString, "kind": "unsigned", "name": "Inspected", "bundleID": bundle,
            "version": version, "size": size, "added": 0, "fileName": "fixture.ipa", "build": "42", "sha256": String(repeating: "a", count: 64)]
        return try JSONDecoder().decode(LibraryEntry.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testSourceDescriptionAndDeveloperAreVisibleWithoutTreatingThemAsVerified() {
        let details = SourceAppDetails(app: app(), saved: nil)
        XCTAssertEqual(details.advertised.first { $0.title == "Developer" }?.value, "A developer")
        XCTAssertEqual(details.advertised.first { $0.title == "Description" }?.value, "A description")
        XCTAssertTrue(details.saved.isEmpty); XCTAssertTrue(details.differences.isEmpty)
    }
    func testDownloadAddressNeverExposesQueryCredentialsOrPaths() {
        let details = SourceAppDetails(app: app(url: "https://user:password@downloads.example.test/private-token.ipa?token=secret#private"), saved: nil)
        XCTAssertEqual(details.advertised.first { $0.title == "Download host" }?.value, "downloads.example.test")
        let values = details.advertised.map(\.value).joined()
        for secret in ["password", "private-token", "secret"] { XCTAssertFalse(values.contains(secret)) }
    }
    func testLongUnicodeClaimsAreDisplayBoundedWithoutMutatingSource() {
        let source = app(summary: String(repeating: "🕯️", count: 20_000), developer: String(repeating: "d", count: 4000))
        let details = SourceAppDetails(app: source, saved: nil)
        XCTAssertTrue(details.advertised.first { $0.title == "Description" }!.value.hasSuffix("(display shortened)"))
        XCTAssertLessThan(details.advertised.first { $0.title == "Description" }!.value.count, 16_500)
        XCTAssertLessThan(details.advertised.first { $0.title == "Developer" }!.value.count, 2100)
        XCTAssertEqual(source.summary.count, 20_000)
    }
    func testCommittedMetadataComparisonUsesActualFieldsAndBuildAndHash() throws {
        let equal = SourceAppDetails(app: app(), saved: try entry())
        XCTAssertTrue(equal.differences.isEmpty)
        XCTAssertEqual(equal.saved.first { $0.title == "Inspected build" }?.value, "42")
        XCTAssertEqual(equal.saved.first { $0.title == "Saved IPA SHA-256" }?.value, String(repeating: "a", count: 64))
        let different = SourceAppDetails(app: app(), saved: try entry(bundle: "different.id", version: "2", size: 11))
        XCTAssertEqual(different.differences.count, 3)
    }
    func testUnknownSizeAndVersionAreNotFabricatedMismatchEvidence() throws {
        let details = SourceAppDetails(app: app(version: "", size: -1), saved: try entry())
        XCTAssertTrue(details.differences.isEmpty)
        XCTAssertEqual(details.advertised.first { $0.title == "Advertised size" }?.value, "Not provided")
    }
    func testSavedAssociationRequiresExactCommittedDownloadKeyAndSurvivesNoMetadataGuessing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-details-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Bundle(for: Self.self).url(forResource: "TestApp", withExtension: "ipa")!
        let library = LibraryModel(library: IPALibrary(root: root.appendingPathComponent("shelf")), announce: { _ in }, load: false)
        let credentials = CredentialsModel(store: try CredentialStore(directory: root.appendingPathComponent("credentials")))
        let signing = SigningModel(credentials: credentials, library: library), router = Router()
        let model = SourcesModel(sourceStore: SourceStore(directory: root.appendingPathComponent("sources")), download: { _, directory in
            let output = directory.appendingPathComponent("download.ipa")
            try FileManager.default.copyItem(at: fixture, to: output); return output
        }, announce: { _ in })
        let source = UUID(), item = app()
        XCTAssertNil(model.savedEntry(item, source: source, library: library))
        await model.get(item, from: source, signAfter: false, library: library, signing: signing, router: router)?.value
        let saved = try XCTUnwrap(model.savedEntry(item, source: source, library: library))
        XCTAssertEqual(saved.bundleID, try IPAInspector.inspect(url: fixture).bundleIdentifier)
        XCTAssertNil(model.savedEntry(item, source: UUID(), library: library))
        XCTAssertNil(model.savedEntry(app(url: "https://other.example/app.ipa"), source: source, library: library))
        await library.remove(saved)
        XCTAssertNil(model.savedEntry(item, source: source, library: library)); XCTAssertFalse(model.isFiled(item, source: source, library: library))
    }
}
