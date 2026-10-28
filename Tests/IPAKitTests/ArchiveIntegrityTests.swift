import Foundation
import XCTest
@testable import IPAKit

final class ArchiveIntegrityTests: XCTestCase {
    private var dir: URL!
    private let path = "Payload/Demo.app/asset"
    private let collisionA = Data([0x9c,0x1f,0xe1,0x8a,0x5d,0xb4,0x78,0x6f,0x3c,0x53,0x93,0xb1,0x1f,0x12,0x80,0xec])
    private let collisionB = Data([0xac,0x12,0xaa,0x68,0xce,0xd7,0xe4,0x88,0xbd,0xab,0x66,0xd9,0x1f,0x1b,0x36,0x6e])

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func tree(_ name: String = "tree", bytes: Data) throws -> URL {
        let root = dir.appendingPathComponent(name)
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
        return root
    }
    private func assertIntegrity(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case IPAError.integrity = error else { return XCTFail("expected integrity rejection, got \(error)", file: file, line: line) }
        }
    }
    private func bytes(_ archive: URL, name: String? = nil) throws -> Data {
        let zip = try ZipArchive(url: archive)
        return try zip.data(for: XCTUnwrap(zip.entries.first { $0.name == (name ?? path) }))
    }
    private func collision(suffix: Int, store: Bool = false, inventory: Bool = true) throws {
        let a = collisionA + Data(repeating: 0, count: suffix), b = collisionB + Data(repeating: 0, count: suffix)
        XCTAssertEqual(a.count, b.count); XCTAssertNotEqual(a, b)
        XCTAssertEqual(CRC32.checksum(a), CRC32.checksum(b), "fixture must defeat the old size+CRC predicate")
        let originalTree = try tree("original-tree", bytes: a), original = dir.appendingPathComponent("original.ipa")
        try IPAArchiver.archive(directory: originalTree, to: original)
        let session = try IPAArchiveSession(url: original), edited = dir.appendingPathComponent("edited")
        let extracted = try session.extract(to: edited)
        try b.write(to: edited.appendingPathComponent(path))
        let output = dir.appendingPathComponent("output.ipa")
        try IPAArchiver.archive(directory: edited, to: output, reusing: original, compressChangedFiles: !store,
                                reusingExtraction: inventory ? extracted : nil)
        let unpacked = dir.appendingPathComponent("unpacked")
        try IPAExtractor.extract(ipa: output, to: unpacked)
        XCTAssertEqual(try Data(contentsOf: unpacked.appendingPathComponent(path)), b)
        if store {
            XCTAssertEqual(try ZipArchive(url: output).entries.first { $0.name == path }?.method, 0)
        }
    }
    func testAppRootManifestAcceptsTheSameInternalSymlinkAsPayloadRoot() throws {
        let root = try tree(bytes: Data("target".utf8))
        let app = root.appendingPathComponent("Payload/Demo.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("a/link").path, withDestinationPath: "../asset")
        XCTAssertNoThrow(try IPAArchiveManifest.capture(directory: root))
        XCTAssertNoThrow(try IPAArchiveManifest.capture(directory: app.deletingLastPathComponent(), rootFolder: "Demo.app"))
        try FileManager.default.removeItem(at: app.appendingPathComponent("a/link"))
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("a/link").path, withDestinationPath: "../../outside")
        XCTAssertThrowsError(try IPAArchiveManifest.capture(directory: app.deletingLastPathComponent(), rootFolder: "Demo.app"))
    }

    func testSmallCRCCollisionDoesNotRestoreOldBytes() throws { try collision(suffix: 0) }
    func testLargeCRCCollisionDoesNotRestoreOldBytes() throws { try collision(suffix: 2 * 1024 * 1024 + 1) }
    func testStoredLargeCRCCollisionDoesNotRestoreOldBytes() throws { try collision(suffix: 2 * 1024 * 1024 + 1, store: true) }
    func testLegacyReuseCallAlsoUsesContentIdentity() throws { try collision(suffix: 0, inventory: false) }

    func testUnchangedEntryReusesExactCompressedBytes() throws {
        let data = Data(repeating: 123, count: 800_000), original = dir.appendingPathComponent("original.zip")
        // Raw DEFLATE stored blocks: deliberately much larger than Wax's default compression. A recompression
        // cannot accidentally satisfy the byte-exact assertion, even if the default encoder is deterministic.
        var rawDeflate = Data(), start = 0
        while start < data.count {
            let count = min(65_535, data.count - start)
            rawDeflate.append(start + count == data.count ? 1 : 0)
            rawDeflate.le16(UInt16(count)); rawDeflate.le16(~UInt16(count))
            rawDeflate.append(data[start..<(start + count)]); start += count
        }
        var fixture = ZipFixture()
        fixture.add(path, data, deflate: true) { $0.encodedData = rawDeflate; $0.unixMode = 0o100644 }
        try fixture.write(to: original)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let inventory = try session.extract(to: extracted)
        // Metadata edits do not require recompression, but must reach the final ZIP.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: extracted.appendingPathComponent(path).path)
        let output = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: extracted, to: output, reusing: original, reusingExtraction: inventory)
        func raw(_ zip: ZipArchive) throws -> Data {
            let entry = try XCTUnwrap(zip.entries.first { $0.name == path })
            var data = Data(); try zip.copyRaw(entry, expecting: zip.fingerprint(entry)) { data.append($0) }; return data
        }
        XCTAssertEqual(try raw(session.zip), rawDeflate)
        XCTAssertEqual(try raw(session.zip), try raw(ZipArchive(url: output)))
        XCTAssertEqual(try ZipArchive(url: output).entries.first { $0.name == path }?.method, 8)
        XCTAssertEqual(try ZipArchive(url: output).entries.first { $0.name == path }?.unixMode, 0o100755)
    }

    func testInventoryRejectsDifferentSourceAndDifferentExtractionTree() throws {
        let root = try tree(bytes: collisionA), original = dir.appendingPathComponent("original.zip")
        try IPAArchiver.archive(directory: root, to: original)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let inventory = try session.extract(to: extracted)
        let other = dir.appendingPathComponent("other.zip")
        try IPAArchiver.archive(directory: root, to: other)
        assertIntegrity { try IPAArchiver.archive(directory: extracted, to: dir.appendingPathComponent("out.zip"), reusing: other, reusingExtraction: inventory) }
        assertIntegrity { try IPAArchiver.archive(directory: root, to: dir.appendingPathComponent("out.zip"), reusing: original, reusingExtraction: inventory) }
    }

    func testPathReplacementCannotSwitchOpenSource() throws {
        let root = try tree(bytes: collisionA), original = dir.appendingPathComponent("original.zip")
        try IPAArchiver.archive(directory: root, to: original)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let inventory = try session.extract(to: extracted)
        // Atomic path replacement leaves the extraction's open file descriptor attached to the old inode.
        try collisionB.write(to: root.appendingPathComponent(path))
        try IPAArchiver.archive(directory: root, to: original)
        let out = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: extracted, to: out, reusing: original, reusingExtraction: inventory)
        XCTAssertEqual(try bytes(out), collisionA)
    }

    func testInPlaceSourceCorruptionFailsWithoutReplacingOutput() throws {
        let root = try tree(bytes: collisionA), original = dir.appendingPathComponent("original.zip")
        try IPAArchiver.archive(directory: root, to: original)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let inventory = try session.extract(to: extracted)
        let entry = try XCTUnwrap(session.zip.entries.first { $0.name == path })
        let handle = try FileHandle(forUpdating: original)
        try handle.seek(toOffset: UInt64(entry.localHeaderOffset + 30 + path.utf8.count))
        try handle.write(contentsOf: Data([0xff])); try handle.close()
        let out = dir.appendingPathComponent("out.zip"), previous = Data("keep me".utf8)
        try previous.write(to: out)
        assertIntegrity { try IPAArchiver.archive(directory: extracted, to: out, reusing: original, reusingExtraction: inventory) }
        XCTAssertEqual(try Data(contentsOf: out), previous)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".wax-archive-") })
    }

    func testInvalidOriginalPayloadIsNotSilentlyRecompressed() throws {
        let root = try tree(bytes: collisionA), original = dir.appendingPathComponent("original.zip")
        var fixture = ZipFixture(); fixture.add(path, collisionA, corruptCRC: true); try fixture.write(to: original)
        XCTAssertThrowsError(try IPAArchiver.archive(directory: root, to: dir.appendingPathComponent("out.zip"), reusing: original)) {
            XCTAssertEqual($0 as? IPAError, .corruptEntry(self.path))
        }
    }

    func testMissingOriginalEntryIsSafelyCompressedFromTree() throws {
        let root = try tree(bytes: collisionB), original = dir.appendingPathComponent("original.zip")
        var fixture = ZipFixture(); fixture.add("unrelated", collisionA); try fixture.write(to: original)
        let out = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: root, to: out, reusing: original)
        XCTAssertEqual(try bytes(out), collisionB)
    }

    func testPostVerificationChangesRejectInsteadOfPublishing() throws {
        let root = try tree(bytes: collisionA), snapshot = try IPAArchiveManifest.capture(directory: root)
        let out = dir.appendingPathComponent("out.zip"), previous = Data("keep me".utf8)
        try previous.write(to: out)
        let stamp = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)[.modificationDate]!
        try collisionB.write(to: root.appendingPathComponent(path))
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: root.appendingPathComponent(path).path)
        assertIntegrity { try IPAArchiver.archive(directory: root, to: out, verifiedManifest: snapshot) }
        XCTAssertEqual(try Data(contentsOf: out), previous)
    }

    func testTreeMutationAfterPackingIsDetected() throws {
        let root = try tree(bytes: collisionA), out = dir.appendingPathComponent("out.zip")
        let previous = Data("keep me".utf8); try previous.write(to: out)
        assertIntegrity {
            try IPAArchiver.archive(directory: root, to: out, progress: { done, total in
                if done == total { try! self.collisionB.write(to: root.appendingPathComponent(self.path)) }
            })
        }
        XCTAssertEqual(try Data(contentsOf: out), previous)
    }

    func testActualCandidateBytesAreCheckedAfterAdditionalValidation() throws {
        let root = try tree(bytes: collisionA), wrongTree = try tree("wrong", bytes: collisionB)
        let wrong = dir.appendingPathComponent("wrong.zip"), out = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: wrongTree, to: wrong)
        let previous = Data("keep me".utf8); try previous.write(to: out)
        assertIntegrity {
            try IPAArchiver.archive(directory: root, to: out, validateArchive: { try Data(contentsOf: wrong).write(to: $0) })
        }
        XCTAssertEqual(try Data(contentsOf: out), previous)
    }

    func testManifestRejectsMissingExtraAndChangedPathsContentsModesAndLinks() throws {
        let root = try tree(bytes: collisionA), fm = FileManager.default
        let app = root.appendingPathComponent("Payload/Demo.app"), link = app.appendingPathComponent("link")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("asset").path)
        try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: app.path)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "asset")
        let snapshot = try IPAArchiveManifest.capture(directory: root)
        let out = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: root, to: out, verifiedManifest: snapshot)
        try snapshot.verify(archive: out)
        let zip = try ZipArchive(url: out)
        XCTAssertEqual(zip.entries.first { $0.name == "Payload/Demo.app/" }?.unixMode, 0o040750)
        XCTAssertEqual(try bytes(out, name: "Payload/Demo.app/link"), Data("asset".utf8))
        for change in 0..<7 {
            var fixture = ZipFixture()
            for record in snapshot.records.values.sorted(by: { $0.name < $1.name }) {
                if change == 0 && record.name == path { continue }
                let name = change == 1 && record.name == path ? path + "-renamed" : record.name
                let data = record.kind == .file ? (change == 2 ? collisionB : collisionA) : Data((record.target ?? "").utf8)
                let actual = change == 4 && record.kind == .symlink ? Data("missing".utf8) : data
                fixture.add(name, actual) {
                    $0.unixMode = change == 3 && record.name == path ? 0o100644 : record.mode
                    $0.externalAttributes = $0.unixMode! << 16 | (record.kind == .directory || (change == 6 && record.name == path) ? 0x10 : 0)
                }
            }
            if change == 5 { fixture.add("Payload/extra", Data()) { $0.unixMode = 0o100644 } }
            let bad = dir.appendingPathComponent("bad-\(change).zip"); try fixture.write(to: bad)
            assertIntegrity { try snapshot.verify(archive: bad) }
        }
    }

    func testReadFailuresShortEOFAndFileGrowthAreExplicit() throws {
        enum ReadFailure: Error { case interrupted }
        var reads = 0
        XCTAssertThrowsError(try FileFingerprint.read(expectedSize: 2) { _ in
            reads += 1; if reads == 1 { return Data([1]) }; throw ReadFailure.interrupted
        }) { XCTAssertTrue($0 is ReadFailure) }
        assertIntegrity { _ = try FileFingerprint.read(expectedSize: 2) { _ in nil } }
        assertIntegrity { _ = try FileFingerprint.read(expectedSize: 1) { _ in Data([1, 2]) } }
        assertIntegrity { _ = try FileFingerprint.read(expectedSize: -1) { _ in nil } }
        reads = 0
        let complete = try FileFingerprint.read(expectedSize: 2) { _ in
            reads += 1; return reads <= 2 ? Data([UInt8(reads)]) : nil
        }
        XCTAssertEqual(complete.crc32, CRC32.checksum(Data([1, 2])))
        let root = try tree(bytes: collisionA), snapshot = try IPAArchiveManifest.capture(directory: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        XCTAssertThrowsError(try IPAArchiver.archive(directory: root, to: dir.appendingPathComponent("out.zip"), verifiedManifest: snapshot))
    }

    func testClassicZIPBoundariesRejectSentinelsBeforeOutputMutation() throws {
        XCTAssertNoThrow(try ClassicZIP.entryCount(65_534))
        XCTAssertThrowsError(try ClassicZIP.entryCount(65_535))
        XCTAssertEqual(try ClassicZIP.size(Int(UInt32.max) - 1), UInt32.max - 1)
        XCTAssertThrowsError(try ClassicZIP.size(Int(UInt32.max)))
        XCTAssertThrowsError(try ClassicZIP.size(-1))
        XCTAssertEqual(try ClassicZIP.name(String(repeating: "a", count: 65_535)).count, 65_535)
        XCTAssertThrowsError(try ClassicZIP.name(String(repeating: "a", count: 65_536)))
        var fixture = ZipFixture()
        for i in 0..<65_534 { fixture.add("e\(i)") }
        let zip = dir.appendingPathComponent("boundary.zip"); try fixture.write(to: zip)
        XCTAssertEqual(try ZipArchive(url: zip).entries.count, 65_534)
        fixture.eocdCount = 65_535; try fixture.write(to: zip)
        XCTAssertThrowsError(try ZipArchive(url: zip)) { XCTAssertEqual($0 as? IPAError, .unsupportedZip("zip64")) }
        let root = try tree(bytes: collisionA), out = dir.appendingPathComponent("out.zip"), previous = Data("keep me".utf8)
        try previous.write(to: out)
        let record = IPAArchiveManifest.Record(name: "unused/", kind: .directory, mode: 0o040755, fingerprint: nil, target: nil)
        let records = Dictionary(uniqueKeysWithValues: (0..<65_535).map { ("d\($0)/", record) })
        let snapshot = IPAArchiveManifest(directory: root.standardizedFileURL.resolvingSymlinksInPath(), rootFolder: "Payload", records: records)
        XCTAssertThrowsError(try IPAArchiver.archive(directory: root, to: out, verifiedManifest: snapshot)) {
            XCTAssertEqual($0 as? IPAError, .unsupportedZip("ZIP64 sentinel entry count (maximum 65,534)"))
        }
        XCTAssertEqual(try Data(contentsOf: out), previous)
    }
    func testTruncatedSourceAndThrowingCopySinkPropagateFailure() throws {
        let root = try tree(bytes: collisionA), original = dir.appendingPathComponent("source.zip")
        try IPAArchiver.archive(directory: root, to: original)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let inventory = try session.extract(to: extracted)
        let entry = try XCTUnwrap(session.zip.entries.first { $0.name == path })
        enum Failure: Error { case write }
        XCTAssertThrowsError(try session.zip.copyRaw(entry, expecting: session.zip.fingerprint(entry)) { _ in throw Failure.write }) {
            XCTAssertTrue($0 is Failure)
        }
        let handle = try FileHandle(forWritingTo: original)
        try handle.truncate(atOffset: UInt64(entry.localHeaderOffset + 31)); try handle.close()
        let out = dir.appendingPathComponent("out.zip"), previous = Data("keep me".utf8); try previous.write(to: out)
        XCTAssertThrowsError(try IPAArchiver.archive(directory: extracted, to: out, reusing: original, reusingExtraction: inventory))
        XCTAssertEqual(try Data(contentsOf: out), previous)
    }

    func testDeflateTrailingBytesAndBadDescriptorAreRejected() throws {
        let root = try tree(bytes: collisionA), good = dir.appendingPathComponent("good.zip")
        try IPAArchiver.archive(directory: root, to: good)
        let zip = try ZipArchive(url: good), entry = try XCTUnwrap(zip.entries.first { $0.name == path })
        let payload = entry.localHeaderOffset + 30 + path.utf8.count
        let descriptor = payload + entry.compressedSize
        var data = try Data(contentsOf: good)
        data[descriptor + 4] ^= 1
        let bad = dir.appendingPathComponent("bad.zip"); try data.write(to: bad)
        XCTAssertThrowsError(try ZipArchive(url: bad)) { XCTAssertEqual($0 as? IPAError, .corruptEntry(self.path)) }

        // Construct a consistent local+central pair whose declared raw deflate stream has an extra byte.
        let compressed = ZipFixture.deflate(collisionA) + Data([0xaa])
        var fixture = ZipFixture(); fixture.add(path, compressed) {
            $0.claimedCompressed = UInt32(compressed.count); $0.claimedUncompressed = UInt32(self.collisionA.count)
            $0.claimedCRC = CRC32.checksum(self.collisionA)
        }
        try fixture.write(to: bad)
        data = try Data(contentsOf: bad)
        data[8] = 8
        let central = 30 + path.utf8.count + compressed.count
        data[central + 10] = 8
        try data.write(to: bad)
        let trailing = try ZipArchive(url: bad)
        XCTAssertThrowsError(try trailing.data(for: XCTUnwrap(trailing.entries.first))) {
            XCTAssertEqual($0 as? IPAError, .corruptEntry(self.path))
        }
    }

    func testCandidateValidationAndPromotionFailuresPreserveExistingDestination() throws {
        let root = try tree(bytes: collisionA), out = dir.appendingPathComponent("out.zip")
        let previous = Data("keep me".utf8); try previous.write(to: out)
        enum Failure: Error { case validation }
        XCTAssertThrowsError(try IPAArchiver.archive(directory: root, to: out, validateArchive: { _ in throw Failure.validation })) {
            XCTAssertTrue($0 is Failure)
        }
        XCTAssertEqual(try Data(contentsOf: out), previous)
        let occupied = dir.appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try previous.write(to: occupied.appendingPathComponent("keep"))
        XCTAssertThrowsError(try IPAArchiver.archive(directory: root, to: occupied))
        XCTAssertEqual(try Data(contentsOf: occupied.appendingPathComponent("keep")), previous)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".wax-archive-") })
    }

    func testArchiveTimingObservation() throws {
        // Reproducible generated 8 MiB fixture; observations, never a timing assertion or iPhone claim.
        var data = Data(count: 8 * 1024 * 1024)
        var state: UInt32 = 0x12345678
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<bytes.count {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                bytes[i] = i % 1024 < 768 ? 0 : UInt8(truncatingIfNeeded: state)
            }
        }
        let root = try tree(bytes: data), original = dir.appendingPathComponent("original.zip")
        let beginHash = Date(); _ = try IPAArchiveManifest.capture(directory: root)
        let hashing = Date().timeIntervalSince(beginHash)
        let begin = Date(); try IPAArchiver.archive(directory: root, to: original)
        let compressed = Date().timeIntervalSince(begin)
        let session = try IPAArchiveSession(url: original), extracted = dir.appendingPathComponent("extracted")
        let startExtract = Date(), inventory = try session.extract(to: extracted)
        let extract = Date().timeIntervalSince(startExtract)
        let startReuse = Date()
        try IPAArchiver.archive(directory: extracted, to: dir.appendingPathComponent("reused.zip"), reusing: original, reusingExtraction: inventory)
        let reuse = Date().timeIntervalSince(startReuse)
        print("R2_BENCH fixture=8MiB mixed-compressibility snapshot_hash_s=\(hashing) compress_and_gate_s=\(compressed) extraction_s=\(extract) reuse_and_gate_s=\(reuse) archive_bytes=\((try FileManager.default.attributesOfItem(atPath: original.path)[.size])!)")
    }

    func testUnreadableRegularFileIsAnExplicitError() throws {
        guard geteuid() != 0 else { throw XCTSkip("root bypasses file read permissions") }
        let root = try tree(bytes: collisionA), file = root.appendingPathComponent(path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        XCTAssertThrowsError(try IPAArchiveManifest.capture(directory: root)) { error in
            guard case IPAError.unreadable = error else { return XCTFail("expected I/O rejection, got \(error)") }
        }
    }

    func testDistantDatesAndEmptyRegularFilesRemainSupported() throws {
        let root = try tree(bytes: Data()), file = root.appendingPathComponent(path)
        for (index, date) in [Date.distantPast, Date.distantFuture].enumerated() {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
            let out = dir.appendingPathComponent("date-\(index).zip")
            try IPAArchiver.archive(directory: root, to: out)
            XCTAssertEqual(try bytes(out), Data())
        }
    }

    func testManifestUsesCanonicalParentPathsWithoutFollowingEntryLinks() throws {
        let root = try tree(bytes: collisionA)
        let alias = dir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: root.path)
        let snapshot = try IPAArchiveManifest.capture(directory: alias)
        XCTAssertEqual(Set(snapshot.records.keys), ["Payload/", "Payload/Demo.app/", path])
        let out = dir.appendingPathComponent("out.zip")
        try IPAArchiver.archive(directory: alias, to: out, verifiedManifest: snapshot)
        XCTAssertEqual(try bytes(out), collisionA)
    }

}
