import Foundation

/// Which identifier a nested bundle (extension, Watch app) can take when its app is renamed, best first.
enum NestedIdentifier {
    /// The full suffix after the app's own ID comes first (so `com.foo.app.share.ext` stays distinguishable from
    /// `com.foo.app.ext`), then just the last component, then the original ID unchanged (some profiles still permit it).
    static func candidates(original: String, mainOriginal: String, newMain: String) -> [String] {
        var out: [String] = []
        if original.hasPrefix(mainOriginal + ".") {
            out.append(newMain + "." + String(original.dropFirst(mainOriginal.count + 1)))
        }
        out.append(newMain + "." + (original.split(separator: ".").last.map(String.init) ?? original))
        out.append(original)
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}
