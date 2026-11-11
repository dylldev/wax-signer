import Foundation
import Network

/// Uploading a signed app can spend hundreds of megabytes. Wax waits for Wi-Fi unless the person allows cellular,
/// and never asks for the phone host, which stays on the device.
public enum UploadNetworkPolicy {
    /// `expensive` is the system's own answer for the current path, which covers cellular and personal hotspot.
    public static func blocksUpload(remote: Bool, expensive: Bool, allowCellular: Bool) -> Bool {
        remote && expensive && !allowCellular
    }

    public static let message = "Wax uploads over Wi-Fi only, and this connection looks like cellular or a hotspot. "
        + "Join Wi-Fi, or turn on “Upload over cellular” in Settings."

    /// The current path's cost, read once. Nil when the system has not answered yet.
    public static func currentPathIsExpensive(timeout: TimeInterval = 2) async -> Bool? {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "wax.network.path")
        let decided = PathAnswer()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            monitor.pathUpdateHandler = { path in
                guard decided.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied ? path.isExpensive : nil)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard decided.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    private final class PathAnswer: @unchecked Sendable {
        private let lock = NSLock()
        private var answered = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if answered { return false }; answered = true; return true }
    }
}
