import Foundation

/// Bounds are relative to a structure, not just its backing file. Subtraction avoids overflowing offset + length.
enum CheckedBytes {
    static func contains(_ offset: Int, _ length: Int, in limit: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= limit && length <= limit - offset
    }

    static func contains(_ offset: UInt64, _ length: UInt64, in limit: UInt64) -> Bool {
        offset <= limit && length <= limit - offset
    }

    static func be32(_ data: Data, _ offset: Int) -> Int {
        // Callers first validate the enclosing fixed-size record.
        (0..<4).reduce(0) { $0 << 8 | Int(data[data.startIndex + offset + $1]) }
    }
}
