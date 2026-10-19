import Compression

/// A libcompression stream, with the awkward parts kept in one place.
///
/// Creating one needs `dst_ptr`/`src_ptr` set to something before `compression_stream_init` runs. Callers pass
/// `UnsafePointer(bitPattern: 1)`, a value that looks like a pointer, is not one, and works only because init
/// overwrites both fields before reading them. Repeating that idiom at each call site is how a future edit ends up
/// dereferencing it, so it lives here instead.
///
/// `deinit` destroys the stream, which is why there is no `destroy()` to forget to call.
public final class CompressionStream {
    private var raw: compression_stream

    public init?(_ operation: compression_stream_operation, _ algorithm: compression_algorithm) {
        raw = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                 src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&raw, operation, algorithm) == COMPRESSION_STATUS_OK else { return nil }
    }

    deinit { compression_stream_destroy(&raw) }

    /// Hands the stream its next slice of input. A nil base with a zero count is the "nothing left" signal.
    public func feed(_ base: UnsafePointer<UInt8>?, _ count: Int) {
        raw.src_ptr = base ?? UnsafePointer(bitPattern: 1)!
        raw.src_size = count
    }

    /// Runs the stream, writing into `buffer`. The caller appends the first `buffer.count - pendingOutput` bytes.
    public func drain(into buffer: UnsafeMutableBufferPointer<UInt8>, finalize: Bool = false) -> compression_status {
        raw.dst_ptr = buffer.baseAddress!
        raw.dst_size = buffer.count
        return compression_stream_process(&raw, finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
    }

    /// Input bytes the backend has not consumed yet. Internal read-ahead can consume bytes past a codec's
    /// logical end, so zero does not establish an exact single-stream boundary (notably for DEFLATE).
    public var pendingInput: Int { raw.src_size }
    /// Free space left in the destination buffer.
    public var pendingOutput: Int { raw.dst_size }
}
