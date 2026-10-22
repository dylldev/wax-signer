import XCTest
import zlib
@testable import IPAKit

/// Large changed files are deflated as independent blocks on several cores and stitched into one valid raw-deflate stream.
final class ParallelDeflateTests: XCTestCase {
    private var root: URL!
    private var saved = IPAArchiver.parallelDeflateMinimum

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wax-pdeflate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        IPAArchiver.parallelDeflateMinimum = saved
        try? FileManager.default.removeItem(at: root)
    }

    /// Compressible but not trivial: repeating text with a counter, so every block differs a little.
    private func sample(bytes: Int) -> Data {
        var data = Data(capacity: bytes + 64)
        var i = 0
        while data.count < bytes { data.append(Data("line \(i) of a perfectly ordinary executable segment\n".utf8)); i += 1 }
        return data.prefix(bytes)
    }

    private func inflate(_ raw: Data, expected: Int) throws -> Data {
        var s = z_stream()
        XCTAssertEqual(inflateInit2_(&s, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)), Z_OK)
        defer { inflateEnd(&s) }
        var out = Data(count: expected + 1024)
        let status: Int32 = raw.withUnsafeBytes { inp in
            out.withUnsafeMutableBytes { dst in
                s.next_in = UnsafeMutablePointer(mutating: inp.bindMemory(to: UInt8.self).baseAddress!); s.avail_in = UInt32(raw.count)
                s.next_out = dst.bindMemory(to: UInt8.self).baseAddress!; s.avail_out = UInt32(dst.count)
                return zlib.inflate(&s, Z_FINISH)
            }
        }
        XCTAssertEqual(status, Z_STREAM_END, "the stitched stream must be one complete deflate stream")
        return out.prefix(Int(s.total_out))
    }

    func testLargeFileIsCompressedInBlocksThatInflateBackToTheOriginal() throws {
        IPAArchiver.parallelDeflateMinimum = 1024 * 1024
        let original = sample(bytes: 9 * 1024 * 1024 + 12_345)
        let file = root.appendingPathComponent("big.bin"); try original.write(to: file)
        let p = try IPAArchiver.precompress(file, in: root)
        let packed = try Data(contentsOf: p.temp)
        XCTAssertEqual(p.comp, packed.count)
        XCTAssertEqual(p.uncomp, original.count)
        XCTAssertLessThan(packed.count, original.count / 2, "block compression must still compress")
        XCTAssertEqual(try inflate(packed, expected: original.count), original)
        XCTAssertEqual(p.fingerprint, try FileFingerprint.file(file))
        XCTAssertEqual(p.crc, p.fingerprint.crc32)
    }

    func testSmallFilesStillUseTheSingleStreamPath() throws {
        IPAArchiver.parallelDeflateMinimum = 64 * 1024 * 1024
        let original = sample(bytes: 3 * 1024 * 1024)
        let file = root.appendingPathComponent("small.bin"); try original.write(to: file)
        let p = try IPAArchiver.precompress(file, in: root)
        XCTAssertEqual(try inflate(try Data(contentsOf: p.temp), expected: original.count), original)
    }

    func testBlockCompressedEntryExtractsFromARealArchive() throws {
        IPAArchiver.parallelDeflateMinimum = 1024 * 1024
        let tree = root.appendingPathComponent("tree"), app = tree.appendingPathComponent("Payload/Big.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let original = sample(bytes: 6 * 1024 * 1024 + 7)
        try original.write(to: app.appendingPathComponent("Big"))
        try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let ipa = root.appendingPathComponent("out.ipa")
        try IPAArchiver.archive(directory: tree, to: ipa)
        let session = try IPAArchiveSession(url: ipa), out = root.appendingPathComponent("extracted")
        _ = try session.extract(to: out)
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("Payload/Big.app/Big")), original)
    }

    func testFastLevelStillRoundTripsAndIsNotLargerThanStored() throws {
        IPAArchiver.parallelDeflateMinimum = 1024 * 1024
        let original = sample(bytes: 8 * 1024 * 1024 + 99)
        let file = root.appendingPathComponent("fast.bin"); try original.write(to: file)
        let p = try IPAArchiver.precompress(file, in: root, level: Z_BEST_SPEED)
        let packed = try Data(contentsOf: p.temp)
        XCTAssertLessThan(packed.count, original.count / 2)
        XCTAssertEqual(try inflate(packed, expected: original.count), original)
        XCTAssertEqual(p.fingerprint, try FileFingerprint.file(file))
    }

    func testFastDeflateArchiveExtractsToTheSameBytes() throws {
        IPAArchiver.parallelDeflateMinimum = 1024 * 1024
        let tree = root.appendingPathComponent("tree2"), app = tree.appendingPathComponent("Payload/Fast.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let original = sample(bytes: 5 * 1024 * 1024 + 3)
        try original.write(to: app.appendingPathComponent("Fast"))
        try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let ipa = root.appendingPathComponent("fast.ipa")
        try IPAArchiver.archive(directory: tree, to: ipa, fastDeflate: true)
        let session = try IPAArchiveSession(url: ipa), out = root.appendingPathComponent("extracted2")
        _ = try session.extract(to: out)
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("Payload/Fast.app/Fast")), original)
    }

    func testFastLevelAlsoAppliesToFilesBelowTheBlockThreshold() throws {
        IPAArchiver.parallelDeflateMinimum = 512 * 1024 * 1024      // far above this file: only the level can route it
        let original = sample(bytes: 3 * 1024 * 1024)
        let file = root.appendingPathComponent("mid.bin"); try original.write(to: file)
        let normal = try IPAArchiver.precompress(file, in: root)
        let fast = try IPAArchiver.precompress(file, in: root, level: Z_BEST_SPEED)
        XCTAssertEqual(try inflate(try Data(contentsOf: fast.temp), expected: original.count), original)
        XCTAssertNotEqual(fast.comp, normal.comp, "the fast level must reach files that are not big enough for block mode")
    }
}
