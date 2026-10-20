import Foundation
import InstallKit
import IPAKit
import SourcesKit
import SwiftUI
import UIKit

/// The Sources tab's state: the sources the user added, what is being downloaded, and what went wrong.
@MainActor
final class SourcesModel: ObservableObject {
    @Published private(set) var sources: [SavedSource] = []
    @Published private(set) var loading: Set<UUID> = []
    private struct DownloadKey: Hashable, Sendable {
        let source: UUID?
        let appID: String
        let bundleID: String
        let version: String
        let address: String
        let size: Int?
        let date: Date?
    }
    @Published private var downloads: [DownloadKey: Double] = [:]
    @Published private var filed: [DownloadKey: UUID] = [:]
    @Published var message: String?
    @Published private var retainedDownloads: [DownloadKey: URL] = [:]
    @Published private var savingDownloads: Set<DownloadKey> = []
    private var retainedPending: [DownloadKey: UUID] = [:]
    private func key(_ app: SourceApp, _ source: UUID?) -> DownloadKey {
        DownloadKey(source: source, appID: app.id, bundleID: app.bundleID, version: app.version,
                    address: app.downloadURL.absoluteString, size: app.size, date: app.date)
    }
    func progress(_ app: SourceApp, source: UUID?) -> Double? { downloads[key(app, source)] }
    func isSaving(_ app: SourceApp, source: UUID?) -> Bool { savingDownloads.contains(key(app, source)) }
    func retainedFile(_ app: SourceApp, source: UUID?) -> URL? { retainedDownloads[key(app, source)] }
    func isFiled(_ app: SourceApp, source: UUID?, library: LibraryModel) -> Bool {
        guard let id = filed[key(app, source)] else { return false }
        return (library.unsigned + library.signed).contains { $0.id == id }
    }
    private let downloadOverride: ((SourceApp, URL) async throws -> URL)?
    private let announce: (String) -> Void

    private let store: SourceStore
    private var repos: [UUID: SourceRepo] = [:]

    init(sourceStore: SourceStore? = nil, download: ((SourceApp, URL) async throws -> URL)? = nil,
         announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }) {
        downloadOverride = download; self.announce = announce
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = sourceStore ?? SourceStore(directory: support.appendingPathComponent("Sources", isDirectory: true))
        sources = store.sources
    }

    /// Apps of one source from the on-disk copy (parsed once, kept in memory).
    func apps(of id: UUID) -> [SourceApp] {
        if let r = repos[id] { return r.apps }
        let r = store.cached(id)
        if let r { repos[id] = r }
        return r?.apps ?? []
    }

    /// Adds a source address, or downloads a pasted direct link to one IPA.
    func add(_ text: String, signAfter: Bool, library: LibraryModel, signing: SigningModel, router: Router) {
        message = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else {
            message = SourceStoreError.notHTTPS.localizedDescription; return
        }
        if url.pathExtension.lowercased() == "ipa" {
            let stem = url.deletingPathExtension().lastPathComponent
            let app = SourceApp(id: "direct@\(trimmed)", name: stem.isEmpty ? "App" : stem, bundleID: "", version: "", size: nil,
                                iconURL: nil, downloadURL: url, date: nil, summary: "", developer: "")
            get(app, from: nil, signAfter: signAfter, library: library, signing: signing, router: router)
            return
        }
        guard !sources.contains(where: { $0.url == url }) else { message = "That source is already added."; return }
        Task {
            do {
                try await store.add(url: url)
                sources = store.sources
            } catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }

    func refresh(_ id: UUID) {
        loading.insert(id)
        Task {
            defer { loading.remove(id) }
            do {
                repos[id] = try await store.refresh(id)
                sources = store.sources
            } catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }

    /// Pull to refresh on the Sources list: asks every added source again and waits for all of them.
    func refreshAll() async {
        let ids = sources.map(\.id)
        guard !ids.isEmpty else { return }
        message = nil
        loading.formUnion(ids)
        defer { loading.subtract(ids) }
        var problems: [String] = []
        for id in ids {
            do { repos[id] = try await store.refresh(id) }
            catch {
                problems.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ImportLogs.shared.log("sources: refresh failed \(ImportLog.describe(error))")
            }
        }
        sources = store.sources
        message = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    func remove(_ id: UUID) {
        do { try store.remove(id); repos[id] = nil; sources = store.sources }
        catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    /// Downloads an app onto the Unsigned shelf; optionally opens it on the Sign tab afterwards.
    @discardableResult func get(_ app: SourceApp, from sourceID: UUID?, signAfter: Bool, library: LibraryModel, signing: SigningModel, router: Router) -> Task<Void, Never>? {
        let key = self.key(app, sourceID)
        guard downloads[key] == nil else { return nil }
        downloads[key] = 0
        message = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()   // the tap on Get, so the download feels answered
        let backgroundID = BackgroundJob.shared.begin(title: app.name)
        let downloader = IPADownloader()
        let store = store
        return Task {
            var ok = false
            defer { BackgroundJob.shared.end(backgroundID, success: ok); downloads[key] = nil; savingDownloads.remove(key) }
            do {
                let storage = library.storage
                let file: URL
                if let kept = retainedDownloads[key] { file = kept }
                else {
                    let temp = try await Task.detached { try storage.incomingDirectory() }.value
                    if let downloadOverride { file = try await downloadOverride(app, temp) }
                    else { file = try await downloader.download(app, to: temp, refetch: {
                    // An expired link: ask the source again and use its fresh link for this same app.
                    guard let id = sourceID else { throw DownloadError.linkExpired }
                    let repo = try await store.refresh(id)
                    guard let fresh = repo.apps.first(where: { $0.bundleID == app.bundleID }) else { throw DownloadError.linkExpired }
                    return fresh
                }, progress: { p in
                    Task { @MainActor in
                        guard self.downloads[key] != nil, !self.savingDownloads.contains(key) else { return }
                        self.downloads[key] = p
                        BackgroundJob.shared.update(backgroundID, fraction: p, subtitle: "Downloading")
                    }
                }) }
                }
                savingDownloads.insert(key)
                retainedDownloads[key] = file
                let saved: LibrarySaveResult
                if let pending = retainedPending[key] { saved = try await library.finishPending(pending) }
                else {
                    let info = try await Task.detached { try IPAInspector.inspect(url: file) }.value
                    // A publisher signature marker does not make this a Wax-generated signing result.
                    saved = try await library.fileNow(file, info: info, signed: false, provenance: .sourceDownload)
                }
                filed[key] = saved.entry.id
                ok = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let savedTitle = saved.entry.name.isEmpty ? app.name : saved.entry.name
                announce(saved.alreadySaved ? "\(savedTitle) already saved" : "\(savedTitle) downloaded and saved")
                retainedDownloads[key] = nil; retainedPending[key] = nil
                do { try await Task.detached { try storage.removeIncoming(file) }.value }
                catch { message = "Saved, but the retained download needs cleanup: " + error.localizedDescription }
                await library.refresh(recover: false)
                if signAfter { signing.use(saved.entry); router.tab = .sign }
            } catch {
                if let pending = (error as? ShelfSaveFailure)?.pendingID { retainedPending[key] = pending }
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ImportLogs.shared.log("sources: get failed \(ImportLog.describe(error))")
            }
        }
    }
}
