import Foundation

/// Reads an existing embedded signature's entitlements without trusting its offsets: anything out of range is
/// treated as "no entitlements" instead of trapping, because the bytes come from an IPA the user picked.
enum BlobReader {
    static let embeddedSignatureMagic = Blob.embeddedSignature
    static let entitlementsMagic = Blob.entitlementsXML
    static let entitlementsSlot = Blob.Slot.entitlementsXML

    static func entitlements(inSignature blob: Data) -> [String: Any]? {
        guard let slots = try? SignatureLayout.slots(blob), let entitlements = slots[Int(entitlementsSlot)],
              CheckedBytes.be32(entitlements, 0) == Int(entitlementsMagic) else { return nil }
        return try? PropertyListSerialization.propertyList(from: Data(entitlements.dropFirst(8)), format: nil) as? [String: Any]
    }
}
