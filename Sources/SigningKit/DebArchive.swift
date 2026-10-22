import Foundation

/// Byte geometry for Debian's ar/tar containers, independent of the compression backend.
enum DebArchive {
    static let maxDecompressed = 1 << 30
    static let maxFile = 512 << 20
    static var bad: SigningError { .bundle("The tweak's archive is damaged or uses an unsupported numeric encoding.") }

    private static func number(_ text: String, radix: Int) throws -> Int {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && Int($0 - 48) < radix }),
              let value = Int(text, radix: radix) else { throw bad }
        return value
    }

    static func arMembers(_ input: Data) throws -> [(name: String, bytes: Data)] {
        let d = Data(input)
        guard d.count >= 8, d.prefix(8) == Data("!<arch>\n".utf8) else { throw bad }
        var out: [(String, Data)] = []
        var pos = 8
        while pos < d.count {
            guard CheckedBytes.contains(pos, 60, in: d.count) else { throw bad }
            let header = d[pos..<(pos + 60)]
            guard header.suffix(2) == Data("`\n".utf8) else { throw bad }
            func text(_ r: Range<Int>) -> String {
                String(decoding: header[(header.startIndex + r.lowerBound)..<(header.startIndex + r.upperBound)], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
            }
            var name = text(0..<16)
            let size = try number(text(48..<58), radix: 10)
            var start = pos + 60, length = size
            guard CheckedBytes.contains(start, size, in: d.count) else { throw bad }
            let end = start + size
            if size % 2 != 0 {
                guard end < d.count, d[end] == 10 else { throw bad }
            }
            let symbolTable = name == "/" || name == "//" || name == "/SYM64/"
            if name.hasPrefix("#1/") {
                let n = try number(String(name.dropFirst(3)), radix: 10)
                guard n > 0, n <= length, let decoded = String(data: d[start..<(start + n)], encoding: .utf8) else { throw bad }
                name = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                start += n; length -= n
            } else if name.hasPrefix("/"), !symbolTable {
                throw bad // GNU long-name table references are not Debian data member names.
            } else if name.hasSuffix("/"), !symbolTable { name.removeLast() }
            guard !name.isEmpty, !name.utf8.contains(0) else { throw bad }
            if !name.hasPrefix("__.SYMDEF"), !symbolTable { out.append((name, Data(d[start..<(start + length)]))) }
            pos = end + size % 2
        }
        return out
    }

    struct TarFile { let name: String; let bytes: Data }

    static func tarFiles(_ input: Data) throws -> [TarFile] {
        let tar = Data(input)
        guard tar.count <= maxDecompressed else { throw bad }
        var files: [TarFile] = []
        var pos = 0
        var longName: String?
        while CheckedBytes.contains(pos, 512, in: tar.count) {
            let h = tar[pos..<(pos + 512)]
            if h.allSatisfy({ $0 == 0 }) {
                guard longName == nil, CheckedBytes.contains(pos, 1024, in: tar.count), tar.count % 512 == 0,
                      tar[pos..<tar.count].allSatisfy({ $0 == 0 }) else { throw bad }
                return files
            }
            func str(_ r: Range<Int>) -> String {
                String(decoding: h[(h.startIndex + r.lowerBound)..<(h.startIndex + r.upperBound)].prefix { $0 != 0 }, as: UTF8.self)
            }
            let checksum = try number(str(148..<156), radix: 8)
            let sum = (0..<512).reduce(0) { $0 + ((148..<156).contains($1) ? 32 : Int(h[h.startIndex + $1])) }
            guard checksum == sum else { throw bad }
            let size = try number(str(124..<136), radix: 8)
            let dataStart = pos + 512
            guard CheckedBytes.contains(dataStart, size, in: tar.count) else { throw bad }
            // Once size is bounded by the (capped) archive, rounding cannot overflow.
            let padded = size + (512 - size % 512) % 512
            guard CheckedBytes.contains(dataStart, padded, in: tar.count) else { throw bad }
            let body = tar[dataStart..<(dataStart + size)]
            let type = h[h.startIndex + 156]
            var name = str(0..<100)
            if str(257..<263) == "ustar" { // POSIX prefix; GNU's old header uses these bytes differently.
                let prefix = str(345..<500)
                if !prefix.isEmpty { name = prefix + "/" + name }
            }
            if type == UInt8(ascii: "L") {
                guard longName == nil, size > 0, size <= 4096, body.last == 0,
                      let decoded = String(data: body.dropLast(), encoding: .utf8), !decoded.utf8.contains(0) else { throw bad }
                longName = decoded
            } else {
                if let l = longName { name = l; longName = nil }
                if type == 0 || type == UInt8(ascii: "0") {
                    guard size <= maxFile, !name.isEmpty else { throw bad }
                    files.append(TarFile(name: name, bytes: Data(body)))
                }
            }
            pos = dataStart + padded
        }
        throw bad // A partial header or missing two-block terminator is not a complete TAR archive.
    }
}

/// Validates the gzip wrapper separately from raw DEFLATE decoding.
enum DebGzip {
    struct Member {
        let payload: Data
        let checksum: UInt32
        let size: UInt32
        func validate(_ output: Data) throws {
            guard output.count <= DebArchive.maxDecompressed, UInt32(output.count) == size,
                  DebGzip.crc32(output) == checksum else { throw DebArchive.bad }
        }
    }

    static func parse(_ input: Data) throws -> Member {
        let d = Data(input)
        guard d.count > 18, d[0] == 0x1F, d[1] == 0x8B, d[2] == 8, d[3] & 0xE0 == 0 else { throw DebArchive.bad }
        let flags = d[3], end = d.count - 8
        var i = 10
        if flags & 4 != 0 {
            guard CheckedBytes.contains(i, 2, in: end) else { throw DebArchive.bad }
            let length = Int(d[i]) | Int(d[i + 1]) << 8
            i += 2
            guard CheckedBytes.contains(i, length, in: end) else { throw DebArchive.bad }
            i += length
        }
        for bit in [UInt8(8), 16] where flags & bit != 0 {
            guard i < end, let zero = d[i..<end].firstIndex(of: 0) else { throw DebArchive.bad }
            i = zero + 1
        }
        if flags & 2 != 0 {
            guard CheckedBytes.contains(i, 2, in: end),
                  (UInt32(d[i]) | UInt32(d[i + 1]) << 8) == (crc32(d.prefix(i)) & 0xFFFF) else { throw DebArchive.bad }
            i += 2
        }
        guard i < end else { throw DebArchive.bad }
        return Member(payload: Data(d[i..<end]), checksum: d.u32(end), size: d.u32(end + 4))
    }

    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 0 ? c >> 1 : (c >> 1) ^ 0xEDB8_8320 }
    }
    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(UInt32.max) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}
