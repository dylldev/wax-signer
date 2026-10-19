#if os(macOS)
import XCTest
@testable import SigningKit

/// Builds real .deb files with the system's ar, tar and compressors, so the extractor is tested on the actual format.
final class DebExtractorTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("deb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    /// A compressed member with no bytes in it cannot be inflated. Returning an empty Data instead would let the
    /// caller carry on as though the tweak simply shipped no libraries.
    func testEmptyCompressedPayloadIsRejectedRatherThanSilentlyEmpty() {
        XCTAssertThrowsError(try DebExtractor.decompress(Data(), name: "tweak.xz")) { error in
            XCTAssertTrue((error as? SigningError)?.localizedDescription.contains("damaged") == true
                          || (error as? SigningError)?.localizedDescription.contains("data") == true,
                          "got \(error)")
        }
    }

    /// The real risk: a package that stopped downloading half way through must not install as though it were whole.
    func testTruncatedCompressedPayloadIsRejectedRatherThanYieldingPartialData() throws {
        let src = work.appendingPathComponent("payload.bin")
        try Data((0..<8192).map { UInt8($0 % 251) }).write(to: src)
        XCTAssertEqual(try run("/usr/bin/gzip", ["-k", "-f", src.path], in: work), 0, "gzip must be available")
        let full = try Data(contentsOf: work.appendingPathComponent("payload.bin.gz"))
        let truncated = Data(full.prefix(full.count / 2))
        XCTAssertThrowsError(try DebExtractor.decompress(truncated, name: "payload.bin.gz"),
                             "a half-downloaded package must not be accepted as complete")
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String], in dir: URL? = nil) throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        if let dir { p.currentDirectoryURL = dir }
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); return p.terminationStatus
    }

    private func dylibBytes() throws -> Data {
        try Data(contentsOf: Fixtures.appDirectory.appendingPathComponent("Frameworks/TestKit.framework/TestKit"))
    }

    /// A real dpkg-style `ar` archive (GNU member names: "name/"), written by hand.
    private func writeAr(_ members: [(name: String, data: Data)], to url: URL, bsd: Bool = false) throws {
        func cat(_ parts: [Data]) -> Data { parts.reduce(Data(), +) }      // arrays type-check quickly; long `+` chains do not on older compilers
        func field(_ s: String, _ n: Int) -> Data { Data((s + String(repeating: " ", count: max(0, n - s.count))).prefix(n).utf8) }
        var out = Data("!<arch>\n".utf8)
        if bsd {   // macOS ar starts with a symbol-table member
            let sym = Data("__.SYMDEF SORTED".utf8) + Data(count: 4) + Data(count: 8)
            out += cat([field("#1/20", 16), field("0", 12), field("0", 6), field("0", 6), field("100644", 8), field("\(sym.count)", 10), Data("`\n".utf8), sym])
        }
        for m in members {
            if bsd {
                let nameBytes = Data(m.name.utf8) + Data(count: (8 - m.name.utf8.count % 8) % 8 + 8)   // padded, NUL terminated
                let body = nameBytes + m.data
                out += cat([field("#1/\(nameBytes.count)", 16), field("0", 12), field("0", 6), field("0", 6), field("100644", 8), field("\(body.count)", 10), Data("`\n".utf8)])
                out += body
                if body.count % 2 == 1 { out += Data("\n".utf8) }
                continue
            }
            out += cat([field(m.name + "/", 16), field("0", 12), field("0", 6), field("0", 6), field("100644", 8), field("\(m.data.count)", 10), Data("`\n".utf8)])
            out += m.data
            if m.data.count % 2 == 1 { out += Data("\n".utf8) }
        }
        try out.write(to: url)
    }

    /// Makes a .deb whose data archive is compressed by `compress` (tool + args, producing `produced`) and stored as `storedAs`.
    private func makeDeb(storedAs: String, compress: (tool: String, args: [String], produced: String)?) throws -> URL {
        let root = work.appendingPathComponent("root-\(storedAs)")
        let lib = root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try dylibBytes().write(to: lib.appendingPathComponent("Tweak.dylib"))
        try Data("filter".utf8).write(to: lib.appendingPathComponent("Tweak.plist"))
        let build = work.appendingPathComponent("build-\(storedAs)")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try run("/usr/bin/tar", ["-cf", build.appendingPathComponent("control.tar").path, "-C", root.path, "--no-recursion", "."])
        try run("/usr/bin/tar", ["-cf", build.appendingPathComponent("data.tar").path, "-C", root.path, "."])
        var dataFile = "data.tar"
        if let c = compress {
            try run(c.tool, c.args + [build.appendingPathComponent("data.tar").path])
            dataFile = c.produced
        }
        let deb = work.appendingPathComponent("tweak-\(storedAs).deb")
        try writeAr([("debian-binary", Data("2.0\n".utf8)),
                     ("control.tar", try Data(contentsOf: build.appendingPathComponent("control.tar"))),
                     (storedAs, try Data(contentsOf: build.appendingPathComponent(dataFile)))], to: deb)
        return deb
    }

    private func assertExtracts(_ deb: URL) throws {
        let out = work.appendingPathComponent("out-\(UUID().uuidString)")
        let files = try DebExtractor.dylibs(inDeb: deb, to: out)
        XCTAssertEqual(files.map(\.lastPathComponent), ["Tweak.dylib"])
        XCTAssertEqual(try Data(contentsOf: files[0]), try dylibBytes())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Tweak.dylib"], "only dylibs are kept")
    }

    func testDebWithAGzipDataTarYieldsItsDylibs() throws { try assertExtracts(try makeDeb(storedAs: "data.tar.gz", compress: ("/usr/bin/gzip", ["-f"], "data.tar.gz"))) }

    func testDebWithAnXZDataTarYieldsItsDylibs() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/xz") else { throw XCTSkip("no xz on this machine") }
        try assertExtracts(try makeDeb(storedAs: "data.tar.xz", compress: ("/opt/homebrew/bin/xz", ["-f"], "data.tar.xz")))
    }

    func testDebWithAnUncompressedDataTarYieldsItsDylibs() throws { try assertExtracts(try makeDeb(storedAs: "data.tar", compress: nil)) }

    func testZstdDebIsRefusedClearly() throws {
        let deb = try makeDeb(storedAs: "data.tar.zst", compress: ("/usr/bin/gzip", ["-f"], "data.tar.gz"))
        XCTAssertThrowsError(try DebExtractor.dylibs(inDeb: deb, to: work.appendingPathComponent("o"))) {
            XCTAssertTrue($0.localizedDescription.lowercased().contains("zstd"), $0.localizedDescription)
        }
    }

    func testBSDStyleArchiveWithASymbolTableIsAlsoRead() throws {
        let tar = work.appendingPathComponent("bsd.tar")
        let root = work.appendingPathComponent("bsdroot/lib"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try dylibBytes().write(to: root.appendingPathComponent("Tweak.dylib"))
        try run("/usr/bin/tar", ["-cf", tar.path, "-C", work.appendingPathComponent("bsdroot").path, "."])
        let deb = work.appendingPathComponent("bsd.deb")
        try writeAr([("debian-binary", Data("2.0\n".utf8)), ("data.tar", try Data(contentsOf: tar))], to: deb, bsd: true)
        let files = try DebExtractor.dylibs(inDeb: deb, to: work.appendingPathComponent("bsdout"))
        XCTAssertEqual(files.map(\.lastPathComponent), ["Tweak.dylib"])
    }

    func testNotADebIsRefused() throws {
        let junk = work.appendingPathComponent("junk.deb"); try Data("hello world".utf8).write(to: junk)
        XCTAssertThrowsError(try DebExtractor.dylibs(inDeb: junk, to: work.appendingPathComponent("o")))
    }

    func testPathTraversalInsideTheArchiveCannotEscapeTheOutputFolder() throws {
        // A hand-built tar entry named "../../escaped.dylib".
        var header = Data(count: 512)
        let name = Data("../../escaped.dylib".utf8)
        header.replaceSubrange(0..<name.count, with: name)
        let body = try dylibBytes()
        header.replaceSubrange(124..<135, with: Data(String(format: "%011o", body.count).utf8))
        header[156] = UInt8(ascii: "0")
        header.replaceSubrange(148..<156, with: Data(repeating: 0x20, count: 8))
        let sum = header.reduce(0) { $0 + Int($1) }
        header.replaceSubrange(148..<155, with: Data(String(format: "%06o", sum).utf8) + Data([0]))
        var tar = header + body
        tar += Data(count: (512 - body.count % 512) % 512) + Data(count: 1024)
        let deb = work.appendingPathComponent("evil.deb")
        try writeAr([("debian-binary", Data("2.0\n".utf8)), ("data.tar", tar)], to: deb)
        let out = work.appendingPathComponent("safe/out")
        let files = (try? DebExtractor.dylibs(inDeb: deb, to: out)) ?? []
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("escaped.dylib").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("safe/escaped.dylib").path))
        for f in files { XCTAssertEqual(f.deletingLastPathComponent().path, out.path) }
    }
    func testMalformedArAndTarNeverCreateOutput() throws {
        let deb = work.appendingPathComponent("damaged.deb")
        let output = work.appendingPathComponent("untouched")
        for tar in [Data(), Data(count: 512), Data(repeating: 1, count: 1024)] {
            try writeAr([("data.tar", tar)], to: deb)
            XCTAssertThrowsError(try DebExtractor.dylibs(inDeb: deb, to: output)) {
                XCTAssertTrue($0 is SigningError)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
        // The negative BSD length previously reached a reversed Swift range.
        let header = "#1/-1".padding(toLength: 48, withPad: " ", startingAt: 0)
            + "0".padding(toLength: 10, withPad: " ", startingAt: 0) + "`\n"
        try (Data("!<arch>\n".utf8) + Data(header.utf8)).write(to: deb)
        XCTAssertThrowsError(try DebExtractor.dylibs(inDeb: deb, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testGzipCorruptionAndTrailingCompressedBytesAreRejected() throws {
        let src = work.appendingPathComponent("crc.bin")
        try Data("hello".utf8).write(to: src)
        XCTAssertEqual(try run("/usr/bin/gzip", ["-k", "-f", src.path], in: work), 0)
        let good = try Data(contentsOf: work.appendingPathComponent("crc.bin.gz"))
        XCTAssertEqual(try DebExtractor.decompress(good, name: "data.tar.gz"), Data("hello".utf8))
        for index in [good.count - 8, good.count - 4] {
            var bad = good; bad[index] ^= 1
            XCTAssertThrowsError(try DebExtractor.decompress(bad, name: "data.tar.gz"))
        }
        var trailing = good; trailing.insert(0xAA, at: trailing.count - 8)
        XCTAssertThrowsError(try DebExtractor.decompress(trailing, name: "data.tar.gz"))
    }

}
#endif
