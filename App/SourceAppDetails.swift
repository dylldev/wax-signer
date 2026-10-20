import Foundation
import InstallKit
import SourcesKit

/// Display-only, bounded source claims beside metadata from an actually committed IPA entry.
/// Never associates artifacts by matching their names/versions and never exposes download URL tokens.
struct SourceAppDetails {
    struct Field: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }
    let advertised: [Field]
    let saved: [Field]
    let differences: [String]
    init(app: SourceApp, saved entry: LibraryEntry?) {
        advertised = [
            Field(title: "Developer", value: Self.text(app.developer, fallback: "Not provided")),
            Field(title: "Description", value: Self.text(app.summary, limit: 16_384, fallback: "No description provided")),
            Field(title: "Bundle ID", value: Self.text(app.bundleID, fallback: "Not provided")),
            Field(title: "Version", value: Self.text(app.version, fallback: "Not provided")),
            Field(title: "Advertised size", value: app.size.flatMap { $0 >= 0 ? Self.bytes($0) : nil } ?? "Not provided"),
            Field(title: "Download host", value: Self.text(app.downloadURL.host ?? "", fallback: "Not provided")),
        ]
        guard let entry else { saved = []; differences = []; return }
        saved = [Field(title: "Inspected name", value: Self.text(entry.name)),
                 Field(title: "Inspected bundle ID", value: Self.text(entry.bundleID)),
                 Field(title: "Inspected version", value: Self.text(entry.version)),
                 Field(title: "Inspected build", value: Self.text(entry.build ?? "", fallback: "Not recorded")),
                 Field(title: "Saved IPA size", value: Self.bytes(entry.size)),
                 Field(title: "Saved IPA SHA-256", value: Self.text(entry.sha256 ?? "", fallback: "Not yet recorded (legacy entry)"))]
        var changed: [String] = []
        if app.bundleID != entry.bundleID { changed.append("The saved IPA's bundle ID differs from the source claim.") }
        if !app.version.isEmpty, app.version != entry.version { changed.append("The saved IPA's version differs from the source claim.") }
        if let size = app.size, size >= 0, size != entry.size { changed.append("The saved IPA's size differs from the source claim.") }
        differences = changed
    }
    private static func bytes(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
    private static func text(_ input: String, limit: Int = 2048, fallback: String = "Not provided") -> String {
        guard !input.isEmpty else { return fallback }
        let prefix = input.prefix(limit + 1)
        return prefix.count > limit ? String(prefix.prefix(limit)) + "… (display shortened)" : String(prefix)
    }
}
