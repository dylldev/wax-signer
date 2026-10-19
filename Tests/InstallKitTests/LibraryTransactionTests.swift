import XCTest
@testable import InstallKit

final class LibraryTransactionTests: XCTestCase {
    private var base: URL!
    private var root: URL { base.appendingPathComponent("Library") }
    enum Stop: Error { case simulated }
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("library-txn-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }
    private func source(_ name: String = "input", _ text: String = "original") throws -> URL {
        let url = base.appendingPathComponent(name + ".ipa"); try Data(text.utf8).write(to: url); return url
    }
    private func save(_ lib: IPALibrary, _ file: URL, kind: LibraryEntry.Kind = .unsigned, build: String = "1") throws -> LibrarySaveResult {
        try lib.save(file: file, kind: kind, name: "Demo", version: "1.0", bundleID: "com.demo", build: build, provenance: kind == .signed ? .waxSigned : .fileImport)
    }
    private func assertSource(_ file: URL, _ text: String = "original", file f: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: file), Data(text.utf8), file: f, line: line)
    }
    private func legacy(_ files: [(UUID, String, String)]) throws {
        let folder = root.appendingPathComponent("unsigned"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries: [[String: Any]] = []
        for (id, name, content) in files {
            try Data(content.utf8).write(to: folder.appendingPathComponent(name))
            entries.append(["id": id.uuidString, "fileName": name, "kind": "unsigned", "name": "Demo", "version": "1", "bundleID": "com.demo", "size": content.utf8.count, "added": 0])
        }
        try JSONSerialization.data(withJSONObject: entries).write(to: root.appendingPathComponent("index.json"))
    }
    func testExactDuplicateReusesEntryAndDoesNotStoreAnotherArtifact() throws {
        let file = try source(), lib = IPALibrary(root: root)
        let first = try save(lib, file), second = try save(lib, file)
        XCTAssertFalse(first.alreadySaved); XCTAssertTrue(second.alreadySaved); XCTAssertEqual(first.entry.id, second.entry.id)
        XCTAssertEqual(lib.entries(.unsigned).count, 1); XCTAssertNotNil(first.entry.sha256); XCTAssertEqual(first.entry.sha256?.count, 64)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("unsigned").path).count, 1)
        try assertSource(file)
    }
    func testEqualMetadataAndSizeWithDifferentBytesPreservesBoth() throws {
        let lib = IPALibrary(root: root), a = try save(lib, source("a", "identity-A")), b = try save(lib, source("b", "identity-B"))
        XCTAssertNotEqual(a.entry.id, b.entry.id); XCTAssertNotEqual(a.entry.sha256, b.entry.sha256)
        XCTAssertEqual(lib.entries(.unsigned).count, 2); try assertSource(lib.url(for: a.entry), "identity-A"); try assertSource(lib.url(for: b.entry), "identity-B")
    }
    func testBuildNumbersAndDistinctSignedConfigurationsRemainDistinct() throws {
        let lib = IPALibrary(root: root)
        let a = try save(lib, source("a", "signed-A-edits-A"), kind: .signed, build: "1")
        let b = try save(lib, source("b", "signed-B-edits-B"), kind: .signed, build: "2")
        XCTAssertEqual(lib.entries(.signed).count, 2); XCTAssertEqual(a.entry.build, "1"); XCTAssertEqual(b.entry.build, "2")
        XCTAssertNotEqual(a.entry.sha256, b.entry.sha256); XCTAssertEqual(a.entry.provenance, .waxSigned)
    }
    func testSignedAndUnsignedIdentityNamespacesStayDistinct() throws {
        let lib = IPALibrary(root: root), file = try source()
        let unsigned = try save(lib, file), signed = try save(lib, file, kind: .signed)
        XCTAssertNotEqual(unsigned.entry.id, signed.entry.id); XCTAssertEqual(unsigned.entry.sha256, signed.entry.sha256)
        XCTAssertEqual(lib.entries(.unsigned).count, 1); XCTAssertEqual(lib.entries(.signed).count, 1)
    }
    func testConcurrentInsertionsAcrossInstancesAreSerialized() throws {
        let file = try source(), lock = NSLock()
        var ids: [UUID] = [], errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do { let result = try self.save(IPALibrary(root: self.root), file); lock.withLock { ids.append(result.entry.id) } }
            catch { lock.withLock { errors.append(error.localizedDescription) } }
        }
        XCTAssertTrue(errors.isEmpty, "\(errors)"); XCTAssertEqual(Set(ids).count, 1)
        XCTAssertEqual(IPALibrary(root: root).entries(.unsigned).count, 1)
    }
    func testBeforeCopyFailureKeepsSourceAndPreviousArtifact() throws {
        let good = IPALibrary(root: root), previous = try save(good, source("old", "previous"))
        let lib = IPALibrary(root: root) { point, _ in if point == .beforeCopy { throw Stop.simulated } }
        let file = try source(); XCTAssertThrowsError(try save(lib, file)); try assertSource(file)
        try assertSource(good.url(for: previous.entry), "previous")
        XCTAssertEqual(IPALibrary(root: root).entries(.unsigned).count, 1)
    }
    func testOutOfSpaceDuringCopyKeepsSource() throws {
        let lib = IPALibrary(root: root) { point, _ in if point == .copyChunk { throw CocoaError(.fileWriteOutOfSpace) } }
        let file = try source()
        XCTAssertThrowsError(try save(lib, file)) { XCTAssertEqual(($0 as NSError).code, NSFileWriteOutOfSpaceError) }
        try assertSource(file); XCTAssertTrue(lib.entries(.unsigned).isEmpty)
    }
    func testMissingSourceDoesNotCreateEntry() throws {
        let lib = IPALibrary(root: root)
        XCTAssertThrowsError(try save(lib, base.appendingPathComponent("missing.ipa")))
        XCTAssertTrue(lib.entries(.unsigned).isEmpty)
    }
    func testSourceChangeAfterCopyIsRejected() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in
            if point == .afterCopy { try Data("modified".utf8).write(to: file) }
        }
        XCTAssertThrowsError(try save(lib, file)) { guard case LibraryError.changed = $0 else { return XCTFail("\($0)") } }
        XCTAssertTrue(lib.entries(.unsigned).isEmpty); try assertSource(file, "modified")
    }
    func testStagedTruncationAndCorruptionAreRejected() throws {
        for truncated in [true, false] {
            let localRoot = base.appendingPathComponent("lib-\(truncated)")
            let lib = IPALibrary(root: localRoot) { point, file in
                if point == .afterCopy { try Data((truncated ? "x" : "corrupt!").utf8).write(to: file) }
            }
            let file = try source()
            XCTAssertThrowsError(try save(lib, file)) { guard case LibraryError.changed = $0 else { return XCTFail("\($0)") } }
            try assertSource(file); XCTAssertTrue(lib.entries(.unsigned).isEmpty)
        }
    }
    func testHashReadErrorPropagatesWithoutEntry() throws {
        let lib = IPALibrary(root: root) { point, _ in if point == .hashRead { throw Stop.simulated } }
        let file = try source(); XCTAssertThrowsError(try save(lib, file)) { XCTAssertTrue($0 is Stop) }
        try assertSource(file); XCTAssertTrue(lib.entries(.unsigned).isEmpty)
    }
    func testIndexFailureLeavesJournalAndPublishedIPARecoverable() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in if point == .beforeIndexWrite { throw Stop.simulated } }
        XCTAssertThrowsError(try save(lib, file)); XCTAssertTrue(lib.entries(.unsigned).isEmpty)
        let retained = lib.recoveryItems(); XCTAssertEqual(retained.count, 1); try assertSource(retained[0].url); try assertSource(file)
        let next = IPALibrary(root: root); try next.recover()
        XCTAssertEqual(next.entries(.unsigned).count, 1); XCTAssertTrue(next.recoveryItems().isEmpty)
        try assertSource(next.url(for: next.entries(.unsigned)[0]))
    }
    func testCrashBeforePublicationIsRecoveredIdempotently() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in if point == .beforePublish { throw Stop.simulated } }
        XCTAssertThrowsError(try save(lib, file))
        let next = IPALibrary(root: root); try next.recover(); try next.recover()
        XCTAssertEqual(next.entries(.unsigned).count, 1); try assertSource(file)
    }
    func testCrashAfterPublicationIsRecoveredIdempotently() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in if point == .afterPublish { throw Stop.simulated } }
        XCTAssertThrowsError(try save(lib, file))
        let id = try XCTUnwrap(lib.recoveryItems().first?.pendingID)
        for _ in 0..<3 { let next = IPALibrary(root: root); try next.recover(); XCTAssertEqual(next.entries(.unsigned).map(\.id), [id]) }
    }
    func testCrashAfterIndexCommitDoesNotCreateAnotherEntry() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in if point == .afterIndexWrite { throw Stop.simulated } }
        XCTAssertThrowsError(try save(lib, file))
        let next = IPALibrary(root: root); try next.recover()
        XCTAssertEqual(next.entries(.unsigned).count, 1); XCTAssertTrue(next.recoveryItems().isEmpty)
    }
    func testCleanupFailureReportsCommittedSaveAndCanBeRetried() throws {
        let lib = IPALibrary(root: root) { point, _ in if point == .beforeCleanup { throw Stop.simulated } }
        let result = try save(lib, source()); XCTAssertNotNil(result.warning)
        XCTAssertEqual(lib.entries(.unsigned).map(\.id), [result.entry.id])
        let next = IPALibrary(root: root); try next.recover(); XCTAssertTrue(next.recoveryItems().isEmpty)
    }
    func testDeletionCleanupFailureRetainsTombstoneAndFile() throws {
        let good = IPALibrary(root: root), entry = try save(good, source()).entry, file = good.url(for: entry)
        let lib = IPALibrary(root: root) { point, _ in if point == .beforeCleanup { throw Stop.simulated } }
        XCTAssertThrowsError(try lib.remove(entry)) { guard case LibraryError.cleanupPending = $0 else { return XCTFail("\($0)") } }
        XCTAssertTrue(lib.entries(.unsigned).isEmpty); try assertSource(file)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("index.json"))) as! [String: Any]
        XCTAssertEqual((json["deletions"] as? [Any])?.count, 1)
        let next = IPALibrary(root: root); try next.recover(); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testLegacyMetadataPreservesIDsNamesAndDistinctContents() throws {
        let a = UUID(), b = UUID(); try legacy([(a,"a.ipa","contentA"),(b,"b.ipa","contentB")])
        let lib = IPALibrary(root: root)
        XCTAssertEqual(Set(lib.entries(.unsigned).map(\.id)), [a,b]); XCTAssertNil(lib.entries(.unsigned)[0].sha256)
        let duplicate = try save(lib, source("duplicate","contentA"))
        XCTAssertTrue(duplicate.alreadySaved); XCTAssertEqual(duplicate.entry.id, a)
        XCTAssertEqual(Set(IPALibrary(root: root).entries(.unsigned).map(\.id)), [a,b])
        try assertSource(root.appendingPathComponent("unsigned/a.ipa"), "contentA"); try assertSource(root.appendingPathComponent("unsigned/b.ipa"), "contentB")
    }
    func testSharedLegacyFilenameIsNotDeletedWhileAnotherEntryReferencesIt() throws {
        let a=UUID(), b=UUID(); try legacy([(a,"shared.ipa","original"),(b,"shared.ipa","original")])
        let lib = IPALibrary(root: root), first = try XCTUnwrap(lib.entries(.unsigned).first { $0.id == a })
        try lib.remove(first)
        XCTAssertEqual(lib.entries(.unsigned).map(\.id), [b]); try assertSource(lib.url(for: lib.entries(.unsigned)[0]))
    }
    func testMissingFileReferenceSurvivesOtherIndexMutations() throws {
        let id=UUID(); try legacy([(id,"missing.ipa","original")]); try FileManager.default.removeItem(at: root.appendingPathComponent("unsigned/missing.ipa"))
        let lib = IPALibrary(root: root); XCTAssertTrue(lib.entries(.unsigned).isEmpty); XCTAssertNotNil(lib.issue)
        _ = try save(lib, source("other","different"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("index.json"))) as! [String: Any]
        XCTAssertEqual((json["entries"] as? [Any])?.count, 2)
    }
    func testDamagedIndexBlocksWritesAndPreservesBytesUntilExplicitRepair() throws {
        let id = UUID(); try legacy([(id,"orphan.ipa","original")])
        let index = root.appendingPathComponent("index.json"), damaged = Data("{broken json".utf8); try damaged.write(to: index)
        let lib = IPALibrary(root: root); XCTAssertNotNil(lib.issue)
        XCTAssertThrowsError(try save(lib, source())) { guard case LibraryError.damagedIndex = $0 else { return XCTFail("\($0)") } }
        XCTAssertEqual(try Data(contentsOf: index), damaged); XCTAssertFalse(lib.recoveryItems().isEmpty)
        try lib.repairIndex(); XCTAssertFalse(lib.entries(.unsigned).isEmpty)
        let firstIDs = lib.entries(.unsigned).map(\.id); try lib.repairIndex(); XCTAssertEqual(lib.entries(.unsigned).map(\.id), firstIDs)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("index-damaged-") })
    }
    func testInterruptedStagingRemainsRecoverableWithoutAutomaticAcceptance() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in if point == .afterCopy { throw Stop.simulated } }
        XCTAssertThrowsError(try save(lib, file))
        let next = IPALibrary(root: root); try next.recover()
        XCTAssertTrue(next.entries(.unsigned).isEmpty); XCTAssertEqual(next.recoveryItems().count, 1); try assertSource(next.recoveryItems()[0].url)
    }
    func testBrokenJournalDoesNotHideOrDeleteItsArtifact() throws {
        let lib = IPALibrary(root: root), pending = try lib.prepare(file: source(), kind: .unsigned, name: "Retained", version: "1", bundleID: "com.demo")
        try Data("broken".utf8).write(to: root.appendingPathComponent("pending/\(pending.id)/record.json"))
        let next = IPALibrary(root: root); try next.recover()
        XCTAssertTrue(next.entries(.unsigned).isEmpty); XCTAssertEqual(next.recoveryItems().count, 1); try assertSource(next.recoveryItems()[0].url)
    }
    func testUnknownOrphanSurvivesRepeatedRecovery() throws {
        let folder = root.appendingPathComponent("signed"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let orphan = folder.appendingPathComponent("unknown.ipa"); try Data("original".utf8).write(to: orphan)
        let lib = IPALibrary(root: root)
        for _ in 0..<3 { try lib.recover(); XCTAssertEqual(lib.recoveryItems().count, 1); try assertSource(orphan) }
        XCTAssertTrue(lib.entries(.signed).isEmpty)
    }
    func testSymlinkedFileFolderAndIndexAreRefusedWithoutTouchingTarget() throws {
        let outside = try source("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("index.json").path, withDestinationPath: outside.path)
        let lib = IPALibrary(root: root)
        XCTAssertThrowsError(try save(lib, source())); try assertSource(outside)
        try FileManager.default.removeItem(at: root.appendingPathComponent("index.json"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("unsigned").path, withDestinationPath: base.path)
        XCTAssertThrowsError(try save(lib, source())); try assertSource(outside)
    }
    func testStoredBytesAreRecheckedBeforeDuplicateSuccess() throws {
        let lib = IPALibrary(root: root), file = try source(), first = try save(lib, file)
        try Data("modified".utf8).write(to: lib.url(for: first.entry))
        let second = try save(lib, file)
        XCTAssertFalse(second.alreadySaved); XCTAssertNotEqual(first.entry.id, second.entry.id)
        XCTAssertEqual(lib.entries(.unsigned).count, 2); try assertSource(lib.url(for: second.entry))
    }
    func testIncomingFilesAreKeptAndUnknownFilesAreNeverCleaned() throws {
        let lib = IPALibrary(root: root), folder = try lib.incomingDirectory(), file = folder.appendingPathComponent("download.ipa")
        try Data("original".utf8).write(to: file)
        try lib.recover(); XCTAssertEqual(lib.recoveryItems().count, 1)
        let external = try source("external"); try lib.removeIncoming(external); try assertSource(external)
        try lib.removeIncoming(file); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testLargeStreamingSaveTimingObservation() throws {
        let file = base.appendingPathComponent("large.ipa"), out = try XCTUnwrap(FileManager.default.createFile(atPath: file.path, contents: nil) ? FileHandle(forWritingTo: file) : nil)
        for _ in 0..<32 { try out.write(contentsOf: Data(repeating: 0x5a, count: 256 * 1024)) }; try out.close()
        let lib = IPALibrary(root: root), start = Date(), result = try save(lib, file)
        print("R3_BENCH bytes=\(result.entry.size) save_s=\(Date().timeIntervalSince(start)) buffer_bytes=\(LibraryFileIO.chunkSize)")
        XCTAssertEqual(result.entry.size, 8 * 1024 * 1024)
        XCTAssertEqual(try LibraryFileIO.hash(lib.url(for: result.entry)).sha256, result.entry.sha256)
    }
    func testLegacyCaseAliasesNeverDeleteAnotherReference() throws {
        let a = UUID(), b = UUID(); try legacy([(a,"Shared.ipa","original"),(b,"shared.ipa","original")])
        let lib = IPALibrary(root: root), first = try XCTUnwrap(lib.entries(.unsigned).first { $0.id == a })
        try lib.remove(first)
        XCTAssertEqual(lib.entries(.unsigned).map(\.id), [b])
        try assertSource(lib.url(for: lib.entries(.unsigned)[0]))
    }
    func testSourceDisappearingDuringCopyRetainsTheStagedCopy() throws {
        let file = try source(), lib = IPALibrary(root: root) { point, _ in
            if point == .copyChunk, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        XCTAssertThrowsError(try save(lib, file)); XCTAssertTrue(lib.entries(.unsigned).isEmpty)
        let retained = try XCTUnwrap(lib.recoveryItems().first); try assertSource(retained.url)
    }
    func testExtraUnrecognizedCandidateIsExposedWithoutDeletion() throws {
        let lib = IPALibrary(root: root), pending = try lib.reserve(kind: .signed, name: "Unfinished", provenance: .waxSigned)
        let folder = try lib.pendingURL(pending.id).deletingLastPathComponent()
        let file = folder.appendingPathComponent(".wax-archive-candidate.part"); try Data("original".utf8).write(to: file)
        try lib.recover(); XCTAssertEqual(lib.recoveryItems().count, 1)
        XCTAssertNil(lib.recoveryItems()[0].pendingID); try assertSource(file)
    }

    func testOrphanAdoptionPreservesFilenameWithoutAnotherIPA() throws {
        let folder = root.appendingPathComponent("unsigned"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("legacy-orphan.ipa"); try Data("original".utf8).write(to: file)
        let lib = IPALibrary(root: root), saved = try XCTUnwrap(lib.adoptOrphan(file, name: "Recovered", version: "1", bundleID: "com.demo", build: "1"))
        XCTAssertEqual(saved.entry.provenance, .recoveredUnknown)
        XCTAssertEqual(lib.url(for: saved.entry).lastPathComponent, file.lastPathComponent)
        XCTAssertTrue(lib.recoveryItems().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["legacy-orphan.ipa"])
        XCTAssertEqual(try lib.adoptOrphan(file, name: "Recovered", version: "1", bundleID: "com.demo", build: "1")?.entry.id, saved.entry.id)
    }

    func testCommitRetryAfterJournalCleanupConfirmsIndexedBytes() throws {
        let lib = IPALibrary(root: root), saved = try save(lib, source())
        let retry = try lib.commit(saved.entry.id)
        XCTAssertTrue(retry.alreadySaved); XCTAssertEqual(retry.entry.id, saved.entry.id)
        try assertSource(lib.url(for: retry.entry))
    }

}
