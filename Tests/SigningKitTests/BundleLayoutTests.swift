import XCTest
@testable import SigningKit

final class BundleLayoutTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func dir(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    private func found() -> [String] {
        BundleLayout.nestedBundles(in: root.appendingPathComponent("A.app")).map { String($0.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)) }
    }

    func testFindsExtensionsAndAppsInEveryContainer() throws {
        try dir("A.app/PlugIns/X.appex"); try dir("A.app/Watch/W.app"); try dir("A.app/AppClips/C.app")
        XCTAssertEqual(found(), ["A.app/PlugIns/X.appex", "A.app/AppClips/C.app", "A.app/Watch/W.app"])
    }

    func testFindsAnExtensionNestedInsideAWatchApp() throws {
        try dir("A.app/Watch/W.app/PlugIns/E.appex")
        XCTAssertEqual(found(), ["A.app/Watch/W.app", "A.app/Watch/W.app/PlugIns/E.appex"],
                       "an extension inside a Watch app must still be signed with its own profile")
    }

    func testASymlinkedBundleIsNotFollowed() throws {
        try dir("A.app/PlugIns")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("A.app/PlugIns/L.appex"),
                                                   withDestinationURL: root.appendingPathComponent("A.app"))
        XCTAssertEqual(found(), [], "a crafted link back to the app must not recurse forever or be signed")
    }
}
