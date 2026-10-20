import Foundation

public struct SavedSource: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var name: String
    public var updated: Date?
    public var appCount: Int
}

public enum SourceStoreError: Error, LocalizedError, Equatable {
    case notHTTPS, http(Int), tooLarge, unreachable(String), refreshSuperseded
    public var errorDescription: String? {
        switch self {
        case .refreshSuperseded: "This source changed or was removed during refresh. Refresh the current source again."
        case .notHTTPS: "A source address must start with https://."
        case .http(let c): "The source server answered with an error (HTTP \(c))."
        case .tooLarge: "That source file is too large to load."
        case .unreachable(let why): "Could not reach that source: \(why)"
        }
    }
}

/// The sources a user added, with an on-disk copy of each so the list opens instantly and offline.
/// Nothing is built in: this starts empty.
public final class SourceStore: @unchecked Sendable {
    private let directory: URL
    private let session: URLSession
    private let lock = NSLock()
    private var saved: [SavedSource]
    private var refreshing: [UUID: UUID] = [:]

    static let maxBytes = 64 * 1024 * 1024
    private var indexURL: URL { directory.appendingPathComponent("sources.json") }
    private func cacheURL(_ id: UUID) -> URL { directory.appendingPathComponent("cache-\(id.uuidString).json") }
    private func etagURL(_ id: UUID) -> URL { directory.appendingPathComponent("cache-\(id.uuidString).etag") }

    public init(directory: URL, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
        let data = try? Data(contentsOf: directory.appendingPathComponent("sources.json"))
        saved = data.flatMap { try? JSONDecoder().decode([SavedSource].self, from: $0) } ?? []
    }

    public var sources: [SavedSource] { lock.withLock { saved } }

    public func cached(_ id: UUID) -> SourceRepo? {
        lock.withLock { cachedLocked(id) }
    }

    private func cachedLocked(_ id: UUID) -> SourceRepo? {
        (try? Data(contentsOf: cacheURL(id))).flatMap { try? JSONDecoder().decode(SourceRepo.self, from: $0) }
    }

    @discardableResult
    public func add(url: URL) async throws -> SourceRepo {
        guard url.scheme == "https", url.host != nil else { throw SourceStoreError.notHTTPS }
        if let existing = sources.first(where: { $0.url == url }) { return try await refresh(existing.id) }
        let (repo, etag) = try await fetch(url, etag: nil)
        let source = SavedSource(id: UUID(), url: url, name: repo.name, updated: Date(), appCount: repo.apps.count)
        try write(repo: repo, etag: etag, for: source.id)
        do {
            let inserted = try lock.withLock { () throws -> Bool in
                guard !saved.contains(where: { $0.url == url }) else { return false }
                let before = saved
                saved.append(source)
                do { try saveIndexLocked() } catch { saved = before; throw error }
                return true
            }
            if !inserted { removeCache(for: source.id) }
        } catch {
            removeCache(for: source.id)
            throw error
        }
        return repo
    }

    public func remove(_ id: UUID) throws {
        try lock.withLock {
            let before = saved
            saved.removeAll { $0.id == id }
            do { try saveIndexLocked() }
            catch { saved = before; throw error }
            refreshing[id] = nil
            removeCache(for: id)
        }
    }

    @discardableResult
    public func refresh(_ id: UUID) async throws -> SourceRepo {
        let refresh = try beginRefresh(id)
        let (repo, newTag) = try await fetch(refresh.source.url, etag: refresh.etag, fallback: refresh.known)
        return try finishRefresh(refresh, repo: repo, etag: newTag)
    }

    // Split around the await so tests can deterministically reorder/remove refreshes.
    struct Refresh {
        let source: SavedSource
        let known: SourceRepo?
        let etag: String?
        let token: UUID
    }
    func beginRefresh(_ id: UUID) throws -> Refresh {
        try lock.withLock {
            guard let source = saved.first(where: { $0.id == id }) else { throw SourceStoreError.refreshSuperseded }
            let known = cachedLocked(id), token = UUID()
            let tag = known == nil ? nil : (try? String(contentsOf: etagURL(id), encoding: .utf8))
            refreshing[id] = token
            return Refresh(source: source, known: known, etag: tag, token: token)
        }
    }
    func finishRefresh(_ refresh: Refresh, repo: SourceRepo, etag: String?) throws -> SourceRepo {
        try lock.withLock {
            let id = refresh.source.id
            guard refreshing[id] == refresh.token, let i = saved.firstIndex(where: { $0.id == id && $0.url == refresh.source.url }) else {
                throw SourceStoreError.refreshSuperseded
            }
            // Cache + ETag + metadata commit serialize with snapshots/removal. Invalidating the old
            // ETag first makes interruption a safe unconditional re-fetch, never stale-cache 304 reuse.
            try write(repo: repo, etag: etag, for: id)
            let before = saved
            saved[i].name = repo.name; saved[i].appCount = repo.apps.count; saved[i].updated = Date()
            do { try saveIndexLocked() } catch { saved = before; throw error }
            refreshing[id] = nil
            return repo
        }
    }

    // MARK: Network

    private func fetch(_ url: URL, etag: String?, fallback: SourceRepo? = nil) async throws -> (SourceRepo, String?) {
        var request = URLRequest(url: url); request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, fallback != nil { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        // To a file, not memory: a hostile source cannot fill RAM before the size check.
        let file: URL, response: URLResponse
        do { (file, response) = try await session.download(for: request) }
        catch { throw SourceStoreError.unreachable(error.localizedDescription) }
        defer { try? FileManager.default.removeItem(at: file) }
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 304, let fallback { return (fallback, etag) }
        guard (200..<300).contains(code) else { throw SourceStoreError.http(code) }
        guard try Self.measuredSize(of: file) <= Self.maxBytes else { throw SourceStoreError.tooLarge }
        let repo = try SourceParser.parse(try Data(contentsOf: file, options: .mappedIfSafe))      // throws before anything is written
        return (repo, http?.value(forHTTPHeaderField: "ETag"))
    }

    /// The size probe must fail loudly. Treating a failed probe as zero bytes would wave a hostile source of any
    /// size past the cap, which is the whole point of downloading to a file instead of memory.
    static func measuredSize(of file: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = (attrs[.size] as? NSNumber)?.intValue else {
            throw SourceStoreError.unreachable("The source file could not be measured.")
        }
        return size
    }

    // MARK: Disk

    private func write(repo: SourceRepo, etag: String?, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Remove the prior validator before replacing its content; no failure can pair old ETag/new bytes.
        let validator = etagURL(id)
        if FileManager.default.fileExists(atPath: validator.path) { try FileManager.default.removeItem(at: validator) }
        try JSONEncoder().encode(repo).write(to: cacheURL(id), options: .atomic)
        if let etag { try Data(etag.utf8).write(to: etagURL(id), options: .atomic) }
    }

    private func saveIndex() throws {
        try lock.withLock { try saveIndexLocked() }
    }

    private func saveIndexLocked() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: indexURL, options: .atomic)
    }

    private func removeCache(for id: UUID) {
        for url in [cacheURL(id), etagURL(id)] { try? FileManager.default.removeItem(at: url) }
    }
}
