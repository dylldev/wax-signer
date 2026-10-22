import XCTest
@testable import IPAKit

final class CRC32Tests: XCTestCase {
    /// The textbook one-byte-at-a-time version, kept only as the reference for the fast one.
    private func reference(_ data: [UInt8]) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    func testTheStandardCheckValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testMatchesTheReferenceForEveryLengthAndAlignment() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<5000).map { _ in UInt8.random(in: 0...255, using: &generator) }
        for length in [0, 1, 7, 8, 9, 15, 16, 17, 63, 64, 65, 1000, 4096, 4999] {
            for offset in 0..<9 where offset + length <= bytes.count {
                let slice = Array(bytes[offset..<(offset + length)])
                XCTAssertEqual(CRC32.checksum(Data(slice)), reference(slice), "length \(length) offset \(offset)")
            }
        }
    }

    func testChunkedUpdatesEqualOneBigUpdate() {
        let bytes = (0..<100_003).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761) }
        var state = CRC32.begin()
        var i = 0
        for size in [1, 3, 8, 13, 4096, 65_536, 30_000, 1] where i < bytes.count {
            let end = min(bytes.count, i + size)
            state = CRC32.update(state, Data(bytes[i..<end])); i = end
        }
        state = CRC32.update(state, Data(bytes[i...]))
        XCTAssertEqual(CRC32.finish(state), reference(bytes))
    }
}
