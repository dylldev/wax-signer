import XCTest
@testable import IPAKit

private final class ArchiveObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}

final class ArchivingBudgetTests: XCTestCase {
    private var root: URL!
    private var tree: URL { root.appendingPathComponent("tree") }
    private var output: URL { root.appendingPathComponent("result.ipa") }
    private let oldOutput = Data("preserve the previous artifact".utf8)
    private var live: ArchivingEnvironment { .init(now: { 0 }, freeBytes: { _ in .max }) }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("archiving-budget-\(UUID())")
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("Payload/Demo.app"), withIntermediateDirectories: true)
        try oldOutput.write(to: output)
        try Data("unknown file".utf8).write(to: root.appendingPathComponent("unrelated"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func fixture(bytes: Int = 32, count: Int = 1) throws -> IPAArchiveManifest {
        var data = Data(count: bytes), state: UInt32 = 0x12345678
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for i in 0..<bytes { state ^= state << 13; state ^= state >> 17; state ^= state << 5; buffer[i] = UInt8(truncatingIfNeeded: state >> 16) }
        }
        for i in 0..<count {
            let file = tree.appendingPathComponent("Payload/Demo.app/file\(i)")
            try data.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: i == 0 ? 0o755 : 0o644], ofItemAtPath: file.path)
        }
        return try IPAArchiveManifest.capture(directory: tree)
    }
    private func cleanFailure(_ snapshot: IPAArchiveManifest) throws {
        XCTAssertEqual(try Data(contentsOf: output), oldOutput)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("unrelated")), Data("unknown file".utf8))
        try snapshot.verifyTree()
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), Set(["tree", "result.ipa", "unrelated"]))
    }
    private static func stagedSize(in directory: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(".wax-archive-") && $0.pathExtension == "part" }
            .compactMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size]) as? Int }.max() ?? 0
    }
    func testTemporaryFileCreationCannotTruncateAnExistingArtifact() throws {
        XCTAssertThrowsError(try IPAArchiver.createTemporaryFile(at: output)) {
            guard case .unreadable = $0 as? IPAError else { return XCTFail("wrong error: \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: output), oldOutput)
        let temporary = root.appendingPathComponent("exclusive.part")
        let handle = try IPAArchiver.createTemporaryFile(at: temporary)
        try handle.write(contentsOf: Data("owned bytes".utf8)); try handle.close()
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: temporary.path)[.posixPermissions] as? Int), 0o600)
        XCTAssertEqual(try Data(contentsOf: temporary), Data("owned bytes".utf8))
    }
    func testInvalidLimitsFailBeforeReadingTreeOrCreatingScratch() throws {
        let snapshot = try fixture()
        for i in 0..<9 {
            var limits = IPAArchiver.Limits()
            switch i {
            case 0: limits.maximumConcurrentFiles = 0
            case 1: limits.maximumConcurrentFiles = 65
            case 2: limits.maximumTemporaryBytes = -1
            case 3: limits.minimumFreeBytes = -1
            case 4: limits.deadline = .infinity
            case 5: limits.deadline = .nan
            case 6: limits.deadline = 0
            case 7: limits.deadline = 86401
            default: limits.deadline = 1e-20
            }
            XCTAssertThrowsError(try IPAArchiver.archive(directory: root.appendingPathComponent("missing"), to: output, limits: limits, environment: live)) {
                XCTAssertEqual($0 as? IPAArchiver.BudgetError, .invalidLimits)
            }
            try cleanFailure(snapshot)
        }
    }
    func testInitialLowDiskAndObservationIOErrorPreserveEveryInput() throws {
        struct Failure: Error {}
        let snapshot = try fixture()
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, environment: .init(now: { 0 }, freeBytes: { _ in 0 }))) {
            guard case .diskSpace = $0 as? IPAArchiver.BudgetError else { return XCTFail("wrong error: \($0)") }
        }
        try cleanFailure(snapshot)
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, environment: .init(now: { 0 }, freeBytes: { _ in throw Failure() }))) {
            XCTAssertTrue($0 is Failure)
        }
        try cleanFailure(snapshot)
    }
    func testTemporaryCounterBoundaryAndHostileCountsFailWithoutOverflow() throws {
        var limits = IPAArchiver.Limits(); limits.maximumTemporaryBytes = 3
        let budget = try ArchivingBudget(limits: limits, directory: root, environment: live, cancellation: {})
        try budget.beforeWrite(3)
        for count in [1, Int.max, -1] {
            XCTAssertThrowsError(try budget.beforeWrite(count)) { XCTAssertEqual($0 as? IPAArchiver.BudgetError, .temporaryBytes(limit: 3)) }
        }
    }
    func testConcurrentWritesCannotOvercommitTheSharedTemporaryBudget() throws {
        final class Claims: @unchecked Sendable {
            let lock = NSLock()
            var admitted = 0
            var errors: [Error] = []
            func accept() { lock.withLock { admitted += 1 } }
            func reject(_ error: Error) { lock.withLock { errors.append(error) } }
        }
        var limits = IPAArchiver.Limits(); limits.maximumTemporaryBytes = 1024
        let budget = try ArchivingBudget(limits: limits, directory: root, environment: live, cancellation: {})
        let claims = Claims()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            do { try budget.beforeWrite(8); claims.accept() } catch { claims.reject(error) }
        }
        XCTAssertEqual(claims.admitted, 128); XCTAssertEqual(claims.errors.count, 872)
        XCTAssertTrue(claims.errors.allSatisfy { $0 as? IPAArchiver.BudgetError == .temporaryBytes(limit: 1024) })
    }
    func testDiskReserveArithmeticOverflowIsAConfigurationError() throws {
        var limits = IPAArchiver.Limits(); limits.minimumFreeBytes = .max
        let budget = try ArchivingBudget(limits: limits, directory: root, environment: live, cancellation: {})
        XCTAssertThrowsError(try budget.beforeWrite(8 * 1024 * 1024)) { XCTAssertEqual($0 as? IPAArchiver.BudgetError, .invalidLimits) }
    }
    func testMonotonicDeadlineAndClockReversalAreControlled() throws {
        for current: UInt64 in [0, 1_800_000_000_001] {
            final class Clock: @unchecked Sendable { var time: UInt64 = 1 }
            let clock = Clock()
            let budget = try ArchivingBudget(limits: .init(), directory: root,
                environment: .init(now: { clock.time }, freeBytes: { _ in .max }), cancellation: {})
            clock.time = current
            XCTAssertThrowsError(try budget.check()) { XCTAssertEqual($0 as? IPAArchiver.BudgetError, .deadline) }
        }
    }
    func testCompressionScratchExhaustionCleansOnlyOwnedFiles() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1)
        var limits = IPAArchiver.Limits(); limits.maximumTemporaryBytes = 256
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, limits: limits, environment: live)) {
            XCTAssertEqual($0 as? IPAArchiver.BudgetError, .temporaryBytes(limit: 256))
        }
        try cleanFailure(snapshot)
    }
    func testScratchAndStagedArchiveShareOneCumulativeBudget() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1)
        let file = tree.appendingPathComponent("Payload/Demo.app/file0")
        let prepared = try IPAArchiver.precompress(file, in: root)
        try FileManager.default.removeItem(at: prepared.temp)
        var limits = IPAArchiver.Limits(); limits.maximumTemporaryBytes = prepared.comp + prepared.comp / 2
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, limits: limits, environment: live)) {
            XCTAssertEqual($0 as? IPAArchiver.BudgetError, .temporaryBytes(limit: limits.maximumTemporaryBytes))
        }
        try cleanFailure(snapshot)
    }
    func testCancellationDuringCompressionPreservesPreviousArtifact() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1), parent = root!
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, checkCancellation: {
            let dirs = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            for dir in dirs where dir.lastPathComponent.hasPrefix(".wax-archive-work-") {
                for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    if (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0) > 0 { throw CancellationError() }
                }
            }
        }, environment: live)) { XCTAssertTrue($0 is CancellationError) }
        try cleanFailure(snapshot)
    }
    func testCancellationDuringRawReusePreservesSourceAndPreviousArtifact() throws {
        _ = try fixture(bytes: 2 * 1024 * 1024 + 1)
        let original = root.appendingPathComponent("original.ipa"), extracted = root.appendingPathComponent("extracted")
        try IPAArchiver.archive(directory: tree, to: original, compressChangedFiles: false)
        let originalHash = try FileFingerprint.file(original), session = try IPAArchiveSession(url: original)
        let inventory = try session.extract(to: extracted), snapshot = try IPAArchiveManifest.capture(directory: extracted), parent = root!
        XCTAssertThrowsError(try IPAArchiver.archive(directory: extracted, to: output, reusing: original, reusingExtraction: inventory,
            verifiedManifest: snapshot, checkCancellation: {
                if Self.stagedSize(in: parent) > 256 * 1024 { throw CancellationError() }
            }, environment: live)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try FileFingerprint.file(original), originalHash); XCTAssertEqual(try Data(contentsOf: output), oldOutput)
        try snapshot.verifyTree()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".wax-archive-") })
    }
    func testManifestHashingCanBeCanceledWithoutMutatingTree() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1)
        var calls = 0
        let lock = NSLock()      // hashing runs on several threads now
        XCTAssertThrowsError(try IPAArchiveManifest.capture(directory: tree, checkpoint: {
            lock.lock(); calls += 1; let now = calls; lock.unlock()
            if now == 4 { throw CancellationError() }
        })) {
            XCTAssertTrue($0 is CancellationError)
        }
        try cleanFailure(snapshot)
    }
    func testLowStorageIsObservedDuringOneLargeStoredEntry() throws {
        let snapshot = try fixture(bytes: 8 * 1024 * 1024 + 1), parent = root!
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, compressChangedFiles: false, verifiedManifest: snapshot,
            environment: .init(now: { 0 }, freeBytes: { _ in Self.stagedSize(in: parent) > 4 * 1024 * 1024 ? 0 : .max }))) {
            guard case .diskSpace = $0 as? IPAArchiver.BudgetError else { return XCTFail("wrong error: \($0)") }
        }
        try cleanFailure(snapshot)
    }
    func testDeadlineDuringStreamingRemovesPartialWithoutReplacingOutput() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1), parent = root!
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, compressChangedFiles: false, verifiedManifest: snapshot,
            environment: .init(now: { Self.stagedSize(in: parent) > 256 * 1024 ? 1_800_000_000_000 : 0 }, freeBytes: { _ in .max }))) {
            XCTAssertEqual($0 as? IPAArchiver.BudgetError, .deadline)
        }
        try cleanFailure(snapshot)
    }
    func testUnchangedReuseNeedsNoPrecompressionScratch() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1), original = root.appendingPathComponent("original.ipa")
        try IPAArchiver.archive(directory: tree, to: original)
        let originalZip = try ZipArchive(url: original)
        var limits = IPAArchiver.Limits(); limits.maximumTemporaryBytes = (try FileFingerprint.file(original)).size + 1024
        try IPAArchiver.archive(directory: tree, to: output, reusing: original, verifiedManifest: snapshot, limits: limits, environment: live)
        try snapshot.verify(archive: output)
        let packed = try ZipArchive(url: output)
        let old = try XCTUnwrap(originalZip.entries.first { $0.name.hasSuffix("file0") }), new = try XCTUnwrap(packed.entries.first { $0.name == old.name })
        XCTAssertEqual(try originalZip.fingerprint(old).compressedSHA256, try packed.fingerprint(new).compressedSHA256)
    }
    func testOneAndTwoWorkersPreserveContentAndPermissions() throws {
        let snapshot = try fixture(bytes: 2 * 1024 * 1024 + 1, count: 4)
        for workers in [1, 2] {
            var limits = IPAArchiver.Limits(); limits.maximumConcurrentFiles = workers
            let start = DispatchTime.now().uptimeNanoseconds
            try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, limits: limits)
            let elapsed = (Double(DispatchTime.now().uptimeNanoseconds) - Double(start)) / 1_000_000_000
            let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber
            print("WAX_ARCHIVE_OBSERVATION workers=\(workers) input_bytes=\(4 * (2 * 1024 * 1024 + 1)) output_bytes=\(size?.int64Value ?? -1) seconds=\(elapsed)")
            // One observation per configuration, warm-cache synthetic data; not a baseline speedup or phone benchmark.
            try snapshot.verify(archive: output); try snapshot.verifyTree()
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".wax-archive-") })
        }
    }
    func testCancellationBeforePublicationRejectsButAfterBarrierDoesNotDiscardOutput() throws {
        let snapshot = try fixture(), observations = ArchiveObservations()
        observations.cancel()
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot,
            checkCancellation: { try observations.check() }, environment: live)) { XCTAssertTrue($0 is CancellationError) }
        try cleanFailure(snapshot)
        let after = ArchiveObservations()
        try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, validateArchive: { _ in after.cancel() },
            checkCancellation: { try after.check() }, environment: live)
        try snapshot.verify(archive: output)
    }
    func testIntegrityFailureAfterBarrierStillPreservesPreviousArtifact() throws {
        let snapshot = try fixture()
        XCTAssertThrowsError(try IPAArchiver.archive(directory: tree, to: output, verifiedManifest: snapshot, validateArchive: { staged in
            try Data("corrupt staged output".utf8).write(to: staged)
        }, environment: live)) { XCTAssertEqual($0 as? IPAError, .notAZip) }
        try cleanFailure(snapshot)
    }
}
