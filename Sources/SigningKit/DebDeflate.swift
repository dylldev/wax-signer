import Foundation
import zlib

/// Raw DEFLATE with an exact end-of-stream boundary. Apple Compression may consume buffered trailing bytes,
/// so its pendingInput is not a sufficient single-member gzip framing check. zlib restores unused input at END.
enum DebDeflate {
    static func decode(_ input: Data) throws -> Data {
        guard !input.isEmpty, input.count <= Int(UInt32.max) else { throw DebArchive.bad }
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw DebArchive.bad
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = UInt32(raw.count)
            while true {
                let before = stream.avail_in
                let status = buffer.withUnsafeMutableBufferPointer { destination in
                    stream.next_out = destination.baseAddress!
                    stream.avail_out = UInt32(destination.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = buffer.count - Int(stream.avail_out)
                guard produced <= DebArchive.maxDecompressed - output.count else { throw DebArchive.bad }
                output.append(buffer, count: produced)
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, stream.total_in == input.count else { throw DebArchive.bad }
                    return
                }
                guard status == Z_OK, produced != 0 || stream.avail_in < before else { throw DebArchive.bad }
            }
        }
        return output
    }
}
