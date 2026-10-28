import XCTest
@testable import SigningKit

/// Hostile and damaged Mach-O input must produce an error, never a crash and never a half-written file.
final class MachOMalformedTests: XCTestCase {
    private func sampleBinary() throws -> Data {
        try Data(contentsOf: Fixtures.appDirectory.appendingPathComponent("SigningTestApp"))
    }

    /// Builds a minimal thin arm64 executable: header, __TEXT with one section, __LINKEDIT, optional signature.
    private func synthetic(headerPad: Int = 64, signatureAtEnd: Bool = true, withSignature: Bool = false,
                           extraTail: Int = 0) -> Data {
        func u32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> UInt32(8 * $0)) & 0xff) }) }
        func u64(_ v: UInt64) -> Data { Data((0..<8).map { UInt8((v >> UInt64(8 * $0)) & 0xff) }) }
        func cat(_ parts: [Data]) -> Data { parts.reduce(Data(), +) }      // arrays type-check quickly; long `+` chains do not on older compilers
        func name(_ s: String) -> Data { Data(s.utf8) + Data(count: 16 - s.utf8.count) }

        let textCmdSize = 72 + 80
        let linkCmdSize = 72
        let sigCmdSize = withSignature ? 16 : 0
        let cmdsSize = textCmdSize + linkCmdSize + sigCmdSize
        let sectionOffset = 32 + cmdsSize + headerPad          // first section data, i.e. end of header padding
        let textSize = 0x4000
        let linkeditOffset = textSize
        let sigSize = withSignature ? 64 : 0
        let linkeditSize = 16 + sigSize + extraTail

        var d = Data()
        d += cat([u32(0xFEED_FACF), u32(0x0100_000C), u32(0), u32(2)])  // magic, cputype arm64, subtype, MH_EXECUTE
        let extraCommands: Int = withSignature ? 1 : 0
        d += cat([u32(UInt32(2 + extraCommands)), u32(UInt32(cmdsSize)), u32(0), u32(0)])
        // __TEXT
        d += cat([u32(0x19), u32(UInt32(textCmdSize)), name("__TEXT"), u64(0x1_0000_0000), u64(0x4000)])
        d += cat([u64(0), u64(UInt64(textSize)), u32(5), u32(5), u32(1), u32(0)])
        d += cat([name("__text"), name("__TEXT"), u64(0x1_0000_0000 + UInt64(sectionOffset)), u64(16)])
        d += cat([u32(UInt32(sectionOffset)), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0)])
        // __LINKEDIT
        d += cat([u32(0x19), u32(UInt32(linkCmdSize)), name("__LINKEDIT"), u64(0x1_0000_4000), u64(0x4000)])
        d += cat([u64(UInt64(linkeditOffset)), u64(UInt64(linkeditSize)), u32(1), u32(1), u32(0), u32(0)])
        if withSignature {
            d += cat([u32(0x1d), u32(16), u32(UInt32(linkeditOffset + 16)), u32(UInt32(sigSize))])
        }
        d += Data(count: textSize - d.count)
        let pad = Data(repeating: 0xAA, count: 16 + (signatureAtEnd ? 0 : sigSize))
        let sig: Data = withSignature ? Data(repeating: 0xBB, count: sigSize) : Data()
        d += cat([pad, sig, Data(count: extraTail)])
        return d
    }

    func testSyntheticBinaryParses() throws {
        let m = try MachO(synthetic())
        XCTAssertEqual(m.textFileSize, 0x4000)
        XCTAssertNil(m.existingSignature)
    }

    func testAddsSignatureCommandWhenThereIsRoom() throws {
        var m = try MachO(synthetic(headerPad: 64))
        try m.prepareForSignature(size: 100)
        XCTAssertEqual(m.existingSignature?.size, 100)
        XCTAssertEqual(m.signedLength % 16, 0)
    }

    func testRefusesWhenHeaderHasNoRoomForTheCommand() throws {
        var m = try MachO(synthetic(headerPad: 8))
        XCTAssertThrowsError(try m.prepareForSignature(size: 100)) {
            XCTAssertTrue(($0 as? SigningError)?.errorDescription?.contains("no room in the Mach-O header") == true, "\($0)")
        }
    }

    func testReplacesExistingTrailingSignature() throws {
        var m = try MachO(synthetic(withSignature: true))
        XCTAssertNotNil(m.existingSignature)
        try m.prepareForSignature(size: 200)
        XCTAssertEqual(m.existingSignature?.size, 200)
    }

    func testRefusesSignatureThatIsNotLast() throws {
        var m = try MachO(synthetic(withSignature: true, extraTail: 64))
        XCTAssertThrowsError(try m.prepareForSignature(size: 100)) {
            XCTAssertTrue(($0 as? SigningError)?.errorDescription?.contains("not at the end") == true, "\($0)")
        }
    }

    func testRejectsTruncationAtEveryHeaderLength() throws {
        let data = try sampleBinary()
        for cut in stride(from: 0, to: 4096, by: 7) {
            let truncated = data.prefix(cut)
            // may parse (if only padding was cut) or throw; it must not trap
            if var m = try? MachO(Data(truncated)) { _ = try? m.prepareForSignature(size: 64) }
        }
    }

    func testSurvivesRandomHeaderCorruption() throws {
        let original = try sampleBinary()
        var rng = SplitMix(seed: 0x5EED)
        var parsed = 0, rejected = 0
        for _ in 0..<3000 {
            var d = original
            for _ in 0..<(1 + Int(rng.next() % 6)) {
                d[Int(rng.next() % 6000)] = UInt8(truncatingIfNeeded: rng.next())
            }
            if var m = try? MachO(d) {
                parsed += 1
                _ = try? m.prepareForSignature(size: Int(rng.next() % 5000))
            } else { rejected += 1 }
        }
        XCTAssertGreaterThan(parsed, 0)
        XCTAssertGreaterThan(rejected, 0, "corruption of load commands must be caught")
    }

    func testHugeCommandCountsAreRejected() throws {
        var d = try sampleBinary()
        d.setU32(16, 0xFFFF_FFFF)       // ncmds
        XCTAssertThrowsError(try MachO(d))
        d = try sampleBinary()
        d.setU32(20, 0xFFFF_FFF0)       // sizeofcmds
        XCTAssertThrowsError(try MachO(d))
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
