import XCTest
@testable import IPAKit

private final class ExtractionObservations: @unchecked Sendable {
    let lock = NSLock()
    var clock: UInt64 = 0
    var free: [Int64] = []
    var cancelled = false
    func now() -> UInt64 { lock.withLock { clock } }
    func freeBytes() -> Int64 { lock.withLock { free.isEmpty ? .max : free.removeFirst() } }
    func cancel() { lock.withLock { cancelled = true } }
    func checkCancellation() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}

final class ExtractionBudgetTests: XCTestCase {
    private var root: URL!
    private var source: URL { root.appendingPathComponent("input.ipa") }
    private var output: URL { root.appendingPathComponent("tree") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("extraction-budget-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func fixture(count: Int = 3, bytes: Int = 16, deflate: Bool = false) throws {
        var zip = ZipFixture()
        for i in 0..<count { zip.add("Payload/Demo.app/file\(i)", Data(repeating: UInt8(i), count: bytes), deflate: deflate) }
        try zip.write(to: source)
    }
    private func extract(limits: IPAExtractor.Limits = .init(), observations: ExtractionObservations,
                         progress: ((Int, Int) -> Void)? = nil) throws {
        _ = try IPAExtractor.extract(session: IPAArchiveSession(url: source), to: output, limits: limits, progress: progress, byteProgress: nil,
            checkCancellation: { try observations.checkCancellation() },
            environment: .init(now: { observations.now() }, freeBytes: { _ in observations.freeBytes() }))
    }
    func testInvalidBudgetsFailBeforeCreatingDestination() throws {
        try fixture()
        for invalid in 0..<4 {
            var limits = IPAExtractor.Limits()
            switch invalid { case 0: limits.maximumConcurrentEntries = 0; case 1: limits.maximumConcurrentEntries = 65
            case 2: limits.minimumFreeBytes = -1; default: limits.deadline = .infinity }
            XCTAssertThrowsError(try extract(limits: limits, observations: ExtractionObservations())) {
                XCTAssertEqual($0 as? IPAExtractor.BudgetError, .invalidLimits)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
    func testInsufficientInitialStorageRemovesOnlyOwnedDestinationAndPreservesArchive() throws {
        try fixture(); let original = try Data(contentsOf: source), observations = ExtractionObservations()
        observations.free = [0]
        XCTAssertThrowsError(try extract(observations: observations)) {
            guard case .diskSpace = $0 as? IPAExtractor.BudgetError else { return XCTFail("wrong error: \($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path)); XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testExistingDestinationAndUnknownFilesSurviveBudgetFailure() throws {
        try fixture(); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let good = output.appendingPathComponent("previous-good.ipa"), bytes = Data("valuable user artifact".utf8); try bytes.write(to: good)
        let observations = ExtractionObservations(); observations.free = [0]
        XCTAssertThrowsError(try extract(observations: observations))
        XCTAssertEqual(try Data(contentsOf: good), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["previous-good.ipa"])
    }
    func testMonotonicDeadlineIsEnforcedBeforeWriting() throws {
        try fixture()
        let clock = ExtractionObservations(), budget = try ExtractionBudget(limits: .init(), directory: root,
            environment: .init(now: { clock.now() }, freeBytes: { _ in .max }), cancellation: {})
        clock.clock = 1_800_000_000_000
        XCTAssertThrowsError(try budget.begin(total: 1)) { XCTAssertEqual($0 as? IPAExtractor.BudgetError, .deadline) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testDiskIsRecheckedDuringOneLargeStreamingEntry() throws {
        try fixture(count: 1, bytes: 8 * 1024 * 1024 + 1, deflate: true)
        let original = try Data(contentsOf: source), observations = ExtractionObservations()
        // Initial full expansion check, entry-start check, then the 8MiB write checkpoint.
        observations.free = [.max, .max, 0]
        XCTAssertThrowsError(try extract(observations: observations)) {
            guard case .diskSpace = $0 as? IPAExtractor.BudgetError else { return XCTFail("wrong error: \($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path)); XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testCooperativeCancellationBetweenEntriesCleansOwnedPartials() throws {
        try fixture(); let original = try Data(contentsOf: source), observations = ExtractionObservations()
        var limits = IPAExtractor.Limits(); limits.maximumConcurrentEntries = 1
        XCTAssertThrowsError(try extract(limits: limits, observations: observations, progress: { done, _ in if done == 1 { observations.cancel() } })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path)); XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testStorageObservationIOErrorsArePropagated() throws {
        struct Failure: Error {}
        try fixture()
        XCTAssertThrowsError(try IPAExtractor.extract(session: IPAArchiveSession(url: source), to: output, limits: .init(), progress: nil, byteProgress: nil,
            environment: .init(now: { 0 }, freeBytes: { _ in throw Failure() }))) { XCTAssertTrue($0 is Failure) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testReserveArithmeticOverflowIsAControlledConfigurationError() throws {
        try fixture(); var limits = IPAExtractor.Limits(); limits.minimumFreeBytes = .max
        XCTAssertThrowsError(try extract(limits: limits, observations: ExtractionObservations())) {
            XCTAssertEqual($0 as? IPAExtractor.BudgetError, .invalidLimits)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testLongSymlinkIsRejectedBeforeReadingOrCRCVerification() throws {
        var zip = ZipFixture(); zip.add("Payload/Demo.app/link", Data(repeating: 97, count: 4096), corruptCRC: true) { $0.unixMode = 0o120777 }
        try zip.write(to: source)
        XCTAssertThrowsError(try extract(observations: ExtractionObservations())) {
            guard case .unsafePath(let why) = $0 as? IPAError else { return XCTFail("must refuse length before decompression/CRC: \($0)") }
            XCTAssertTrue(why.contains("too long"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testOneAndTwoWorkerConfigurationsPreserveExactFiles() throws {
        try fixture(count: 12)
        for workers in [1, 2] {
            var limits = IPAExtractor.Limits(); limits.maximumConcurrentEntries = workers
            try extract(limits: limits, observations: ExtractionObservations())
            for i in 0..<12 { XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Payload/Demo.app/file\(i)")), Data(repeating: UInt8(i), count: 16)) }
            try FileManager.default.removeItem(at: output)
        }
    }
}
