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

    /// Two different names that land on the same file (through an in-archive symlink) would be written at the same time.
    func testTwoNamesThatResolveToTheSameFileAreRefused() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/sub/", Data()) { $0.unixMode = 0o040755 }
        z.add("Payload/Demo.app/l", Data("sub".utf8)) { $0.unixMode = 0o120777 }
        z.add("Payload/Demo.app/sub/f", Data("one".utf8), deflate: true)
        z.add("Payload/Demo.app/l/f", Data("two".utf8), deflate: true)
        let ipa = dir.appendingPathComponent("alias.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("out-alias")))
    }

    /// A file queued under one name must not be redirected by a symlink that a later entry plants at its real path.
    func testALaterSymlinkCannotRedirectAQueuedFile() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/sub/", Data()) { $0.unixMode = 0o040755 }
        z.add("Payload/Demo.app/l", Data("sub".utf8)) { $0.unixMode = 0o120777 }
        z.add("Payload/Demo.app/l/x", Data("queued".utf8), deflate: true)      // really sub/x
        z.add("Payload/Demo.app/sub/x", Data("other".utf8)) { $0.unixMode = 0o120777 }   // a link planted at sub/x
        let ipa = dir.appendingPathComponent("planted.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("out-planted")))
    }

    func testManyFilesExtractCorrectlyAndReportProgressOnce() throws {
        var z = ZipFixture()
        var expected: [String: Data] = [:]
        for i in 0..<300 {
            let body = Data((0..<(i * 97 % 9000)).map { UInt8(truncatingIfNeeded: $0 &* (i + 3)) })
            z.add("Payload/Demo.app/d\(i % 7)/f\(i).bin", body, deflate: i % 2 == 0)
            expected["Payload/Demo.app/d\(i % 7)/f\(i).bin"] = body
        }
        let ipa = dir.appendingPathComponent("many.ipa")
        try z.write(to: ipa)
        let out = dir.appendingPathComponent("out-many")
        let lock = NSLock()        // callbacks arrive from several worker threads
        var calls = 0
        var lastFraction = 0.0
        let names = try IPAExtractor.extract(ipa: ipa, to: out, progress: { _, _ in lock.lock(); calls += 1; lock.unlock() },
                                             byteProgress: { f in lock.lock(); lastFraction = max(lastFraction, f); lock.unlock() })
        XCTAssertEqual(Set(names), Set(expected.keys))
        XCTAssertEqual(calls, 300 + 0, "one progress call per entry")
        XCTAssertEqual(lastFraction, 1.0, accuracy: 0.0001)
        for (name, body) in expected { XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent(name)), body, name) }
    }

    func testOneCorruptFileAmongManyFailsTheWholeExtraction() throws {
        var z = ZipFixture()
        for i in 0..<100 { z.add("Payload/Demo.app/f\(i)", Data("file \(i)".utf8), deflate: true) }
        z.add("Payload/Demo.app/bad", Data("bad".utf8), corruptCRC: true)
        let ipa = dir.appendingPathComponent("corrupt.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("out-corrupt")))
    }

    /// Real frameworks link to siblings with `..`. That is fine while the target stays inside the app, never outside it.
    func testASymlinkWithDotDotThatStaysInsideTheAppIsAllowed() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/b/f", Data("target".utf8), deflate: true)
        z.add("Payload/Demo.app/a/l", Data("../b/f".utf8)) { $0.unixMode = 0o120777 }
        let ipa = dir.appendingPathComponent("inside.ipa")
        try z.write(to: ipa)
        let out = dir.appendingPathComponent("out-inside")
        XCTAssertNoThrow(try IPAExtractor.extract(ipa: ipa, to: out))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: out.appendingPathComponent("Payload/Demo.app/a/l").path), "../b/f")
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("Payload/Demo.app/a/l")), Data("target".utf8))
    }

    /// macOS-style versioned frameworks link through `Versions/Current`, itself a link. That is legitimate.
    func testAVersionedFrameworkLayoutWithLinksInTheMiddleIsAllowed() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/Frameworks/Foo.framework/Versions/A/Headers/h.h", Data("h".utf8), deflate: true)
        z.add("Payload/Demo.app/Frameworks/Foo.framework/Versions/Current", Data("A".utf8)) { $0.unixMode = 0o120777 }
        z.add("Payload/Demo.app/Frameworks/Foo.framework/Headers", Data("Versions/Current/Headers".utf8)) { $0.unixMode = 0o120777 }
        let ipa = dir.appendingPathComponent("versioned.ipa")
        try z.write(to: ipa)
        let out = dir.appendingPathComponent("out-versioned")
        XCTAssertNoThrow(try IPAExtractor.extract(ipa: ipa, to: out))
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("Payload/Demo.app/Frameworks/Foo.framework/Headers/h.h")), Data("h".utf8))
    }

    func testSymlinksThatClimbOutOfTheAppAreStillRefused() throws {
        for (i, target) in ["../../outside", "../../../x", "a/../../../x", "b/../../../Payload/Other.app/x", "../../"].enumerated() {
            var z = ZipFixture()
            z.add("Payload/Demo.app/a/l", Data(target.utf8)) { $0.unixMode = 0o120777 }
            let ipa = dir.appendingPathComponent("climb\(i).ipa")
            try z.write(to: ipa)
            XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("out-climb\(i)")), target)
        }
    }

    /// The text of a link target can look harmless while an earlier link in the archive moves where it really starts.
    func testAChainOfLinksCannotLeadOutOfTheApp() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/a/b/", Data()) { $0.unixMode = 0o040755 }
        z.add("Payload/Demo.app/a/b/x", Data("../..".utf8)) { $0.unixMode = 0o120777 }          // really the app folder itself
        z.add("Payload/Demo.app/a/b/x/l", Data("../../../q".utf8)) { $0.unixMode = 0o120777 }    // from there, three levels up
        let ipa = dir.appendingPathComponent("chain.ipa")
        try z.write(to: ipa)
        let out = dir.appendingPathComponent("out-chain")
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: out))
    }

    /// `x/..` means something different once `x` is a link to the app folder itself: the kernel goes above the app.
    func testDotDotAfterALinkThatPointsAtTheAppRootIsRefused() throws {
        var z = ZipFixture()
        z.add("Payload/Demo.app/x", Data(".".utf8)) { $0.unixMode = 0o120777 }
        z.add("Payload/Demo.app/l", Data("x/..".utf8)) { $0.unixMode = 0o120777 }
        let ipa = dir.appendingPathComponent("dotdot-link.ipa")
        try z.write(to: ipa)
        XCTAssertThrowsError(try IPAExtractor.extract(ipa: ipa, to: dir.appendingPathComponent("out-dotdot-link")))
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

    /// The CRC check is what stops stale bytes being reused: a big file edited without changing its size must be recompressed.
    func testASameSizeEditToABigFileIsNotReused() throws {
        let src = try makeTree()
        let original = dir.appendingPathComponent("original.ipa")
        try IPAArchiver.archive(directory: src, to: original)
        let tree = dir.appendingPathComponent("tree")
        try IPAExtractor.extract(ipa: original, to: tree)
        let big = tree.appendingPathComponent("Payload/Demo.app/zeros.bin")
        var edited = try Data(contentsOf: big)
        edited[edited.count / 2] = 0x7F                                   // same size, one byte different
        try edited.write(to: big)

        let out = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: tree, to: out, reusing: original)
        let result = dir.appendingPathComponent("result")
        try IPAExtractor.extract(ipa: out, to: result)
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("Payload/Demo.app/zeros.bin")), edited)
    }

    /// For installs the signed copy only travels inside the phone, so changed big files may be stored as they are
    /// (no deflate); everything must still unpack to the same bytes and the system unzip must accept it.
    func testStoringChangedBigFilesKeepsContentAndKeepsReusedEntriesCompressed() throws {
        let src = try makeTree()
        let original = dir.appendingPathComponent("original.ipa")
        try IPAArchiver.archive(directory: src, to: original)
        let tree = dir.appendingPathComponent("tree")
        try IPAExtractor.extract(ipa: original, to: tree)
        let changed = tree.appendingPathComponent("Payload/Demo.app/noise.bin")      // 1 MB: below the big-file threshold
        var data = try Data(contentsOf: tree.appendingPathComponent("Payload/Demo.app/zeros.bin"))
        data[10] = 0x55
        try data.write(to: tree.appendingPathComponent("Payload/Demo.app/zeros.bin"))   // 5 MB, edited: big and changed
        _ = changed

        let out = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: tree, to: out, reusing: original, compressChangedFiles: false)

        let after = try ZipArchive(url: out)
        func entry(_ name: String) throws -> ZipEntry { try XCTUnwrap(after.entries.first { $0.name == name }, name) }
        XCTAssertEqual(try entry("Payload/Demo.app/zeros.bin").method, 0, "the changed big file is stored, not deflated")
        XCTAssertEqual(try entry("Payload/Demo.app/zeros.bin").compressedSize, data.count)
        XCTAssertEqual(try entry("Payload/Demo.app/noise.bin").method, 8, "an unchanged file keeps its original compressed bytes")
        XCTAssertEqual(try entry("Payload/Demo.app/noise.bin").compressedSize,
                       try XCTUnwrap(try ZipArchive(url: original).entries.first { $0.name == "Payload/Demo.app/noise.bin" }).compressedSize,
                       "and they are the same bytes, not a recompression")

        let result = dir.appendingPathComponent("result")
        try IPAExtractor.extract(ipa: out, to: result)
        XCTAssertEqual(try files(under: result), try files(under: tree))

        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-tq", out.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "the system unzip must accept stored entries")
    }

    func testReuseWithAMissingOriginalFallsBackToCompressing() throws {
        let src = try makeTree()
        let out = dir.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: src, to: out, reusing: dir.appendingPathComponent("nope.ipa"))
        XCTAssertEqual(try IPAInspector.inspect(url: out).bundleIdentifier, "com.example.demo")
    }
}
