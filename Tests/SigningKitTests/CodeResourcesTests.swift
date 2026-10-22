import CryptoKit
import XCTest
@testable import SigningKit

final class CodeResourcesTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cr-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func put(_ rel: String, _ data: Data) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Every sealed file's hash must be the real hash of that file's bytes, whatever order or thread computed it.
    func testEverySealedHashMatchesTheFileAndNothingIsMissing() throws {
        var expected: [String: Data] = [:]
        for i in 0..<250 {
            let body = Data((0..<(i * 131 % 20_000)).map { UInt8(truncatingIfNeeded: $0 &* (i + 5)) })
            let rel = "res/d\(i % 9)/file\(i).bin"
            try put(rel, body); expected[rel] = body
        }
        try put("Exec", Data("binary".utf8))
        try put("_CodeSignature/CodeResources", Data("old".utf8))
        try put("en.lproj/locversion.plist", Data("omitted".utf8))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "res/d0/file0.bin")

        let data = try CodeResources.build(bundleRoot: root, executable: "Exec")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let files = try XCTUnwrap(plist["files"] as? [String: Any])
        let files2 = try XCTUnwrap(plist["files2"] as? [String: Any])

        for (rel, body) in expected {
            XCTAssertEqual(files[rel] as? Data, Data(Insecure.SHA1.hash(data: body)), "sha1 \(rel)")
            XCTAssertEqual((files2[rel] as? [String: Any])?["hash2"] as? Data, Data(SHA256.hash(data: body)), "sha256 \(rel)")
        }
        XCTAssertNil(files["Exec"]); XCTAssertNil(files2["Exec"], "the executable is sealed by its CodeDirectory")
        XCTAssertNil(files["_CodeSignature/CodeResources"], "the bundle's own signature is not sealed")
        XCTAssertNil(files["en.lproj/locversion.plist"], "omitted by rule")
        XCTAssertEqual((files["link"] as? [String: Any])?["symlink"] as? String, "res/d0/file0.bin")
        XCTAssertEqual(files.keys.filter { $0.hasPrefix("res/") }.count, expected.count)
    }
}
