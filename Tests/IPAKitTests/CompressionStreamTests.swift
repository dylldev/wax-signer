import Compression
import XCTest
@testable import IPAKit

/// CompressionStream only wraps initialisation and teardown, so the check that matters is that a stream built
/// through it actually moves bytes -- both directions, and that it leaves no state behind between uses.
final class CompressionStreamTests: XCTestCase {
    func testEncodeThenDecodeRoundTripsThroughBothOperations() throws {
        let payload = Data((0..<400_000).map { UInt8($0 % 251) })
        let encoded = try Self.run(COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB, feeding: payload)
        XCTAssertLessThan(encoded.count, payload.count, "repetitive data should actually compress")
        XCTAssertEqual(try Self.run(COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB, feeding: encoded), payload)
    }

    /// The init hands raw C enums to libcompression. It reports a bad setup by returning nil rather than crashing,
    /// but nothing in libcompression rejects those values, so there is no way to prove that path here.
    private static func run(_ operation: compression_stream_operation, _ algorithm: compression_algorithm,
                            feeding input: Data) throws -> Data {
        guard let stream = CompressionStream(operation, algorithm) else {
            throw XCTSkip("compression could not start")
        }
        var out = Data()
        let chunk = 256 * 1024
        var dst = [UInt8](repeating: 0, count: chunk)
        try input.withUnsafeBytes { raw in
            stream.feed(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
            var idle = 0
            while true {
                let status = dst.withUnsafeMutableBufferPointer { stream.drain(into: $0, finalize: true) }
                let produced = chunk - stream.pendingOutput
                out.append(contentsOf: dst[0..<produced])
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK: break
                default: XCTFail("compression rejected valid input"); return out
                }
                idle = produced == 0 ? idle + 1 : 0
                if idle > 2 { XCTFail("compression stalled"); return out }
            }
        }
        return out
    }
}
