import Foundation

/// Structural validation shared by the verifier's page and special-slot readers. No cryptographic verdict here.
enum SignatureLayout {
    static func slots(_ bytes: Data) throws -> [Int: Data] {
        func bad(_ message: String) -> SigningError { .machO("invalid embedded signature: \(message)") }
        guard bytes.count >= 12, CheckedBytes.be32(bytes, 0) == 0xFADE0CC0 else { throw bad("header") }
        let length = CheckedBytes.be32(bytes, 4), count = CheckedBytes.be32(bytes, 8)
        guard length >= 12, length <= bytes.count, count <= (length - 12) / 8 else { throw bad("index table") }
        // LC_CODE_SIGNATURE may reserve zero-filled alignment space beyond the SuperBlob.
        guard bytes[(bytes.startIndex + length)..<bytes.endIndex].allSatisfy({ $0 == 0 }) else { throw bad("nonzero trailing data") }
        let indexEnd = 12 + count * 8
        var entries: [(type: Int, range: Range<Int>)] = []
        var types: Set<Int> = []
        for i in 0..<count {
            let type = CheckedBytes.be32(bytes, 12 + i * 8), off = CheckedBytes.be32(bytes, 16 + i * 8)
            guard off >= indexEnd, CheckedBytes.contains(off, 8, in: length) else { throw bad("blob index is within the signature") }
            let size = CheckedBytes.be32(bytes, off + 4)
            guard size >= 8, CheckedBytes.contains(off, size, in: length) else { throw bad("blob length") }
            let range = off..<(off + size)
            guard types.insert(type).inserted else { throw bad("no duplicate blob slots") }
            entries.append((type, range))
        }
        let sorted = entries.sorted { $0.range.lowerBound < $1.range.lowerBound }
        for i in 1..<max(1, sorted.count) {
            guard sorted[i - 1].range.upperBound <= sorted[i].range.lowerBound else { throw bad("overlapping blobs") }
        }
        // Copy only after proving disjointness, so aliased blobs cannot multiply allocations.
        return Dictionary(uniqueKeysWithValues: entries.map {
            ($0.type, Data(bytes[(bytes.startIndex + $0.range.lowerBound)..<(bytes.startIndex + $0.range.upperBound)]))
        })
    }

    /// Wax emits DER CMS. Enforce the outer SEQUENCE boundary before the BER-capable CMS reader is used.
    static func validateCMS(_ data: Data) throws {
        func bad() -> SigningError { .machO("invalid CMS: expected one complete DER SEQUENCE") }
        guard data.count >= 2, data[data.startIndex] == 0x30 else { throw bad() }
        let first = Int(data[data.startIndex + 1])
        var header = 2, length = first
        if first >= 128 {
            let n = first & 0x7F
            guard n >= 1, n <= 4, CheckedBytes.contains(2, n, in: data.count), data[data.startIndex + 2] != 0 else { throw bad() }
            length = 0
            for i in 0..<n { length = length << 8 | Int(data[data.startIndex + 2 + i]) }
            guard length >= 128 else { throw bad() }
            header += n
        }
        guard length == data.count - header else { throw bad() }
    }

    struct CodeDirectory {
        let hashOffset: Int, specialCount: Int, codeCount: Int, codeLimit: Int, pageSize: Int

        init(_ bytes: Data) throws {
            func bad(_ message: String) -> SigningError { .machO("invalid CodeDirectory: \(message)") }
            guard bytes.count >= 88, CheckedBytes.be32(bytes, 0) == 0xFADE0C02,
                  CheckedBytes.be32(bytes, 4) == bytes.count else { throw bad("header or length") }
            // Wax emits the executable-segment (0x20400) layout. Do not interpret other versions as this one.
            guard CheckedBytes.be32(bytes, 8) == 0x20400 else { throw bad("unsupported version") }
            guard bytes[bytes.startIndex + 36] == 32, bytes[bytes.startIndex + 37] == 2 else { throw bad("unsupported hash format") }
            let log = Int(bytes[bytes.startIndex + 39])
            guard log >= 12, log < 32 else { throw bad("page size") }
            pageSize = 1 << log
            hashOffset = CheckedBytes.be32(bytes, 16); specialCount = CheckedBytes.be32(bytes, 24)
            codeCount = CheckedBytes.be32(bytes, 28); codeLimit = CheckedBytes.be32(bytes, 32)
            guard hashOffset >= 88, hashOffset <= bytes.count,
                  specialCount <= (hashOffset - 88) / 32,
                  codeCount <= (bytes.count - hashOffset) / 32,
                  codeCount == codeLimit / pageSize + (codeLimit % pageSize == 0 ? 0 : 1) else { throw bad("hash table ranges or page count") }
            let stringsEnd = hashOffset - specialCount * 32
            for field in [20, 48] {
                let start = CheckedBytes.be32(bytes, field)
                if field == 48 && start == 0 { continue }
                guard start >= 88, start < stringsEnd,
                      bytes[(bytes.startIndex + start)..<(bytes.startIndex + stringsEnd)].contains(0) else { throw bad("identifier or team string") }
            }
            // Nonzero scatter/pre-encrypt tables and 64-bit-only limits require a different evaluation path.
            guard CheckedBytes.be32(bytes, 44) == 0,
                  CheckedBytes.be32(bytes, 56) == 0,
                  CheckedBytes.be32(bytes, 60) == codeLimit else { throw bad("unsupported scatter or code limit") }
        }
    }
}
