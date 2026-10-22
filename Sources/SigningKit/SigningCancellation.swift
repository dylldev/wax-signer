import Foundation

/// One operation's cooperative cancellation, safe to consult from Dispatch extraction workers.
/// Publication includes the final R2 integrity gate and atomic promotion and is deliberately not interrupted.
public final class SigningCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var claimed = false
    private var publishing = false
    public init() {}
    public func cancel() { lock.withLock { if !publishing { cancelled = true } } }
    public func check() throws {
        let state = lock.withLock { (cancelled, publishing) }
        if state.1 { return }
        try Task.checkCancellation()
        if state.0 { throw CancellationError() }
    }
    func claim() throws {
        try check()
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            guard !claimed else { throw SigningError.bundle("a signing cancellation token can only be used for one IPA operation") }
            claimed = true
        }
    }
    func beginPublication() throws {
        try Task.checkCancellation()
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            publishing = true
        }
    }
}
