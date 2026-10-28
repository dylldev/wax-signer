import XCTest
@testable import IPAKit

/// The cached resolver must give exactly the keys `FileKey.of` gives: signature coverage compares keys from both.
final class FileKeyTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("filekey-\(UUID().uuidString)")
        let real = root.appendingPathComponent("App.app/Real Folder/é")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("file.bin"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("App.app/Linked").path, withDestinationPath: "Real Folder")
        try FileManager.default.createSymbolicLink(atPath: real.appendingPathComponent("link").path, withDestinationPath: "file.bin")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testResolverGivesTheSameKeysAsFileKeyOf() {
        let resolver = FileKey.Resolver()
        let app = root.appendingPathComponent("App.app")
        let urls = [app.appendingPathComponent("Real Folder/é/file.bin"), app.appendingPathComponent("Linked/é/file.bin"),
                    app.appendingPathComponent("Real Folder/é/link"), app.appendingPathComponent("Real Folder/é"),
                    app.appendingPathComponent("Real Folder/é/missing")]
        for url in urls + urls {                      // twice: the second pass is served from the cache
            XCTAssertEqual(resolver.of(url), FileKey.of(url), url.path)
        }
        XCTAssertEqual(resolver.of(urls[0]), resolver.of(urls[1]), "a folder reached through a link is the same folder")
        XCTAssertTrue(resolver.of(urls[2]).hasSuffix("/é/link"), "the entry's own name is never resolved")
    }
}
