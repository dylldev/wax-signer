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
    @Published private(set) var downloads: [String: Double] = [:]      // app id to 0...1
    @Published private(set) var filed: Set<String> = []                // app ids already on the shelf this session
    @Published var message: String?

    private let store: SourceStore
    private var repos: [UUID: SourceRepo] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SourceStore(directory: support.appendingPathComponent("Sources", isDirectory: true))
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
    func get(_ app: SourceApp, from sourceID: UUID?, signAfter: Bool, library: LibraryModel, signing: SigningModel, router: Router) {
        guard downloads[app.id] == nil else { return }
        downloads[app.id] = 0
        message = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()   // the tap on Get, so the download feels answered
        BackgroundJob.shared.begin(title: app.name)
        let downloader = IPADownloader()
        let store = store
        Task {
            var ok = false
            defer { BackgroundJob.shared.end(success: ok); downloads[app.id] = nil }
            do {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Downloads", isDirectory: true)
                let file = try await downloader.download(app, to: temp, refetch: {
                    // An expired link: ask the source again and use its fresh link for this same app.
                    guard let id = sourceID else { throw DownloadError.linkExpired }
                    let repo = try await store.refresh(id)
                    guard let fresh = repo.apps.first(where: { $0.bundleID == app.bundleID }) else { throw DownloadError.linkExpired }
                    return fresh
                }, progress: { p in
                    Task { @MainActor in
                        self.downloads[app.id] = p
                        BackgroundJob.shared.update(fraction: p, subtitle: "Downloading")
                    }
                })
                defer { try? FileManager.default.removeItem(at: file) }
                let info = try await Task.detached { try IPAInspector.inspect(url: file) }.value
                // A downloaded app is something to re-sign, so it goes on the Unsigned shelf even when the file
                // carries the publisher's own signature (which will not install on this phone).
                let entry = await library.fileNow(file, info: info, signed: false)
                filed.insert(app.id)
                ok = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AccessibilityNotification.Announcement("\(app.name) downloaded").post()
                if signAfter, let entry { signing.use(entry); router.tab = .sign }
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ImportLogs.shared.log("sources: get failed \(ImportLog.describe(error))")
            }
        }
    }
}
