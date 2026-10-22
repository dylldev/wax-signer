import XCTest
@testable import LocalIPASigner

final class PickerCopyCleanupTests: XCTestCase {
    private var base: URL!
    private var owned: URL { base.appendingPathComponent("owned-tmp") }
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("picker-boundary-\(UUID())")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }
    private func file(_ relative: String) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("valuable bytes".utf8).write(to: url); return url
    }
    func testOwnedCopyIsRemovedAfterItsCallerHasRetainedIt() throws {
        let copy = try file("owned-tmp/picked.ipa")
        discardPickerCopy(copy, within: owned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }
    func testExternalDirectoryNamedTmpDoesNotConferDeletionAuthority() throws {
        let original = try file("external/tmp/original.ipa")
        XCTAssertTrue(original.path.contains("/tmp/"), "structural witness for the former substring predicate")
        discardPickerCopy(original, within: owned)
        XCTAssertEqual(try Data(contentsOf: original), Data("valuable bytes".utf8))
    }
    func testPrefixSiblingIsNotInsideTheOwnedDirectory() throws {
        let original = try file("owned-tmp-sibling/original.ipa")
        discardPickerCopy(original, within: owned); XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
    func testTemporaryRootItselfCannotBeDeleted() throws {
        let copy = try file("owned-tmp/keep.ipa")
        discardPickerCopy(owned, within: owned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
    func testOwnedSymlinkToExternalFileIsNotUsedForCleanup() throws {
        let original = try file("external/original.ipa"), link = owned.appendingPathComponent("picked.ipa")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        discardPickerCopy(link, within: owned)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), original.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
    func testExternalLeafSymlinkToOwnedFileIsAlsoPreserved() throws {
        let copy = try file("owned-tmp/picked.ipa"), link = base.appendingPathComponent("external-link.ipa")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: copy)
        discardPickerCopy(link, within: owned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), copy.path)
    }
    func testSymlinkedParentEscapingTemporaryDirectoryCannotDeleteOriginal() throws {
        let original = try file("external/original.ipa"), alias = owned.appendingPathComponent("redirected")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original.deletingLastPathComponent())
        discardPickerCopy(alias.appendingPathComponent(original.lastPathComponent), within: owned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
}
