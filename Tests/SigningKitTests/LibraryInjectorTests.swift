import CredentialKit
import XCTest
@testable import SigningKit

final class LibraryInjectorTests: XCTestCase {
    private func exeURL(_ app: URL) throws -> URL {
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
        return app.appendingPathComponent(info["CFBundleExecutable"] as! String)
    }

    /// A real arm64 dylib: the fixture app's own framework binary, copied under a new name.
    private func makeLibrary(named name: String, in app: URL) throws -> URL {
        let src = app.appendingPathComponent("Frameworks/TestKit.framework/TestKit")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    func testInjectCopiesTheLibraryAndAddsALoadCommand() throws {
        let app = try makeWorkingApp()
        let lib = try makeLibrary(named: "Hook.dylib", in: app)
        let notes = try LibraryInjector.inject([lib], into: app)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/Hook.dylib").path))
        let macho = try MachO(Data(contentsOf: try exeURL(app)))
        XCTAssertTrue(macho.loadDylibNames.contains { $0.hasSuffix("Hook.dylib") }, "\(macho.loadDylibNames)")
        XCTAssertTrue(notes.contains { $0.contains("Hook.dylib") }, "\(notes)")
    }

    func testInjectingTheSameLibraryTwiceDoesNotDuplicateTheLoadCommand() throws {
        let app = try makeWorkingApp()
        let lib = try makeLibrary(named: "Hook.dylib", in: app)
        _ = try LibraryInjector.inject([lib], into: app)
        _ = try LibraryInjector.inject([lib], into: app)
        let macho = try MachO(Data(contentsOf: try exeURL(app)))
        XCTAssertEqual(macho.loadDylibNames.filter { $0.hasSuffix("Hook.dylib") }.count, 1)
    }

    func testRefusesWhenTheHeaderHasNoRoomAndLeavesTheBinaryUntouched() throws {
        let app = try makeWorkingApp()
        var failure: Error?
        var lastGood = try Data(contentsOf: try exeURL(app))
        for i in 0..<400 {
            let lib = try makeLibrary(named: "Pad\(String(repeating: "x", count: 40))\(i).dylib", in: app)
            do { _ = try LibraryInjector.inject([lib], into: app); lastGood = try Data(contentsOf: try exeURL(app)) }
            catch { failure = error; break }
        }
        let error = try XCTUnwrap(failure, "header never filled up")
        XCTAssertTrue(error.localizedDescription.lowercased().contains("room"), error.localizedDescription)
        XCTAssertEqual(try Data(contentsOf: try exeURL(app)), lastGood, "a failed injection changes nothing")
    }

    func testRefusesAnEncryptedMainBinary() throws {
        let app = try makeWorkingApp()
        let exe = try exeURL(app)
        var d = try Data(contentsOf: exe)
        let ncmds = Int(d.u32(16)), size = Int(d.u32(20))
        // Append a FairPlay LC_ENCRYPTION_INFO_64 with cryptid 1 into the header padding.
        var cmd = Data(count: 24)
        cmd.setU32(0, 0x2C); cmd.setU32(4, 24); cmd.setU32(16, 1)
        d.replaceSubrange((32 + size)..<(32 + size + 24), with: cmd)
        d.setU32(16, UInt32(ncmds + 1)); d.setU32(20, UInt32(size + 24))
        try d.write(to: exe)
        let lib = try makeLibrary(named: "Hook.dylib", in: app)
        XCTAssertThrowsError(try LibraryInjector.inject([lib], into: app)) {
            XCTAssertTrue($0.localizedDescription.lowercased().contains("encrypt"), $0.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/Hook.dylib").path))
    }

    func testAFileThatIsNotALibraryIsRefused() throws {
        let app = try makeWorkingApp()
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).dylib")
        try Data("hello".utf8).write(to: junk)
        XCTAssertThrowsError(try LibraryInjector.inject([junk], into: app))
    }

    func testMalformedImportedLibraryDoesNotMutateTheHost() throws {
        let app = try makeWorkingApp()
        let executable = try exeURL(app)
        let before = try Data(contentsOf: executable)
        let lib = try makeLibrary(named: "Bad.dylib", in: app)
        var bad = try Data(contentsOf: lib); bad.setU32(16, .max); try bad.write(to: lib)
        XCTAssertThrowsError(try LibraryInjector.inject([lib], into: app)) {
            XCTAssertTrue($0 is SigningError)
        }
        XCTAssertEqual(try Data(contentsOf: executable), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/Bad.dylib").path))
    }

    func testFrameworkInjectionUsesItsExecutableName() throws {
        let app = try makeWorkingApp()
        let src = app.appendingPathComponent("Frameworks/TestKit.framework")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)/Hooked.framework")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: copy)
        _ = try LibraryInjector.inject([copy], into: app)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks/Hooked.framework/TestKit").path))
        let macho = try MachO(Data(contentsOf: try exeURL(app)))
        XCTAssertTrue(macho.loadDylibNames.contains { $0.hasSuffix("Hooked.framework/TestKit") }, "\(macho.loadDylibNames)")
    }

    func testInjectedLibraryIsSignedAndVerifiedByTheSigner() throws {
        let app = try makeWorkingApp()
        let lib = try makeLibrary(named: "Hook.dylib", in: app)
        _ = try LibraryInjector.inject([lib], into: app)
        let creds = try TestCredentials()
        let r = try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                      profile: try ProvisioningProfile.parse(FixtureData.profileWildcardAll))
        XCTAssertTrue(r.items.contains { $0.relativePath.hasSuffix("Hook.dylib") }, "\(r.items.map(\.relativePath))")
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).passed)
    }

    func testInjectionThroughAppEditsRunsBeforeSigning() throws {
        let app = try makeWorkingApp()
        let lib = try makeLibrary(named: "Hook.dylib", in: app)
        var e = AppEdits(); e.injectLibraries = [lib]
        let notes = try AppEditor.apply(e, to: app)
        XCTAssertTrue(notes.contains { $0.contains("Hook.dylib") })
        XCTAssertFalse(e.isEmpty)
    }
}

