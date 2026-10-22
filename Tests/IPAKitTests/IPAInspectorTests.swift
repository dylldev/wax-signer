import XCTest
@testable import IPAKit

final class IPAInspectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ipakit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let goodPlist: [String: Any] = [
        "CFBundleIdentifier": "com.example.demo",
        "CFBundleDisplayName": "Demo",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "45",
        "MinimumOSVersion": "15.0",
        "CFBundleExecutable": "DemoBin",
    ]

    private func makeIPA(_ build: (inout ZipFixture) throws -> Void) throws -> URL {
        var z = ZipFixture()
        try build(&z)
        let url = dir.appendingPathComponent("t.ipa")
        try z.write(to: url)
        return url
    }

    private func goodIPA(deflate: Bool = false, extra: (inout ZipFixture) -> Void = { _ in }) throws -> URL {
        try makeIPA { z in
            z.add("Payload/")
            z.add("Payload/Demo.app/")
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist), deflate: deflate)
            z.add("Payload/Demo.app/DemoBin", Data(repeating: 0xCF, count: 64), deflate: deflate)
            extra(&z)
        }
    }

    private func assertError(_ url: URL, _ expected: IPAError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try IPAInspector.inspect(url: url), file: file, line: line) { error in
            XCTAssertEqual(error as? IPAError, expected, file: file, line: line)
        }
    }

    func testReadsMetadataFromStoredEntries() throws {
        let m = try IPAInspector.inspect(url: try goodIPA())
        XCTAssertEqual(m.bundleIdentifier, "com.example.demo")
        XCTAssertEqual(m.displayName, "Demo")
        XCTAssertEqual(m.version, "1.2.3")
        XCTAssertEqual(m.build, "45")
        XCTAssertEqual(m.minimumOSVersion, "15.0")
        XCTAssertEqual(m.executable, "DemoBin")
        XCTAssertEqual(m.appFolder, "Demo.app")
        XCTAssertEqual(m.entryCount, 4)
        XCTAssertFalse(m.hasCodeSignature)
        XCTAssertFalse(m.hasEmbeddedProfile)
    }

    func testReadsMetadataFromDeflatedEntries() throws {
        let m = try IPAInspector.inspect(url: try goodIPA(deflate: true))
        XCTAssertEqual(m.bundleIdentifier, "com.example.demo")
        XCTAssertEqual(m.version, "1.2.3")
    }

    func testDetectsSignatureAndProfileFiles() throws {
        let url = try goodIPA { z in
            z.add("Payload/Demo.app/_CodeSignature/CodeResources", Data([1]))
            z.add("Payload/Demo.app/embedded.mobileprovision", Data([2]))
        }
        let m = try IPAInspector.inspect(url: url)
        XCTAssertTrue(m.hasCodeSignature)
        XCTAssertTrue(m.hasEmbeddedProfile)
    }

    func testNameFallsBackToBundleNameThenFolder() throws {
        var p = goodPlist
        p["CFBundleDisplayName"] = nil
        p["CFBundleName"] = "ShortName"
        var url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(p))
            z.add("Payload/Demo.app/DemoBin")
        }
        XCTAssertEqual(try IPAInspector.inspect(url: url).displayName, "ShortName")
        p["CFBundleName"] = nil
        url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(p))
            z.add("Payload/Demo.app/DemoBin")
        }
        XCTAssertEqual(try IPAInspector.inspect(url: url).displayName, "Demo")
    }

    func testRejectsNonZip() throws {
        let url = dir.appendingPathComponent("junk.ipa")
        try Data("not a zip at all".utf8).write(to: url)
        assertError(url, .notAZip)
    }

    func testRejectsTruncatedZip() throws {
        let good = try goodIPA()
        let data = try Data(contentsOf: good)
        let url = dir.appendingPathComponent("cut.ipa")
        try data.prefix(data.count / 2).write(to: url)
        assertError(url, .notAZip)
    }

    func testRejectsMissingPayload() throws {
        let url = try makeIPA { $0.add("Other/readme.txt", Data([1])) }
        assertError(url, .noApp)
    }

    func testRejectsMultipleApps() throws {
        let url = try goodIPA { $0.add("Payload/Second.app/Info.plist", Data()) }
        assertError(url, .multipleApps)
    }

    func testRejectsMissingInfoPlist() throws {
        let url = try makeIPA { $0.add("Payload/Demo.app/DemoBin", Data([1])) }
        assertError(url, .missingInfoPlist)
    }

    func testRejectsInvalidInfoPlist() throws {
        let url = try makeIPA { $0.add("Payload/Demo.app/Info.plist", Data("garbage".utf8)) }
        assertError(url, .invalidInfoPlist)
    }

    func testRejectsMissingBundleIdentifier() throws {
        var p = goodPlist
        p["CFBundleIdentifier"] = nil
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(p))
            z.add("Payload/Demo.app/DemoBin")
        }
        assertError(url, .missingBundleIdentifier)
    }

    func testRejectsMissingExecutableKey() throws {
        var p = goodPlist
        p["CFBundleExecutable"] = nil
        let url = try makeIPA { $0.add("Payload/Demo.app/Info.plist", try infoPlist(p)) }
        assertError(url, .missingExecutable(name: nil))
    }

    func testRejectsExecutableNotInArchive() throws {
        let url = try makeIPA { $0.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist)) }
        assertError(url, .missingExecutable(name: "DemoBin"))
    }

    func testRejectsPathTraversal() throws {
        let url = try goodIPA { $0.add("Payload/Demo.app/../../evil", Data([1])) }
        assertError(url, .unsafePath("Payload/Demo.app/../../evil"))
    }

    func testRejectsAbsolutePath() throws {
        let url = try goodIPA { $0.add("/etc/passwd", Data([1])) }
        assertError(url, .unsafePath("/etc/passwd"))
    }

    func testRejectsCRCMismatch() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist), corruptCRC: true)
            z.add("Payload/Demo.app/DemoBin")
        }
        assertError(url, .corruptEntry("Payload/Demo.app/Info.plist"))
    }

    func testRejectsEncryptedEntry() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist), encrypted: true)
            z.add("Payload/Demo.app/DemoBin")
        }
        assertError(url, .unsupportedZip("encrypted entry"))
    }

    func testMissingFileSurfacesUnreadable() {
        let url = dir.appendingPathComponent("nope.ipa")
        XCTAssertThrowsError(try IPAInspector.inspect(url: url)) { error in
            guard case .unreadable = error as? IPAError else { return XCTFail("got \(error)") }
        }
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    // MARK: - Archive parsing audit regressions

    private func goodZip(_ tweak: (inout ZipFixture) throws -> Void = { _ in }) throws -> URL {
        try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist))
            z.add("Payload/Demo.app/DemoBin", Data(repeating: 1, count: 8))
            try tweak(&z)
        }
    }

    private func assertRejected(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try IPAInspector.inspect(url: url), "expected rejection", file: file, line: line)
    }

    func testRejectsDuplicateEntryNames() throws {
        assertError(try goodZip { $0.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist)) },
                    .duplicateEntry("Payload/Demo.app/Info.plist"))
    }

    func testRejectsCaseInsensitiveDuplicates() throws {
        assertRejected(try goodZip { $0.add("Payload/Demo.app/INFO.plist", try infoPlist(goodPlist)) })
    }

    func testRejectsUnicodeNormalizationDuplicates() throws {
        assertRejected(try goodZip {
            $0.add("Payload/Demo.app/caf\u{E9}", Data([1]))
            $0.add("Payload/Demo.app/cafe\u{301}", Data([2]))
        })
    }

    func testRejectsNonCanonicalPaths() throws {
        for bad in ["Payload/Demo.app//extra", "Payload/./Demo.app/x", "Payload/Demo.app/./x"] {
            let url = try goodZip { $0.add(bad, Data([1])) }
            assertError(url, .unsafePath(bad))
        }
    }

    func testRejectsInvalidUTF8Names() throws {
        let url = try goodZip { z in
            z.add("placeholder", Data([1])) { $0.rawName = Data([0x50, 0xFF, 0xFE]) }
        }
        assertRejected(url)
    }

    func testRejectsAmbiguousEndOfCentralDirectory() throws {
        var fake = Data()
        fake.le32(0x06054b50)
        fake.append(Data(count: 18))
        let url = try goodZip { $0.comment = fake }
        assertError(url, .unsupportedZip("ambiguous end of central directory"))
    }

    func testRejectsEntryCountSmallerThanDirectory() throws {
        let url = try goodZip { $0.eocdCount = 1 }
        assertError(url, .notAZip)
    }

    func testRejectsMultiDiskArchive() throws {
        let url = try goodZip { $0.eocdDisk = 1 }
        assertError(url, .unsupportedZip("multi-disk archive"))
    }

    func testRejectsLocalHeaderNameMismatch() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist)) { $0.localName = "Payload/Other.app/Info.plist" }
            z.add("Payload/Demo.app/DemoBin", Data([1]))
        }
        assertError(url, .corruptEntry("Payload/Demo.app/Info.plist"))
    }

    func testRejectsOverlappingEntries() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist))
            z.add("Payload/Demo.app/DemoBin", Data(repeating: 1, count: 8)) { $0.centralOffset = 0 }
        }
        assertRejected(url)
    }

    func testRejectsHugeDeclaredUncompressedSize() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist), deflate: true) {
                $0.claimedUncompressed = 0x7FFF_FFFF
            }
            z.add("Payload/Demo.app/DemoBin", Data([1]))
        }
        assertError(url, .unsupportedZip("entry too large: Payload/Demo.app/Info.plist"))
    }

    func testRejectsHugeDeclaredCompressedSize() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist), deflate: true) {
                $0.claimedCompressed = 0x7FFF_FFFF
            }
            z.add("Payload/Demo.app/DemoBin", Data([1]))
        }
        assertRejected(url)
    }

    func testRejectsDeflateStreamLongerThanDeclared() throws {
        // Attacker declares 10 bytes + CRC of the 10-byte prefix; the stream really holds 1000.
        let big = Data((0..<1000).map { UInt8($0 & 0xff) })
        let prefixCRC = CRC32.checksum(big.prefix(10))
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", big, deflate: true) {
                $0.claimedUncompressed = 10
                $0.claimedCRC = prefixCRC
            }
            z.add("Payload/Demo.app/DemoBin", Data([1]))
        }
        assertError(url, .corruptEntry("Payload/Demo.app/Info.plist"))
    }

    func testRejectsStoredSizeMismatch() throws {
        let url = try makeIPA { z in
            z.add("Payload/Demo.app/Info.plist", try infoPlist(goodPlist)) { $0.claimedUncompressed = 3 }
            z.add("Payload/Demo.app/DemoBin", Data([1]))
        }
        assertRejected(url)
    }

    func testAppNamedFileIsNotAnAppFolder() throws {
        let url = try makeIPA { $0.add("Payload/Demo.app", Data([1])) }
        assertError(url, .noApp)
    }

    /// Opt-in: IPA_PATH=/path/to/app.ipa swift test --filter testRealIPA
    func testRealIPA() throws {
        guard let path = ProcessInfo.processInfo.environment["IPA_PATH"] else { throw XCTSkip("IPA_PATH not set") }
        let m = try IPAInspector.inspect(url: URL(fileURLWithPath: path))
        XCTContext.runActivity(named: "\(m)") { _ in }
        try "\(m)".write(toFile: "/private/tmp/real-ipa.txt", atomically: true, encoding: .utf8)
        XCTAssertFalse(m.bundleIdentifier.isEmpty)
    }

    // MARK: embedded profile: development vs distribution

    private func profileBytes(getTaskAllow: Bool?) -> Data {
        var ent: [String: Any] = ["application-identifier": "TEAM.com.example.demo"]
        if let g = getTaskAllow { ent["get-task-allow"] = g }
        let xml = try! PropertyListSerialization.data(fromPropertyList: ["Name": "p", "Entitlements": ent], format: .xml, options: 0)
        // A real profile is CMS-wrapped: binary junk, then the XML plist, then junk.
        return Data([0x30, 0x82, 0x0a, 0x00, 0x06, 0x09]) + xml + Data([0x00, 0x01, 0x02])
    }

    func testReadsGetTaskAllowFromEmbeddedProfile() throws {
        for (flag, want) in [(true, true), (false, false)] {
            let url = try goodIPA { z in z.add("Payload/Demo.app/embedded.mobileprovision", self.profileBytes(getTaskAllow: flag)) }
            let m = try IPAInspector.inspect(url: url)
            XCTAssertTrue(m.hasEmbeddedProfile)
            XCTAssertEqual(m.embeddedProfileGetTaskAllow, want)
        }
    }

    func testGetTaskAllowIsNilWhenAbsentOrUnreadable() throws {
        XCTAssertNil(try IPAInspector.inspect(url: try goodIPA()).embeddedProfileGetTaskAllow)
        let noKey = try goodIPA { z in z.add("Payload/Demo.app/embedded.mobileprovision", self.profileBytes(getTaskAllow: nil)) }
        XCTAssertNil(try IPAInspector.inspect(url: noKey).embeddedProfileGetTaskAllow)
        let junk = try goodIPA { z in z.add("Payload/Demo.app/embedded.mobileprovision", Data(repeating: 0xAB, count: 300)) }
        let m = try IPAInspector.inspect(url: junk)
        XCTAssertTrue(m.hasEmbeddedProfile)
        XCTAssertNil(m.embeddedProfileGetTaskAllow)
    }
}
