import Foundation
import InstallKit
import IPAKit
import UIKit

struct ShelfSaveFailure: LocalizedError {
    let reason: String
    let artifact: URL
    let pendingID: UUID?
    var errorDescription: String? { "Save failed: \(reason) Retry Save or choose the original from Files. Keep the original; any retained copies can be recovered or exported from the IPA tab." }
}

@MainActor
final class LibraryModel: ObservableObject {
    enum SaveState {
        case idle, saving, saved(LibrarySaveResult), failed(ShelfSaveFailure)
        var confirmedSaved: Bool { if case .saved = self { return true }; return false }
        var isSaving: Bool { if case .saving = self { return true }; return false }
    }
    static let shared = LibraryModel()
    let storage: IPALibrary
    @Published private(set) var unsigned: [LibraryEntry] = []
    @Published private(set) var signed: [LibraryEntry] = []
    @Published private(set) var recovery: [LibraryRecoveryItem] = []
    @Published private(set) var saveState: SaveState = .idle
    @Published private(set) var busy = false
    @Published var message: String?
    private let announce: (String) -> Void
    private var operations = 0
    private var locations: [UUID: URL] = [:]
    private var refreshGeneration = 0

    init(library: IPALibrary = .standard(), announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) },
         load: Bool = true) {
        storage = library; self.announce = announce
        if load { Task { await refresh() } }
    }
    func refresh(recover: Bool = true) async {
        refreshGeneration += 1; let generation = refreshGeneration
        let storage = storage
        let snapshot = await Task.detached {
            var issue: String?
            if recover { do { try storage.recover() } catch { issue = error.localizedDescription } }
            let unsigned = storage.entries(.unsigned), signed = storage.entries(.signed)
            let urls = Dictionary(uniqueKeysWithValues: (unsigned + signed).map { ($0.id, storage.url(for: $0)) })
            return (unsigned, signed, storage.recoveryItems(), issue ?? storage.issue, urls)
        }.value
        guard generation == refreshGeneration else { return }
        unsigned = snapshot.0; signed = snapshot.1; recovery = snapshot.2; locations = snapshot.4
        if recover { message = snapshot.3 }
        else if let issue = snapshot.3 { message = issue }
    }
    func url(for entry: LibraryEntry) -> URL { locations[entry.id] ?? storage.root.appendingPathComponent("unavailable-\(entry.id).ipa") }
    func bytes(_ kind: LibraryEntry.Kind) -> Int { (kind == .signed ? signed : unsigned).reduce(0) { $0 + $1.size } }

    /// Picked files are copied under coordinated/security-scoped access; that access ends before UI work resumes.
    func preparePicked(_ file: URL) async throws -> (LibraryPending, IPAMetadata) {
        let storage = storage
        return try await Task.detached {
            let pending = try ExternalFile.withReadAccess(to: file) { source in
                // Reject unsupported/corrupt archives before copying a potentially huge picker input.
                let preview = try IPAInspector.inspect(url: source)
                return try storage.prepare(file: source, kind: .unsigned, name: preview.displayName, version: preview.version,
                                           bundleID: preview.bundleIdentifier, build: preview.build, provenance: .fileImport)
            }
            let owned = try storage.pendingURL(pending.id)
            return (pending, try IPAInspector.inspect(url: owned))
        }.value
    }
    @discardableResult func importPicked(_ file: URL) async throws -> LibrarySaveResult {
        saveState = .saving; operations += 1; busy = true
        defer { operations -= 1; busy = operations > 0 }
        do {
            let (pending, _) = try await preparePicked(file)
            discardPickerCopy(file) // Only after the durable copy and its record exist.
            let result = try await finishPending(pending.id)
            announce(result.alreadySaved ? "Already saved: \(result.entry.name)" : "Added \(result.entry.name)")
            return result
        } catch {
            if error is ShelfSaveFailure { throw error }
            let failure = ShelfSaveFailure(reason: error.localizedDescription, artifact: file, pendingID: nil)
            saveState = .failed(failure); message = failure.localizedDescription
            await refresh(recover: false); throw failure
        }
    }
    @discardableResult func retryImport(_ id: UUID) async throws -> LibrarySaveResult {
        let result = try await finishPending(id)
        announce(result.alreadySaved ? "Already saved: \(result.entry.name)" : "Added \(result.entry.name)")
        return result
    }
    @discardableResult func fileNow(_ file: URL, info: IPAMetadata, signed: Bool = false,
                                    provenance: LibraryEntry.Provenance? = nil) async throws -> LibrarySaveResult {
        saveState = .saving; operations += 1; busy = true
        defer { operations -= 1; busy = operations > 0 }
        let storage = storage
        do {
            let pending = try await Task.detached {
                try storage.prepare(file: file, kind: signed ? .signed : .unsigned, name: info.displayName, version: info.version,
                                    bundleID: info.bundleIdentifier, build: info.build, provenance: provenance)
            }.value
            return try await finishPending(pending.id)
        } catch {
            if error is ShelfSaveFailure { throw error }
            let failure = ShelfSaveFailure(reason: error.localizedDescription, artifact: file, pendingID: nil)
            saveState = .failed(failure); message = failure.localizedDescription
            await refresh(recover: false); throw failure
        }
    }
    @discardableResult func finishPending(_ id: UUID) async throws -> LibrarySaveResult {
        saveState = .saving; operations += 1; busy = true
        defer { operations -= 1; busy = operations > 0 }
        let storage = storage
        do {
            let result = try await Task.detached {
                let pending: LibraryPending
                do { pending = try storage.pendingRecord(id) }
                catch { return try storage.commit(id) }
                let file = try storage.pendingURL(id)
                let info = try IPAInspector.inspect(url: file)
                _ = try storage.complete(id, name: info.displayName.isEmpty ? info.bundleIdentifier : info.displayName, version: info.version,
                                         bundleID: info.bundleIdentifier, build: info.build, provenance: pending.provenance)
                return try storage.commit(id)
            }.value
            saveState = .saved(result); message = result.warning
            await refresh(recover: false)
            return result
        } catch {
            let artifact = await Task.detached {
                if let kept = try? storage.pendingURL(id) { return kept }
                if let entry = (storage.entries(.unsigned) + storage.entries(.signed)).first(where: { $0.id == id }) { return storage.url(for: entry) }
                if let recovered = storage.recoveryItems().first(where: { $0.pendingID == id || $0.url.lastPathComponent == "\(id.uuidString).ipa" }) { return recovered.url }
                return storage.root.appendingPathComponent("pending/\(id.uuidString)/artifact.ipa")
            }.value
            let failure = ShelfSaveFailure(reason: error.localizedDescription, artifact: artifact, pendingID: id)
            saveState = .failed(failure); message = failure.localizedDescription
            await refresh(recover: false); throw failure
        }
    }
    @discardableResult func retry(_ item: LibraryRecoveryItem) async throws -> LibrarySaveResult {
        if let id = item.pendingID { return try await finishPending(id) }
        saveState = .saving; operations += 1; busy = true
        defer { operations -= 1; busy = operations > 0 }
        let file = item.url
        let storage = storage
        do {
            let info = try await Task.detached { try IPAInspector.inspect(url: file) }.value
            if let adopted = try await Task.detached(operation: {
                try storage.adoptOrphan(file, name: info.displayName, version: info.version, bundleID: info.bundleIdentifier, build: info.build)
            }).value {
                saveState = .saved(adopted); await refresh(recover: false); return adopted
            }
            let saved = try await fileNow(file, info: info, provenance: .recoveredUnknown)
            do { try await Task.detached { try storage.removeIncoming(file) }.value }
            catch { message = "Saved, but the retained original needs cleanup: " + error.localizedDescription }
            return saved
        } catch {
            let failure = (error as? ShelfSaveFailure) ?? ShelfSaveFailure(reason: error.localizedDescription, artifact: file, pendingID: nil)
            saveState = .failed(failure); message = failure.localizedDescription; throw failure
        }
    }
    func remove(_ entry: LibraryEntry) async {
        let storage = storage
        do { try await Task.detached { try storage.remove(entry) }.value; message = nil }
        catch { message = error.localizedDescription; announce(error.localizedDescription) }
        await refresh(recover: false)
    }
    func clear(_ kind: LibraryEntry.Kind) async {
        let storage = storage
        do { try await Task.detached { try storage.clear(kind) }.value; message = nil }
        catch { message = error.localizedDescription; announce(error.localizedDescription) }
        await refresh(recover: false)
    }
    func repairIndex() async {
        let storage = storage
        do { try await Task.detached { try storage.repairIndex() }.value; message = nil; await refresh() }
        catch { message = error.localizedDescription; announce(error.localizedDescription) }
    }
}
