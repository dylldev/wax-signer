import Foundation

/// Reads an existing embedded signature's entitlements without trusting its offsets: anything out of range is
/// treated as "no entitlements" instead of trapping, because the bytes come from an IPA the user picked.
enum BlobReader {
    static let embeddedSignatureMagic = Blob.embeddedSignature
    static let entitlementsMagic = Blob.entitlementsXML
    static let entitlementsSlot = Blob.Slot.entitlementsXML

    static func entitlements(inSignature blob: Data) -> [String: Any]? {
        let base = blob.startIndex
        func u32(_ o: Int) -> Int? {
            guard o >= 0, o + 4 <= blob.count else { return nil }
            return (0..<4).reduce(0) { $0 << 8 | Int(blob[base + o + $1]) }
        }
        guard u32(0) == Int(embeddedSignatureMagic), let count = u32(8), count >= 0, count <= (blob.count - 12) / 8 else { return nil }
        for i in 0..<count {
            guard let type = u32(12 + 8 * i), let off = u32(16 + 8 * i) else { return nil }
            guard type == Int(entitlementsSlot), u32(off) == Int(entitlementsMagic), let len = u32(off + 4),
                  len >= 8, off + len <= blob.count else { continue }
            let xml = blob[(base + off + 8)..<(base + off + len)]
            return try? PropertyListSerialization.propertyList(from: Data(xml), format: nil) as? [String: Any]
        }
        return nil
    }
}
