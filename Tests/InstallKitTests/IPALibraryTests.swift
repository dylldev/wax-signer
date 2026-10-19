import XCTest
@testable import InstallKit

final class IPALibraryTests: XCTestCase {
    private var root: URL!
    private var scratch: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ipalib-\(UUID().uuidString)")
        root = base.appendingPathComponent("Library")
        scratch = base.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func file(_ name: String, bytes: Int) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func testAddedFilesAreListedNewestFirstPerKind() throws {
        let lib = IPALibrary(root: root)
        let a = try lib.add(file: try file("a.ipa", bytes: 10), kind: .unsigned, name: "A", version: "1", bundleID: "com.a",
                            now: Date(timeIntervalSince1970: 100))
        let b = try lib.add(file: try file("b.ipa", bytes: 20), kind: .unsigned, name: "B", version: "1", bundleID: "com.b",
                            now: Date(timeIntervalSince1970: 200))
        _ = try lib.add(file: try file("c.ipa", bytes: 30), kind: .signed, name: "C", version: "1", bundleID: "com.c")
        XCTAssertEqual(lib.entries(.unsigned).map(\.id), [b.id, a.id])
        XCTAssertEqual(lib.entries(.signed).count, 1)
        XCTAssertEqual(try Data(contentsOf: lib.url(for: a)).count, 10)
    }

    func testExactDuplicateReusesStableEntryWithoutDeletingOriginal() throws {
        let lib = IPALibrary(root: root)
        let first = try lib.add(file: try file("a.ipa", bytes: 10), kind: .unsigned, name: "A", version: "1", bundleID: "com.a")
        let second = try lib.add(file: try file("a2.ipa", bytes: 10), kind: .unsigned, name: "A", version: "1", bundleID: "com.a")
        XCTAssertEqual(lib.entries(.unsigned).map(\.id), [second.id])
        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: first).path))
    }

    func testRemoveDeletesTheFileAndTheEntry() throws {
        let lib = IPALibrary(root: root)
        let e = try lib.add(file: try file("a.ipa", bytes: 10), kind: .signed, name: "A", version: "1", bundleID: "com.a")
        try lib.remove(e)
        XCTAssertTrue(lib.entries(.signed).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.url(for: e).path))
    }

    func testEntriesSurviveReloadAndMissingFilesAreDropped() throws {
        let lib = IPALibrary(root: root)
        let keep = try lib.add(file: try file("a.ipa", bytes: 10), kind: .unsigned, name: "A", version: "1", bundleID: "com.a")
        let gone = try lib.add(file: try file("b.ipa", bytes: 11), kind: .unsigned, name: "B", version: "1", bundleID: "com.b")
        try FileManager.default.removeItem(at: lib.url(for: gone))
        let reloaded = IPALibrary(root: root)
        XCTAssertEqual(reloaded.entries(.unsigned).map(\.id), [keep.id])
    }

    func testTotalBytesAndClear() throws {
        let lib = IPALibrary(root: root)
        _ = try lib.add(file: try file("a.ipa", bytes: 10), kind: .unsigned, name: "A", version: "1", bundleID: "com.a")
        _ = try lib.add(file: try file("b.ipa", bytes: 25), kind: .signed, name: "B", version: "1", bundleID: "com.b")
        XCTAssertEqual(lib.totalBytes(.unsigned), 10)
        XCTAssertEqual(lib.totalBytes(.signed), 25)
        try lib.clear(.signed)
        XCTAssertTrue(lib.entries(.signed).isEmpty)
        XCTAssertEqual(lib.totalBytes(.signed), 0)
        XCTAssertEqual(lib.entries(.unsigned).count, 1)
    }

    func testRemoveIndexWriteFailureKeepsEntryAndFile() throws {
        let lib = IPALibrary(root: root)
        let entry = try lib.add(file: try file("a.ipa", bytes: 10), kind: .signed, name: "A", version: "1", bundleID: "com.a")
        let indexURL = root.appendingPathComponent("index.json")
        let indexData = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: indexURL)
            try? indexData.write(to: indexURL)
        }

        XCTAssertThrowsError(try lib.remove(entry))
        XCTAssertEqual(lib.entries(.signed), [entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: entry).path))
    }

    func testClearIndexWriteFailureKeepsEntriesAndFiles() throws {
        let lib = IPALibrary(root: root)
        let entry = try lib.add(file: try file("a.ipa", bytes: 10), kind: .signed, name: "A", version: "1", bundleID: "com.a")
        let indexURL = root.appendingPathComponent("index.json")
        let indexData = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: indexURL)
            try? indexData.write(to: indexURL)
        }

        XCTAssertThrowsError(try lib.clear(.signed))
        XCTAssertEqual(lib.entries(.signed), [entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: entry).path))
    }
}

final class IPALibraryHardeningTests: XCTestCase {
    func testAnIndexEntryThatPointsOutsideTheShelfIsIgnored() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ipalib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("unsigned"), withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: base.appendingPathComponent("outside.ipa"))
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","kind":"unsigned","name":"X","version":"1","bundleID":"com.x","size":6,"added":0,"fileName":"../../outside.ipa"}]
        """
        try json.data(using: .utf8)!.write(to: root.appendingPathComponent("index.json"))
        let lib = IPALibrary(root: root)
        XCTAssertTrue(lib.entries(.unsigned).isEmpty)
    }
}
