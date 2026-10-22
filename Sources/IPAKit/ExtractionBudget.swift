import Foundation

/// Test seams for resource observations, not an alternate archive parser.
struct ExtractionEnvironment: Sendable {
    let now: @Sendable () -> UInt64
    let freeBytes: @Sendable (URL) throws -> Int64
    static let live = ExtractionEnvironment(now: { DispatchTime.now().uptimeNanoseconds }, freeBytes: { directory in
        let values = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let size = values[.systemFreeSize] as? NSNumber else { throw IPAError.unreadable("Cannot measure free storage for extraction.") }
        return size.int64Value
    })
}

/// Shared by a bounded number of workers. Counters/probe cadence are locked; user callbacks run outside the lock.
final class ExtractionBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let limits: IPAExtractor.Limits
    private let environment: ExtractionEnvironment
    private let directory: URL
    private let cancellation: @Sendable () throws -> Void
    private let started: UInt64
    private let duration: UInt64
    private var written = 0
    private var sinceProbe = 0
    init(limits: IPAExtractor.Limits, directory: URL, environment: ExtractionEnvironment,
         cancellation: @escaping @Sendable () throws -> Void) throws {
        guard limits.maxTotalBytes >= 0, limits.maxEntries >= 0,
              limits.maximumConcurrentEntries > 0, limits.maximumConcurrentEntries <= 64,
              limits.minimumFreeBytes >= 0, limits.deadline.isFinite, limits.deadline > 0, limits.deadline <= 86400 else {
            throw IPAExtractor.BudgetError.invalidLimits
        }
        self.limits = limits; self.directory = directory; self.environment = environment; self.cancellation = cancellation
        started = environment.now(); duration = UInt64(limits.deadline * 1_000_000_000)
    }
    func begin(total: Int) throws {
        try check()
        let (required, overflow) = Int64(total).addingReportingOverflow(limits.minimumFreeBytes)
        guard !overflow else { throw IPAExtractor.BudgetError.invalidLimits }
        try disk(required: required)
    }
    func check(probeDisk: Bool = false) throws {
        try cancellation()
        let current = environment.now()
        guard current >= started, current - started < duration else { throw IPAExtractor.BudgetError.deadline }
        if probeDisk { try disk(required: limits.minimumFreeBytes) }
    }
    func beforeWrite(_ count: Int) throws {
        try check()
        let probe = try lock.withLock { () throws -> Bool in
            guard count >= 0, count <= limits.maxTotalBytes - written else { throw IPAError.unsupportedZip("extraction exceeds its byte limit") }
            written += count
            sinceProbe += count
            if sinceProbe >= 8 * 1024 * 1024 { sinceProbe = 0; return true }
            return false
        }
        if probe {
            let (required, overflow) = limits.minimumFreeBytes.addingReportingOverflow(Int64(count))
            guard !overflow else { throw IPAExtractor.BudgetError.invalidLimits }
            try disk(required: required)
        }
    }
    private func disk(required: Int64) throws {
        let available = try environment.freeBytes(directory)
        guard available >= required else { throw IPAExtractor.BudgetError.diskSpace(required: required, available: max(0, available)) }
    }
}
