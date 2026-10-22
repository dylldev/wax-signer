import Foundation

struct ArchivingEnvironment: Sendable {
    let now: @Sendable () -> UInt64
    let freeBytes: @Sendable (URL) throws -> Int64
    static let live = ArchivingEnvironment(now: { DispatchTime.now().uptimeNanoseconds }, freeBytes: { directory in
        // The output parent may not exist until staging starts. Observe its nearest existing ancestor.
        var existing = directory
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        let values = try FileManager.default.attributesOfFileSystem(forPath: existing.path)
        guard let size = values[.systemFreeSize] as? NSNumber else { throw IPAError.unreadable("Cannot measure free storage for packaging.") }
        return size.int64Value
    })
}

/// Counts cumulative attempted temporary writes, not peak live disk usage. Free space is an observation,
/// not a reservation against other filesystem users. All scratch shares the staged output's parent.
final class ArchivingBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let limits: IPAArchiver.Limits
    private let environment: ArchivingEnvironment
    private let directory: URL
    private let cancellation: @Sendable () throws -> Void
    private let started: UInt64
    private let duration: UInt64
    private var written = 0
    private var sinceProbe = 0
    init(limits: IPAArchiver.Limits, directory: URL, environment: ArchivingEnvironment,
         cancellation: @escaping @Sendable () throws -> Void) throws {
        guard limits.maximumConcurrentFiles > 0, limits.maximumConcurrentFiles <= 64,
              limits.maximumTemporaryBytes >= 0, limits.minimumFreeBytes >= 0,
              limits.deadline.isFinite, limits.deadline >= 1e-9, limits.deadline <= 86400 else {
            throw IPAArchiver.BudgetError.invalidLimits
        }
        self.limits = limits; self.directory = directory; self.environment = environment; self.cancellation = cancellation
        started = environment.now(); duration = UInt64(limits.deadline * 1_000_000_000)
    }
    func check(probeDisk: Bool = false) throws {
        try cancellation()
        let current = environment.now()
        guard current >= started, current - started < duration else { throw IPAArchiver.BudgetError.deadline }
        if probeDisk { try disk(additionalBytes: 0) }
    }
    func beforeWrite(_ count: Int) throws {
        try check()
        let probe = try lock.withLock { () throws -> Bool in
            guard count >= 0, count <= limits.maximumTemporaryBytes - written else {
                throw IPAArchiver.BudgetError.temporaryBytes(limit: limits.maximumTemporaryBytes)
            }
            written += count
            let interval = 8 * 1024 * 1024
            if count >= interval || sinceProbe >= interval - count { sinceProbe = 0; return true }
            sinceProbe += count
            return false
        }
        if probe { try disk(additionalBytes: count) }
    }
    private func disk(additionalBytes: Int) throws {
        let (required, overflow) = limits.minimumFreeBytes.addingReportingOverflow(Int64(additionalBytes))
        guard !overflow else { throw IPAArchiver.BudgetError.invalidLimits }
        let available = try environment.freeBytes(directory)
        guard available >= required else { throw IPAArchiver.BudgetError.diskSpace(required: required, available: max(0, available)) }
    }
}
