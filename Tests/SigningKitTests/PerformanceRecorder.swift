import Foundation

/// Progress callbacks can arrive from parallel workers. Only this lock owns timing state.
final class PerformanceRecorder: @unchecked Sendable {
    struct Mark: Codable { let label: String; let seconds: Double }
    struct Snapshot: Codable { let seconds: Double; let marks: [Mark] }
    private let lock = NSLock()
    private let start: TimeInterval
    private var last: TimeInterval
    private var label = "start"
    private var marks: [Mark] = []
    private var completed: Snapshot?
    init() { let now = ProcessInfo.processInfo.systemUptime; start = now; last = now }
    func record(_ next: String) {
        lock.withLock {
            guard completed == nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
            marks.append(Mark(label: label, seconds: max(0, now - last)))
            last = now; label = next
        }
    }
    func finish() -> Snapshot {
        lock.withLock {
            if let completed { return completed }
            let now = ProcessInfo.processInfo.systemUptime
            marks.append(Mark(label: label, seconds: max(0, now - last)))
            last = now
            let result = Snapshot(seconds: max(0, last - start), marks: marks)
            completed = result
            return result
        }
    }
}
