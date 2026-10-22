import Foundation
import XCTest
@testable import SigningKit

/// Small deterministic adversarial inputs; shared with scripts/test_parser_safety.py's limited Linux harness.
final class ParserSafetyTests: XCTestCase {
    private func reject<T>(_ operation: @autoclosure () throws -> T, contains text: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertTrue(error is SigningError, "expected a controlled parser error, got \(error)", file: file, line: line)
            XCTAssertTrue(text.isEmpty || error.localizedDescription.contains(text), "\(error)", file: file, line: line)
        }
    }

    private func be(_ n: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
              UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
    }
    private func setBE(_ d: inout Data, _ offset: Int, _ n: UInt32) { d.replaceSubrange(offset..<(offset + 4), with: be(n)) }

    /// A valid unsigned executable with bounded header padding and one file-backed section.
    private func image(signature: Bool = false) -> Data {
        var d = Data(count: signature ? 1088 : 1024)
        d.setU32(0, 0xfeedfacf); d.setU32(4, 0x0100000c); d.setU32(12, 2)
        d.setU32(16, signature ? 3 : 2); d.setU32(20, signature ? 240 : 224)
        d.setU32(32, 0x19); d.setU32(36, 152)
        d.replaceSubrange(40..<46, with: Data("__TEXT".utf8))
        d.setU64(56, 0x100000000); d.setU64(64, 768); d.setU64(80, 768); d.setU32(96, 1)
        d.setU64(136, 0x100000200); d.setU64(144, 16); d.setU32(152, 512)
        d.setU32(184, 0x19); d.setU32(188, 72)
        d.replaceSubrange(192..<202, with: Data("__LINKEDIT".utf8))
        d.setU64(208, 0x100000300); d.setU64(216, 4096)
        d.setU64(224, 768); d.setU64(232, UInt64(d.count - 768))
        if signature { d.setU32(256, 0x1d); d.setU32(260, 16); d.setU32(264, 1024); d.setU32(268, 64) }
        return d
    }

    private func fat(_ slices: [(UInt32, Data)]) -> Data {
        var d = be(0xcafebabe) + be(UInt32(slices.count))
        var offset = 4096
        for (sub, slice) in slices {
            d += be(0x0100000c) + be(sub) + be(UInt32(offset)) + be(UInt32(slice.count)) + be(12)
            offset += 4096
        }
        for (i, pair) in slices.enumerated() {
            d.append(Data(count: 4096 * (i + 1) - d.count)); d.append(pair.1)
        }
        return d
    }

    func testCheckedRangesRejectOverflowWithoutAdding() {
        XCTAssertFalse(CheckedBytes.contains(Int.max, Int.max, in: Int.max))
        XCTAssertFalse(CheckedBytes.contains(-1, 1, in: 32))
        XCTAssertFalse(CheckedBytes.contains(1, -1, in: 32))
        XCTAssertTrue(CheckedBytes.contains(32, 0, in: 32))
        XCTAssertFalse(CheckedBytes.contains(UInt64.max, 1, in: UInt64.max))
        XCTAssertTrue(CheckedBytes.contains(UInt64.max, 0, in: UInt64.max))
    }

    func testValidThinRewriteAndInjectionPreserveSectionBytes() throws {
        var original = image(); original.replaceSubrange(512..<528, with: Data(repeating: 0xA5, count: 16))
        var m = try MachO(original)
        try m.addLoadDylib("@executable_path/Frameworks/Hook.dylib")
        try m.prepareForSignature(size: 64); try m.attach(signature: Data(count: 64))
        let reparsed = try MachO(m.data)
        XCTAssertEqual(reparsed.loadDylibNames, ["@executable_path/Frameworks/Hook.dylib"])
        XCTAssertEqual(m.data[512..<528], original[512..<528])
        XCTAssertEqual(reparsed.existingSignature?.size, 64)
    }

    func testEveryTruncatedHeaderAndCommandRegionIsRejected() {
        let d = image()
        for cut in 0..<256 { reject(try MachO(Data(d.prefix(cut)))) }
    }

    func testCommandCountMustFitAndExactlyConsumeDeclaredRegion() {
        var d = image(); d.setU32(16, 29); reject(try MachO(d), contains: "declared region")
        d = image(); d.setU32(16, 1); reject(try MachO(d), contains: "count")
        d = image(); d.setU32(20, 152); reject(try MachO(d))
        d = image(); d.setU32(36, 151); reject(try MachO(d), contains: "command size")
        d = image(); d.setU32(16, .max); reject(try MachO(d))
    }

    func testSectionTableAndFileGeometryAreBoundedByTheirSegment() {
        var d = image(); d.setU32(96, 2); reject(try MachO(d), contains: "section table")
        d = image(); d.setU32(152, 128); reject(try MachO(d), contains: "section overlaps")
        d = image(); d.setU64(144, .max); reject(try MachO(d))
        d = image(); d.setU64(80, .max); reject(try MachO(d))
        d = image(); d.setU64(64, .max); reject(try MachO(d), contains: "overflows")
    }

    func testSectionlessImageCannotInventHeaderPadding() throws {
        var d = image(); d.setU32(96, 0) // unused section bytes do not establish writable padding
        var m = try MachO(d)
        reject(try m.prepareForSignature(size: 64), contains: "no room")
        XCTAssertEqual(m.data, d)
        reject(try m.addLoadDylib("x"), contains: "no room")
        XCTAssertEqual(m.data, d)
    }

    func testOriginalMinimalCrashWitnessesAreRejected() {
        for length in [104, 120] {
            var d = Data(count: length)
            d.setU32(0, 0xfeedfacf); d.setU32(4, 0x0100000c); d.setU32(12, 2)
            d.setU32(16, length == 104 ? 1 : 2); d.setU32(20, UInt32(length - 32))
            d.setU32(32, 0x19); d.setU32(36, 72)
            d.replaceSubrange(40..<50, with: Data("__LINKEDIT".utf8))
            if length == 120 { d.setU32(104, 0x1d); d.setU32(108, 16); d.setU32(116, 120) }
            reject(try MachO(d))
        }
    }

    func testNonzeroHeaderPaddingAndBadSizesCannotMutateImage() throws {
        var d = image(); d[256] = 1
        var m = try MachO(d); reject(try m.prepareForSignature(size: 64), contains: "no room")
        XCTAssertEqual(m.data, d)
        for size in [-1, Int.max, Int(UInt32.max) + 1] {
            m = try MachO(image(signature: true)); let before = m.data
            reject(try m.prepareForSignature(size: size), contains: "size")
            XCTAssertEqual(m.data, before)
        }
        var nearLimit = image(signature: true)
        nearLimit.setU64(208, UInt64.max - 4096)
        m = try MachO(nearLimit)
        reject(try m.prepareForSignature(size: 8192), contains: "VM range overflows")
        XCTAssertEqual(m.data, nearLimit, "a late rewrite-size rejection must not remove the old signature")
    }

    func testSignatureMustNotOverlapHeaderTextOrOtherLinkeditData() {
        for (offset, size): (UInt32, UInt32) in [(0, 64), (512, 16), (1024, 0), (1024, .max), (.max, 16)] {
            var d = image(signature: true); d.setU32(264, offset); d.setU32(268, size)
            reject(try MachO(d))
        }
        var d = image(signature: true)
        d.setU32(16, 4); d.setU32(20, 256)
        d.setU32(272, 0x26); d.setU32(276, 16); d.setU32(280, 1024); d.setU32(284, 16)
        reject(try MachO(d), contains: "overlap")
    }

    func testTrailingSignatureFailureLeavesDataIntact() throws {
        var d = image(signature: true); d.append(0); d.setU64(232, UInt64(d.count - 768))
        var m = try MachO(d)
        reject(try m.prepareForSignature(size: 64), contains: "not at the end")
        XCTAssertEqual(m.data, d)
    }

    func testAttachSizeMismatchIsControlledAndDoesNotMutate() throws {
        var m = try MachO(image()); try m.prepareForSignature(size: 64)
        let before = m.data
        reject(try m.attach(signature: Data(count: 63)))
        XCTAssertEqual(m.data, before)
    }

    func testCPUAndPlatformValidation() throws {
        for (field, value): (Int, UInt32) in [(4, 7), (8, 1), (12, 1)] {
            var d = image(); d.setU32(field, value); reject(try MachO(d))
        }
        for platform: UInt32 in [1, 2, 4, 7, .max] {
            var d = image(); d.setU32(16, 3); d.setU32(20, 248)
            d.setU32(256, 0x32); d.setU32(260, 24); d.setU32(264, platform)
            if [2, 4].contains(platform) { XCTAssertNoThrow(try MachO(d)) }
            else { reject(try MachO(d), contains: "platform") }
        }
        var e = image(); e.setU32(8, 2); XCTAssertNoThrow(try MachO(e))
    }

    func testCommandSpecificMinimumsAndStrings() {
        for (cmd, size, name): (UInt32, UInt32, UInt32) in [(0xC, 16, 12), (0xC, 24, 8),
                (0x8000001c, 16, .max), (0x2c, 16, 0), (0x32, 16, 0), (0x80000028, 8, 0), (0x31, 32, 0)] {
            var d = image(); d.setU32(16, 3); d.setU32(20, 224 + size)
            d.setU32(256, cmd); d.setU32(260, size); d.setU32(264, name)
            reject(try MachO(d))
        }
    }

    func testValidUniversalArchitecturePreferenceAndArm64e() throws {
        let a = image(); var e = a; e.setU32(8, 2)
        XCTAssertEqual(try FatMachO.thin(fat([(2, e), (0, a)])), a)
        XCTAssertEqual(try FatMachO.thin(fat([(2, e)])), e)
        XCTAssertEqual(try FatMachO.thin(a), a)
    }

    func testFatTableContainmentAlignmentOverlapAndMetadata() {
        let good = fat([(0, image())])
        for cut in 0..<28 { reject(try FatMachO.thin(Data(good.prefix(cut)))) }
        for (field, value): (Int, UInt32) in [(4, .max), (16, 8), (16, 4097), (20, 0), (20, .max), (24, 32), (24, .max), (12, 1), (12, 2)] {
            var d = good; setBE(&d, field, value); reject(try FatMachO.thin(d))
        }
        var e = image(); e.setU32(8, 2)
        var overlap = fat([(0, image()), (2, e)]); setBE(&overlap, 36, 4096)
        reject(try FatMachO.thin(overlap), contains: "overlapping")
        // Even a non-selected architecture must have valid containment.
        var nonselected = fat([(0, image()), (2, e)]); setBE(&nonselected, 28, 7); setBE(&nonselected, 40, .max)
        reject(try FatMachO.thin(nonselected))
    }

    func testMalformedLaterFatFileDoesNotRewriteAnySource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = fat([(0, image())]); var bad = good; setBE(&bad, 24, 32)
        let a = dir.appendingPathComponent("a"), z = dir.appendingPathComponent("z")
        try good.write(to: a); try bad.write(to: z)
        reject(try FatMachO.thinTree(at: dir))
        XCTAssertEqual(try Data(contentsOf: a), good); XCTAssertEqual(try Data(contentsOf: z), bad)
    }

    func testFixtureExecutablesAndFrameworkSupportSafeRewrites() throws {
        for relative in ["SigningTestApp", "PlugIns/TestExt.appex/TestExt", "Frameworks/TestKit.framework/TestKit"] {
            let bytes = try Data(contentsOf: Fixtures.appDirectory.appendingPathComponent(relative))
            var m = try MachO(bytes)
            let signatureOffset = m.existingSignature?.offset ?? bytes.count
            let signedBody = Data(bytes[16384..<signatureOffset])
            try m.addLoadDylib("@executable_path/Frameworks/Hook.dylib")
            try m.prepareForSignature(size: 128); try m.attach(signature: Data(count: 128))
            XCTAssertEqual(Data(m.data[16384..<signatureOffset]), signedBody)
            XCTAssertEqual(try MachO(m.data).existingSignature?.size, 128)
        }
    }

    private func directory() -> Data {
        var d = Data(count: 121)
        setBE(&d, 0, 0xfade0c02); setBE(&d, 4, UInt32(d.count)); setBE(&d, 8, 0x20400)
        setBE(&d, 16, 89); setBE(&d, 20, 88); setBE(&d, 28, 1); setBE(&d, 32, 1024); setBE(&d, 60, 1024)
        d[36] = 32; d[37] = 2; d[39] = 12
        return d
    }

    func testValidCodeDirectoryAndInvalidHashTables() throws {
        XCTAssertEqual(try SignatureLayout.CodeDirectory(directory()).codeCount, 1)
        var withSpecials = directory()
        withSpecials.insert(contentsOf: Data(count: 7 * 32), at: 89)
        setBE(&withSpecials, 4, UInt32(withSpecials.count)); setBE(&withSpecials, 16, 89 + 7 * 32)
        setBE(&withSpecials, 24, 7)
        XCTAssertEqual(try SignatureLayout.CodeDirectory(withSpecials).specialCount, 7)
        for (field, value): (Int, UInt32) in [(16, .max), (16, 0), (24, .max), (24, 7), (28, .max),
                (28, 0), (32, .max), (4, 88), (20, 89), (48, .max), (44, 1), (8, 0x20600)] {
            var d = directory(); setBE(&d, field, value); reject(try SignatureLayout.CodeDirectory(d))
        }
        for cut in 0..<121 { reject(try SignatureLayout.CodeDirectory(Data(directory().prefix(cut)))) }
        var d = directory(); d[39] = 255; reject(try SignatureLayout.CodeDirectory(d))
        d = directory(); d[36] = 255; reject(try SignatureLayout.CodeDirectory(d))
    }

    private func container() -> Data {
        let cd = directory()
        return be(0xfade0cc0) + be(UInt32(20 + cd.count)) + be(1) + be(0) + be(20) + cd
    }

    func testEmbeddedSignatureDeclaredBoundaryIndicesAndBlobs() throws {
        XCTAssertEqual(try SignatureLayout.slots(container())[0], directory())
        XCTAssertNoThrow(try SignatureLayout.slots(container() + Data(count: 8)))
        for (field, value): (Int, UInt32) in [(4, 0), (4, 12), (4, .max), (8, .max),
                (16, 12), (16, .max), (24, 0), (24, .max)] {
            var d = container(); setBE(&d, field, value); reject(try SignatureLayout.slots(d))
        }
        for cut in 0..<container().count { reject(try SignatureLayout.slots(Data(container().prefix(cut)))) }
        reject(try SignatureLayout.slots(container() + Data([1])))
        // Two indices aliasing one body, then two different slot numbers aliasing the same body.
        let cd = directory()
        var d = be(0xfade0cc0) + be(UInt32(28 + cd.count)) + be(2) + be(0) + be(28) + be(0) + be(28) + cd
        reject(try SignatureLayout.slots(d), contains: "duplicate")
        setBE(&d, 20, 2); reject(try SignatureLayout.slots(d), contains: "overlapping")
    }

    func testCMSOuterLengthIsExactAndBounded() {
        XCTAssertNoThrow(try SignatureLayout.validateCMS(Data([0x30, 0])))
        for data in [Data(), Data([0x30]), Data([0x31, 0]), Data([0x30, 1]), Data([0x30, 0, 0]),
                     Data([0x30, 0x80]), Data([0x30, 0x84, 255, 255, 255, 255]),
                     Data([0x30, 0x81, 0]), Data([0x30, 0x82, 0, 128])] {
            reject(try SignatureLayout.validateCMS(data), contains: "CMS")
        }
    }

    #if os(macOS) || os(Linux)
    func testSystemArTarAndGzipWrappersAreAccepted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data([1, 2, 3])
        try bytes.write(to: dir.appendingPathComponent("x.dylib"))
        func run(_ tool: String, _ args: [String]) throws {
            guard FileManager.default.isExecutableFile(atPath: tool) else { throw XCTSkip("missing \(tool)") }
            let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
            p.currentDirectoryURL = dir; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit(); XCTAssertEqual(p.terminationStatus, 0)
        }
        try run("/usr/bin/tar", ["-cf", "data.tar", "x.dylib"])
        let tar = try Data(contentsOf: dir.appendingPathComponent("data.tar"))
        XCTAssertEqual(try DebArchive.tarFiles(tar).first?.bytes, bytes)
        // This is a data archive, not a static library. On macOS plain -q runs the symbol-table tool,
        // which produced only __.SYMDEF SORTED and discarded this non-object TAR in CI. -S preserves data.
        try run("/usr/bin/ar", ["-qS", "tweak.deb", "data.tar"])
        let archive = try Data(contentsOf: dir.appendingPathComponent("tweak.deb"))
        let members = try DebArchive.arMembers(archive)
        XCTAssertEqual(members.map(\.name), ["data.tar"])
        XCTAssertEqual(members.first?.bytes, tar,
                       "ar archive bytes=\(archive.count), prefix=\(archive.prefix(256).map { String(format: "%02x", $0) }.joined()), members=\(members.map(\.name))")
        #if os(macOS)
        // Spaces and >16 bytes force the real BSD #1/N extended-name encoding, including NUL padding.
        let longName = "data archive with BSD extended name.tar"
        try tar.write(to: dir.appendingPathComponent(longName))
        try run("/usr/bin/ar", ["-qS", "long.deb", longName])
        let extended = try DebArchive.arMembers(Data(contentsOf: dir.appendingPathComponent("long.deb")))
        XCTAssertEqual(extended.map(\.name), [longName])
        XCTAssertEqual(extended.first?.bytes, tar)
        #endif
        try run("/usr/bin/gzip", ["-k", "x.dylib"])
        try DebGzip.parse(Data(contentsOf: dir.appendingPathComponent("x.dylib.gz"))).validate(bytes)
    }
    #endif

    private func ar(name: String = "data.tar/", size: String? = nil, body: Data = Data()) -> Data {
        func field(_ s: String, _ n: Int) -> Data { Data(s.padding(toLength: n, withPad: " ", startingAt: 0).utf8) }
        var d = Data("!<arch>\n".utf8) + field(name, 16) + field("0", 12) + field("0", 6)
        d += field("0", 6) + field("100644", 8) + field(size ?? "\(body.count)", 10) + Data("`\n".utf8) + body
        if body.count % 2 != 0 { d.append(10) }
        return d
    }

    func testArNegativeBSDLengthsAndMalformedMembersAreRejected() throws {
        for name in ["#1/-1", "#1/1", "#1/+0", "#1/no", "#1/0"] { reject(try DebArchive.arMembers(ar(name: name))) }
        for size in ["-1", "+1", "9999999999", "bad", ""] { reject(try DebArchive.arMembers(ar(size: size))) }
        let good = ar(body: Data([42]))
        XCTAssertEqual(try DebArchive.arMembers(good).first?.bytes, Data([42]))
        for cut in 9..<good.count { reject(try DebArchive.arMembers(Data(good.prefix(cut)))) }
        reject(try DebArchive.arMembers(good + Data([1])))
        var bad = good; bad[bad.count - 1] = 0; reject(try DebArchive.arMembers(bad))
        for n in [8, 12, 20] {
            let bsd = ar(name: "#1/\(n)", body: Data("data.tar".utf8) + Data(count: n - 8) + Data([42]))
            let member = try DebArchive.arMembers(bsd).first
            XCTAssertEqual(member?.name, "data.tar"); XCTAssertEqual(member?.bytes, Data([42]))
        }
        let symbol = ar(name: "#1/20", body: Data("__.SYMDEF SORTED".utf8) + Data(count: 12))
        let withSymbol = symbol + ar(body: Data([42])).dropFirst(8)
        XCTAssertEqual(try DebArchive.arMembers(withSymbol).map(\.name), ["data.tar"])
        XCTAssertEqual(try DebArchive.arMembers(withSymbol).first?.bytes, Data([42]))
    }

    private func tar(size: String = "00000000001", body: Data = Data([42])) -> Data {
        var h = Data(count: 512)
        h.replaceSubrange(0..<7, with: Data("x.dylib".utf8))
        h.replaceSubrange(124..<135, with: Data(size.utf8)); h[156] = 48
        h.replaceSubrange(148..<156, with: Data(repeating: 32, count: 8))
        let sum = h.reduce(0) { $0 + Int($1) }
        h.replaceSubrange(148..<155, with: Data(String(format: "%06o", sum).utf8) + Data([0]))
        return h + body + Data(count: (512 - body.count % 512) % 512) + Data(count: 1024)
    }

    func testTarChecksumNumbersPaddingAndTermination() throws {
        let good = tar()
        XCTAssertEqual(try DebArchive.tarFiles(good).first?.bytes, Data([42]))
        var bad = good; bad[0] ^= 1; reject(try DebArchive.tarFiles(bad))
        for size in ["77777777777", "-0000000001", "+0000000001", "88888888888"] { reject(try DebArchive.tarFiles(tar(size: size))) }
        for cut in [0, 511, 512, 513, 1023, 1024, 1536, 2047] { reject(try DebArchive.tarFiles(Data(good.prefix(cut)))) }
        reject(try DebArchive.tarFiles(good + Data([1])))
    }

    func testRawDeflateRequiresExactCompleteStream() throws {
        let payload = Data([203,72,205,201,201,7,0]) // fixed-Huffman DEFLATE of "hello"
        XCTAssertEqual(try DebDeflate.decode(payload), Data("hello".utf8))
        XCTAssertEqual(try DebDeflate.decode(Data([3, 0])), Data()) // legitimate empty stream
        for suffix in [Data([0]), Data([0xAA]), Data([0xFF]), Data([3, 0]), payload] {
            reject(try DebDeflate.decode(payload + suffix))
        }
        for cut in 0..<payload.count { reject(try DebDeflate.decode(Data(payload.prefix(cut)))) }
        // Uncompressed final block: byte boundary, LEN, one's-complement NLEN, payload.
        let stored = Data([1, 5, 0, 250, 255]) + Data("hello".utf8)
        XCTAssertEqual(try DebDeflate.decode(stored), Data("hello".utf8))
        reject(try DebDeflate.decode(stored + Data([0])))
        var invalid = stored; invalid[3] ^= 1; reject(try DebDeflate.decode(invalid))
    }

    func testGzipWrapperOptionalFieldsCRCAndLength() throws {
        // gzip of "hello", deterministic header/trailer; DEFLATE backend is separately exercised on Apple.
        let gzip = Data([31,139,8,0,0,0,0,0,0,3,203,72,205,201,201,7,0,134,166,16,54,5,0,0,0])
        try DebGzip.parse(gzip).validate(Data("hello".utf8))
        reject(try DebGzip.parse(gzip).validate(Data("hellx".utf8)))
        reject(try DebGzip.parse(gzip).validate(Data()))
        for cut in 0...18 { reject(try DebGzip.parse(Data(gzip.prefix(cut)))) }
        for flag: UInt8 in [4, 8, 16, 2, 0xE0] {
            var d = gzip; d[3] = flag
            if flag == 4 { d[10] = 255; d[11] = 255 }
            if flag == 8 || flag == 16 { d.replaceSubrange(10..<17, with: Data(repeating: 65, count: 7)) }
            reject(try DebGzip.parse(d))
        }
    }
}
