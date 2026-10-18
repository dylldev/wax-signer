import Foundation
import InstallKit
import IPAKit

/// The shelf the IPA tab shows. One shared copy so signing can file results while the tab is on screen.
@MainActor
final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()

    private let library = IPALibrary.standard()
    @Published private(set) var unsigned: [LibraryEntry] = []
    @Published private(set) var signed: [LibraryEntry] = []

    init() { refresh() }

    func refresh() {
        unsigned = library.entries(.unsigned)
        signed = library.entries(.signed)
    }

    func url(for entry: LibraryEntry) -> URL { library.url(for: entry) }
    func bytes(_ kind: LibraryEntry.Kind) -> Int { library.totalBytes(kind) }

    /// Files a copy of `file` and waits for it (big IPAs take a moment to copy).
    @discardableResult
    func fileNow(_ file: URL, info: IPAMetadata, signed: Bool? = nil) async -> LibraryEntry? {
        let kind: LibraryEntry.Kind = (signed ?? info.hasCodeSignature) ? .signed : .unsigned
        let name = info.displayName.isEmpty ? info.bundleIdentifier : info.displayName
        let library = library
        let entry = await Task.detached { () -> LibraryEntry? in
            do {
                return try library.add(file: file, kind: kind, name: name, version: info.version, bundleID: info.bundleIdentifier)
            } catch {
                ImportLogs.shared.log("library: could not file \(ImportLog.describe(error))")
                return nil
            }
        }.value
        refresh()
        return entry
    }

    /// Same, without waiting.
    func file(_ file: URL, info: IPAMetadata, signed: Bool? = nil) {
        Task { await fileNow(file, info: info, signed: signed) }
    }

    func remove(_ entry: LibraryEntry) { try? library.remove(entry); refresh() }
    func clear(_ kind: LibraryEntry.Kind) { try? library.clear(kind); refresh() }
}
