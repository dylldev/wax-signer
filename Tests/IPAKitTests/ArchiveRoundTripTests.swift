import XCTest
@testable import IPAKit

final class ArchiveRoundTripTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func makeTree() throws -> URL {
        let root = dir.appendingPathComponent("src")
        let app = root.appendingPathComponent("Payload/Demo.app")
        try fm.createDirectory(at: app.appendingPathComponent("Frameworks/Lib.framework"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.example.demo", "CFBundleExecutable": "Demo", "CFBundleDisplayName": "Demo",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "7",
        ], format: .binary, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try Data((0..<100_000).map { UInt8($0 % 251) }).write(to: app.appendingPathComponent("Demo"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("Demo").path)
        try Data(count: 5 * 1024 * 1024).write(to: app.appendingPathComponent("zeros.bin"))
        var noise = Data(count: 1 * 1024 * 1024)
        noise.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        try noise.write(to: app.appendingPathComponent("noise.bin"))
        try Data("lib".utf8).write(to: app.appendingPathComponent("Frameworks/Lib.framework/Lib"))
        try Data().write(to: app.appendingPathComponent("empty"))
        try fm.createSymbolicLink(atPath: app.appendingPathComponent("link").path, withDestinationPath: "Frameworks/Lib.framework/Lib")
        return root
    }

    private func files(under root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])!
        for case let url as URL in e {
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            let rel = String(full.dropFirst(resolvedRoot.count + 1))
            if v.isSymbolicLink == true { out[rel] = Data(("-> " + (try fm.destinationOfSymbolicLink(atPath: url.path))).utf8) }
            else if v.isRegularFile == true { out[rel] = try Data(contentsOf: url) }
        }
        return out
    }

    func testRoundTripPreservesContentPermissionsAndSymlinks() throws {
        let src = try makeTree()
        let ipa = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: src, to: ipa)

        let meta = try IPAInspector.inspect(url: ipa)           // our own strict reader accepts what we wrote
        XCTAssertEqual(meta.bundleIdentifier, "com.example.demo")
        XCTAssertEqual(meta.version, "1.0")
        XCTAssertEqual(meta.build, "7")

        let out = dir.appendingPathComponent("dst")
        try IPAExtractor.extract(ipa: ipa, to: out)
        XCTAssertEqual(try files(under: out), try files(under: src))

        let exec = out.appendingPathComponent("Payload/Demo.app/Demo")
        let mode = (try fm.attributesOfItem(atPath: exec.path)[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(mode & 0o111, 0o111, "executable bit kept")
        let link = try fm.destinationOfSymbolicLink(atPath: out.appendingPathComponent("Payload/Demo.app/link").path)
        XCTAssertEqual(link, "Frameworks/Lib.framework/Lib")
    }

    func testCompressibleDataActuallyShrinks() throws {
        let src = try makeTree()
        let ipa = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: src, to: ipa)
        let size = (try fm.attributesOfItem(atPath: ipa.path)[.size] as? Int) ?? .max
        XCTAssertLessThan(size, 2 * 1024 * 1024, "5 MB of zeros must not be stored raw")
    }

    func testExtractedFilesAreIndependentlyVerifiedByCRC() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/Info.plist", Data("x".utf8), corruptCRC: true)
        let ipa = dir.appendingPathComponent("bad.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("o"))) {
            XCTAssertEqual($0 as? IPAError, .corruptEntry("Payload/Demo.app/Info.plist"))
        }
    }

    func testRefusesTraversalAndEscapingSymlinks() throws {
        for (name, build) in [
            ("dotdot", { (z: inout ZipFixture) in z.add("Payload/../evil", Data("x".utf8)) }),
            ("absolute", { (z: inout ZipFixture) in z.add("/tmp/evil", Data("x".utf8)) }),
            ("abs-link", { (z: inout ZipFixture) in
                z.add("Payload/Demo.app/l", Data("/etc".utf8)) { $0.unixMode = 0o120777 } }),
            ("up-link", { (z: inout ZipFixture) in
                z.add("Payload/Demo.app/l", Data("../../outside".utf8)) { $0.unixMode = 0o120777 } }),
        ] as [(String, (inout ZipFixture) -> Void)] {
            var z = ZipFixture()
            build(&z)
            let ipa = dir.appendingPathComponent("\(name).ipa")
            try z.write(to: ipa)
            let out = dir.appendingPathComponent("out-\(name)")
            XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: out), name)
            XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("evil").path))
            XCTAssertFalse(fm.fileExists(atPath: "/tmp/evil"), name)
        }
    }

    func testExtractionDoesNotWriteThroughAnExistingDestinationSymlink() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/file", Data("archive data".utf8))
        let ipa = dir.appendingPathComponent("symlink-target.ipa")
        try z.write(to: ipa)
        let outside = dir.appendingPathComponent("outside")
        try Data("keep me".utf8).write(to: outside)
        let out = dir.appendingPathComponent("existing-output")
        let file = out.appendingPathComponent("Payload/Demo.app/file")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: file, withDestinationURL: outside)

        try IPAExtractor.extract(ipa: ipa, to: out)

        XCTAssertEqual(try Data(contentsOf: outside), Data("keep me".utf8))
        XCTAssertEqual(try Data(contentsOf: file), Data("archive data".utf8))
    }

    func testEnforcesTheExpansionLimit() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/big", Data(count: 4096), deflate: true)
        let ipa = dir.appendingPathComponent("lim.ipa")
        try z.write(to: ipa)
        var limits = IPAExtractor.Limits()
        limits.maxTotalBytes = 1000
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("o"), limits: limits)) {
            guard case .unsupportedZip = $0 as? IPAError else { return XCTFail("\($0)") }
        }
    }

    func testDeflatedEntryLongerThanDeclaredIsRejectedDuringExtraction() throws {
        let big = Data((0..<1000).map { UInt8($0 & 0xff) })
        var z = ZipFixture()
        z.add("Payload/Demo.app/f", big, deflate: true) {
            $0.claimedUncompressed = 10
            $0.claimedCRC = CRC32.checksum(big.prefix(10))
        }
        let ipa = dir.appendingPathComponent("long.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("o"))) {
            XCTAssertEqual($0 as? IPAError, .corruptEntry("Payload/Demo.app/f"))
        }
    }

    func testArchivingWithoutPayloadFails() {
        XCTAssertThrowsError(try IPAArchiver.archive(directory: dir, to: dir.appendingPathComponent("x.ipa"))) {
            XCTAssertEqual($0 as? IPAError, .noApp)
        }
    }

    func testArchivingWithNonDirectoryPayloadFails() throws {
        try Data().write(to: dir.appendingPathComponent("Payload"))
        XCTAssertThrowsError(try IPAArchiver.archive(directory: dir, to: dir.appendingPathComponent("x.ipa"))) {
            XCTAssertEqual($0 as? IPAError, .noApp)
        }
    }

    #if os(macOS)
    private func run(_ path: String, _ args: [String], cwd: URL? = nil) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args; p.currentDirectoryURL = cwd
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try! p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self))
    }

    func testSystemUnzipAcceptsOurArchive() throws {
        let src = try makeTree()
        let ipa = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: src, to: ipa)
        let r = run("/usr/bin/unzip", ["-tq", ipa.path])
        XCTAssertEqual(r.0, 0, r.1)
        let listing = run("/usr/bin/unzip", ["-Z", ipa.path]).1
        XCTAssertTrue(listing.contains("Payload/Demo.app/Demo"), listing)
        XCTAssertTrue(listing.contains("-rwxr-xr-x") || listing.contains("-rwx"), "unix modes kept:\n\(listing)")
        XCTAssertTrue(listing.contains("lrwxr"), "symlink recorded as a link:\n\(listing)")
    }

    func testWeExtractWhatSystemZipWrote() throws {
        let src = try makeTree()
        let ipa = dir.appendingPathComponent("sys.ipa")
        XCTAssertEqual(run("/usr/bin/zip", ["-q", "-r", "-y", ipa.path, "Payload"], cwd: src).0, 0)
        let out = dir.appendingPathComponent("dst")
        try IPAExtractor.extract(ipa: ipa, to: out)
        XCTAssertEqual(try files(under: out), try files(under: src))
    }
    #endif

    // MARK: reusing the original archive's compressed bytes

    func testReuseCopiesUntouchedEntriesAndRecompressesChangedOnes() throws {
        let src = try makeTree()
        let original = dir.appendingPathComponent("original.ipa")
        try IPAArchiver.archive(directory: src, to: original)

        // Unpack, change one file and add one, then repack reusing the original.
        let tree = dir.appendingPathComponent("tree")
        try IPAExtractor.extract(ipa: original, to: tree)
        let app = tree.appendingPathComponent("Payload/Demo.app")
        try Data("changed".utf8).write(to: app.appendingPathComponent("Frameworks/Lib.framework/Lib"))
        try Data("new".utf8).write(to: app.appendingPathComponent("added.txt"))

        let out = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: tree, to: out, reusing: original)

        let result = dir.appendingPathComponent("result")
        try IPAExtractor.extract(ipa: out, to: result)
        XCTAssertEqual(try files(under: result), try files(under: tree), "contents must match the tree exactly")

        let before = try ZipArchive(url: original), after = try ZipArchive(url: out)
        func entry(_ z: ZipArchive, _ name: String) throws -> ZipEntry { try XCTUnwrap(z.entries.first { $0.name == name }, name) }
        for name in ["Payload/Demo.app/zeros.bin", "Payload/Demo.app/noise.bin", "Payload/Demo.app/Demo"] {
            let a = try entry(before, name), b = try entry(after, name)
            XCTAssertEqual(b.compressedSize, a.compressedSize, "\(name) should keep its original compressed bytes")
            XCTAssertEqual(b.crc32, a.crc32, name)
        }
        XCTAssertEqual(try after.data(for: try entry(after, "Payload/Demo.app/Frameworks/Lib.framework/Lib")), Data("changed".utf8))
        XCTAssertEqual(try after.data(for: try entry(after, "Payload/Demo.app/added.txt")), Data("new".utf8))
    }

    func testReuseWithAMissingOriginalFallsBackToCompressing() throws {
        let src = try makeTree()
        let out = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: src, to: out, reusing: dir.appendingPathComponent("nope.ipa"))
        XCTAssertEqual(try IPAInspector.inspect(url: out).bundleIdentifier, "com.example.demo")
    }
}
