import CredentialKit
import XCTest
@testable import SigningKit

final class FatMachOTests: XCTestCase {
    private func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }

    /// A fat file (big-endian header) holding the given (cpusubtype, slice) pairs, 16 KiB aligned like Apple's lipo.
    private func fat(_ slices: [(subtype: UInt32, data: Data)]) -> Data {
        let align = 16384
        var header = be32(0xCAFEBABE) + be32(UInt32(slices.count))
        var body = Data()
        var offset = align
        for s in slices {
            header += be32(0x0100000C) + be32(s.subtype) + be32(UInt32(offset)) + be32(UInt32(s.data.count)) + be32(14)
            body.append(Data(repeating: 0, count: offset - align - body.count))
            body.append(s.data)
            offset = align + ((body.count + align - 1) / align) * align
        }
        var out = Data(header)
        out.append(Data(repeating: 0, count: align - out.count))
        out.append(body)
        return out
    }

    func testAUniversalBinaryInAnUnsupportedFormatIsRefusedNotTreatedAsAPlainFile() throws {
        for magic: [UInt8] in [[0xCA, 0xFE, 0xBA, 0xBF], [0xBF, 0xBA, 0xFE, 0xCA], [0xBE, 0xBA, 0xFE, 0xCA]] {
            let data = Data(magic + [UInt8](repeating: 0, count: 60))
            XCTAssertThrowsError(try FatMachO.thin(data)) { XCTAssertTrue("\($0)".lowercased().contains("universal"), "\($0)") }

            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fat64-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try data.write(to: dir.appendingPathComponent("code"))
            XCTAssertThrowsError(try FatMachO.thinTree(at: dir), "a binary the scan cannot read must stop signing, not be sealed unsigned")
        }
    }

    /// A refused binary found late in the scan must not leave earlier universal binaries already rewritten.
    func testAnUnsupportedBinaryFoundAfterAGoodOneLeavesTheTreeUntouched() throws {
        let slice = Data((0..<64).map { UInt8($0) })
        let good = fat([(0, slice)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fatscan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try good.write(to: dir.appendingPathComponent("a-good"))
        try Data([0xCA, 0xFE, 0xBA, 0xBF] + [UInt8](repeating: 0, count: 60)).write(to: dir.appendingPathComponent("z-unsupported"))
        XCTAssertThrowsError(try FatMachO.thinTree(at: dir))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("a-good")), good, "nothing is rewritten when the scan is going to refuse")
    }

    private func thinBinary() throws -> Data {
        let app = try makeWorkingApp()
        let exe = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil)
            as? [String: Any])["CFBundleExecutable"] as? String
        return try Data(contentsOf: app.appendingPathComponent(try XCTUnwrap(exe)))
    }

    func testThinPicksArm64OverArm64e() throws {
        let d = try thinBinary()
        let out = try FatMachO.thin(fat([(2, d + Data([0xEE])), (0, d)]))
        XCTAssertEqual(out, d)
    }

    func testThinReturnsArm64eWhenItIsTheOnlyChoice() throws {
        let d = try thinBinary()
        XCTAssertEqual(try FatMachO.thin(fat([(2, d)])), d)
    }

    func testThinInputIsReturnedUnchanged() throws {
        let d = try thinBinary()
        XCTAssertEqual(try FatMachO.thin(d), d)
    }

    func testFatFileWithoutAnArm64SliceIsRefusedClearly() throws {
        var h = fat([(0, try thinBinary())])
        h.replaceSubrange(8..<12, with: be32(0x00000007))   // cputype x86
        XCTAssertThrowsError(try FatMachO.thin(h)) { XCTAssertTrue($0.localizedDescription.contains("arm64"), $0.localizedDescription) }
    }

    func testSliceRangeOutsideTheFileIsRefusedNotTrapped() throws {
        var h = fat([(0, try thinBinary())])
        h.replaceSubrange(20..<24, with: be32(0x7FFFFFF0))  // absurd size
        XCTAssertThrowsError(try FatMachO.thin(h))
    }

    func testFatFrameworkInAnAppSignsAndVerifies() throws {
        let app = try makeWorkingApp()
        let fw = app.appendingPathComponent("Frameworks/TestKit.framework/TestKit")
        let d = try Data(contentsOf: fw)
        try fat([(2, d + Data([0xEE])), (0, d)]).write(to: fw)
        let creds = try TestCredentials()
        let r = try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                      profile: try ProvisioningProfile.parse(FixtureData.profileWildcardAll))
        XCTAssertTrue(r.warnings.contains { $0.contains("unused architectures") && $0.contains("TestKit") }, "\(r.warnings)")
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).passed)
    }

    func testProfileRefusalLeavesUniversalBinariesUnchanged() throws {
        let app = try makeWorkingApp()
        let exe = app.appendingPathComponent("SigningTestApp")
        let original = try Data(contentsOf: exe)
        let universal = fat([(2, original + Data([0xEE])), (0, original)])
        try universal.write(to: exe)
        let creds = try TestCredentials()

        XCTAssertThrowsError(try BundleSigner.sign(appDirectory: app, identity: creds.signer,
                                                   certificateTeamID: creds.loaded.teamID, profiles: ProfileSet()))
        XCTAssertEqual(try Data(contentsOf: exe), universal)
    }
}
