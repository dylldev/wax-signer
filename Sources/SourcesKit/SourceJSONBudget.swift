import Foundation

/// Constant-space lexical budgets, not another JSON decoder. Foundation still validates JSON/schema.
/// Count unknown values too: lenient app decoding must not turn resource-limit failures into skipped rows.
enum SourceJSONBudget {
    static func validate(_ data: Data, limits: SourceParser.Limits,
                         checkpoint: () throws -> Void = { try Task.checkCancellation() }) throws {
        let maximum = SourceParser.Limits()
        guard (1...maximum.maxBytes).contains(limits.maxBytes),
              (1...maximum.maxContainers).contains(limits.maxContainers),
              (1...maximum.maxTokens).contains(limits.maxTokens),
              (1...maximum.maxDepth).contains(limits.maxDepth),
              (1...maximum.maxStringBytes).contains(limits.maxStringBytes),
              limits.deadline.isFinite, limits.deadline > 0, limits.deadline <= 60 else {
            throw SourceError.resourceLimit("invalid parser budget")
        }
        guard data.count <= limits.maxBytes else { throw SourceError.resourceLimit("JSON byte limit") }
        try checkpoint()
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var depth = 0, containers = 0, tokens = 0, stringBytes = 0
            var inString = false, escaped = false, inAtom = false
            // RFC8259 network JSON is UTF-8. Preserve a UTF-8 BOM; reject UTF-16/32 rather than
            // scanning its byte geometry as if it were UTF-8. Unescaped NUL is never legal UTF-8 JSON.
            let start = bytes.count >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf ? 3 : 0
            func token() throws {
                guard tokens < limits.maxTokens else { throw SourceError.resourceLimit("JSON token limit") }
                tokens += 1
            }
            for offset in start..<bytes.count {
                if offset % 65_536 == 0 { try checkpoint() }
                let byte = bytes[offset]
                if byte == 0 || byte == 0xff || byte == 0xfe { throw SourceError.notJSON }
                if inString {
                    if byte == 0x22 && !escaped { inString = false; continue }
                    guard stringBytes < limits.maxStringBytes else { throw SourceError.resourceLimit("JSON string byte limit") }
                    stringBytes += 1
                    if escaped { escaped = false }
                    else if byte == 0x5c { escaped = true }
                    continue
                }
                switch byte {
                case 0x22: // string/key
                    try token(); inString = true; escaped = false; stringBytes = 0; inAtom = false
                case 0x7b, 0x5b: // object/array
                    guard depth < limits.maxDepth else { throw SourceError.resourceLimit("JSON nesting limit") }
                    guard containers < limits.maxContainers else { throw SourceError.resourceLimit("JSON container limit") }
                    try token(); containers += 1; depth += 1; inAtom = false
                case 0x7d, 0x5d:
                    guard depth > 0 else { throw SourceError.notJSON }
                    depth -= 1; inAtom = false
                case 0x20, 0x09, 0x0a, 0x0d, 0x2c, 0x3a:
                    inAtom = false
                default:
                    if !inAtom { try token(); inAtom = true }
                }
            }
            guard !inString, depth == 0 else { throw SourceError.notJSON }
        }
        try checkpoint()
    }
}