private extension Data {
    func u32(_ o: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[o + $1]) << UInt32(8 * $1) } }
    mutating func setU32(_ o: Int, _ v: UInt32) { for i in 0..<4 { self[o + i] = UInt8((v >> UInt32(8 * i)) & 0xFF) } }
}

/// Hostile load commands must be refused or ignored, never trap (found by the whole-branch review).
final class MachOHostileCommandTests: XCTestCase {
    /// A minimal image: a __LINKEDIT segment, then one hostile command that ends exactly at the end of the file.
    private func image(command: UInt32, size: UInt32, nameOffset: UInt32? = nil) -> Data {
        var d = Data(count: 32)
        d.setU32(0, 0xFEED_FACF); d.setU32(4, 0x0100000C); d.setU32(12, 2); d.setU32(16, 2); d.setU32(20, 72 + size)
        var seg = Data(count: 72)
        seg.setU32(0, 0x19); seg.setU32(4, 72)
        seg.replaceSubrange(8..<18, with: Array("__LINKEDIT".utf8))
        var c = Data(count: Int(size))
        c.setU32(0, command); c.setU32(4, size)
        if let nameOffset, size >= 12 { c.setU32(8, nameOffset) }
        return d + seg + c
    }

    func testAnEightByteRpathCommandIsRefusedNotRead() {
        XCTAssertThrowsError(try MachO(image(command: 0x8000_001C, size: 8)))
    }

    func testAnEightByteDylibCommandIsRefusedNotRead() {
        XCTAssertThrowsError(try MachO(image(command: 0xC, size: 8)))
    }

    func testAnRpathWhosePathOffsetIsOutsideTheCommandDoesNotTrap() throws {
        XCTAssertThrowsError(try MachO(image(command: 0x8000_001C, size: 16, nameOffset: 0xFFFF))) {
            XCTAssertTrue($0.localizedDescription.contains("string offset"), "\($0)")
        }
    }
}
