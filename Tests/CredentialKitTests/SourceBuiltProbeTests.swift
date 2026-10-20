#if os(iOS)
import CryptoKit
import XCTest

/// App-hosted only: fail if the build forgot to replace the excluded legacy resource.
final class SourceBuiltProbeTests: XCTestCase {
    func testBundledProbeMatchesItsSourceBuildManifest() throws {
        let ipa = try XCTUnwrap(Bundle.main.url(forResource: "WaxProbe", withExtension: "ipa"))
        let manifest = try XCTUnwrap(Bundle.main.url(forResource: "probe-build", withExtension: "json"))
        let data = try Data(contentsOf: manifest)
        let report = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(report["schemaVersion"] as? Int, 1)
        XCTAssertEqual(report["bundleIdentifier"] as? String, "io.github.dylldev.wax.probe")
        XCTAssertEqual(report["version"] as? String, "1.0")
        XCTAssertEqual(report["build"] as? String, "1")
        XCTAssertEqual(report["scheme"] as? String, "waxprobe")
        XCTAssertFalse((report["sources"] as? [String: String] ?? [:]).isEmpty)
        let handle = try FileHandle(forReadingFrom: ipa); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(report["ipaSHA256"] as? String, actual)
    }
}
#endif
