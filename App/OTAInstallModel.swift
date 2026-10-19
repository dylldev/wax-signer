import Foundation
import InstallKit

/// Serial ownership of installation preparation, publication and local delivery.
/// Settings apply to the next reservation; an active session keeps its immutable configuration.
@MainActor
final class OTAInstallModel: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case uploading(Double)
        case handedToiOS
        case failed(String)
    }

    @Published var serverText: String = UserDefaults.standard.string(forKey: "otaServer") ?? "" {
        didSet { UserDefaults.standard.set(serverText, forKey: "otaServer") }
    }
    @Published private(set) var hasToken: Bool
    @Published private(set) var state: State = .idle
    @Published var tokenDraft = ""
    /// Result of asking the server whether it accepts the saved token ("checking…", "accepted", or the reason it did not).
    @Published private(set) var tokenNote: String?

    enum HostKind: String, CaseIterable {
        case phone, server, bucket

        /// The name shown in the picker and in one-line summaries. Kept here so a new host cannot be added with a
        /// name in one place and a different name, or none, in the other.
        var label: String {
            switch self {
            case .phone: return "This iPhone"
            case .server: return "My server"
            case .bucket: return "Bucket"
            }
        }
    }

    /// Where signed apps go: the owner's own server, or a storage bucket.
    /// New installs serve from this phone; someone who already set up a server keeps using it.
    @Published var hostKind: HostKind = HostKind(rawValue: UserDefaults.standard.string(forKey: "installHost") ?? "")
        ?? ((UserDefaults.standard.string(forKey: "otaServer") ?? "").isEmpty ? .phone : .server) {
        didSet { UserDefaults.standard.set(hostKind.rawValue, forKey: "installHost") }
    }
    @Published var bucketEndpoint = UserDefaults.standard.string(forKey: "s3Endpoint") ?? "" {
        didSet { UserDefaults.standard.set(bucketEndpoint, forKey: "s3Endpoint") }
    }
    @Published var bucketName = UserDefaults.standard.string(forKey: "s3Bucket") ?? "" {
        didSet { UserDefaults.standard.set(bucketName, forKey: "s3Bucket") }
    }
    @Published var bucketRegion = UserDefaults.standard.string(forKey: "s3Region") ?? "auto" {
        didSet { UserDefaults.standard.set(bucketRegion, forKey: "s3Region") }
    }
    /// Where the certificate for the "This iPhone" host is published.
    @Published var certificateFeedText = UserDefaults.standard.string(forKey: "certificateFeed") ?? LoopbackConfig.defaultFeed {
        didSet { UserDefaults.standard.set(certificateFeedText, forKey: "certificateFeed") }
    }
    @Published var accessKeyDraft = ""
    @Published var secretKeyDraft = ""
    @Published private(set) var hasBucketKeys: Bool
    @Published private(set) var bucketNote: String?

    private let store: SecretStore
    private let bucketStore: SecretStore
    /// A reservation covers signing as well as upload, so a probe cannot replace a real installation.
    final class Session {
        let id = UUID()
        let kind: HostKind
        fileprivate let configuration: Configuration
        fileprivate var host: PreparedHost?
        fileprivate var uploadTask: Task<URL?, Never>?
        fileprivate var deliveryTask: Task<Bool, Never>?
        fileprivate var uploadStarted = false
        fileprivate var deliveryFinished = false
        fileprivate init(_ configuration: Configuration) {
            self.configuration = configuration
            switch configuration { case .phone: kind = .phone; case .server: kind = .server; case .bucket: kind = .bucket }
        }
    }
    fileprivate enum Configuration {
        case phone(URL)
        case server(OTAEndpoint, String)
        case bucket(S3Credentials, String)
    }
    /// Small host-lifecycle seam; production uses the same LoopbackHost/OTAUploader/S3Host implementations.
    struct PreparedHost {
        let publisher: any InstallHost
        var stop: () -> Void = {}
        var wait: (TimeInterval) async -> Bool = { _ in true }
        var served: () -> Bool = { false }
    }
    struct SessionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    @Published private(set) var activeSession: Session?
    private let preparePhone: (URL) async throws -> PreparedHost
    private let prepareServer: (OTAEndpoint, String) async throws -> PreparedHost
    private var tokenCheck: Task<Void, Never>?
    private var tokenCheckID = UUID()
    private var bucketCheck: Task<Void, Never>?
    private var bucketCheckID = UUID()
    private let bucketHost: (S3Credentials, String) throws -> S3Host
    private let cleanupStore: BucketCleanupStore
    private let cleanup: @Sendable (S3Credentials, String, String) async throws -> Void
    private let defaults: UserDefaults
    private var activeBucketRecords = Set<UUID>()

    /// The Keychain service name for cloud bucket keys. DO NOT RENAME: Wax has shipped under this string, and
    /// changing it would orphan the keys already stored on people's phones.
    static let bucketKeysService = "dev.localsigner.wax.bucket-keys"

    init(store: SecretStore = KeychainSecretStore(), bucketStore: SecretStore = KeychainSecretStore(service: OTAInstallModel.bucketKeysService),
         cleanupStore: BucketCleanupStore? = nil, defaults: UserDefaults = .standard, sweepOnStart: Bool = true,
         preparePhone: ((URL) async throws -> PreparedHost)? = nil,
         prepareServer: ((OTAEndpoint, String) async throws -> PreparedHost)? = nil,
         bucketHost: @escaping (S3Credentials, String) throws -> S3Host = { try S3Host(credentials: $0, bucket: $1) },
         cleanup: @escaping @Sendable (S3Credentials, String, String) async throws -> Void = { credentials, bucket, id in
             try await S3Host(credentials: credentials, bucket: bucket, id: id).cleanupConfirmed()
         }) {
        self.preparePhone = preparePhone ?? { feed in
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Install")
            let bundle = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, allowedNames: LoopbackConfig.allowedNames(for: feed))
            try Task.checkCancellation()
            let host = try LoopbackHost(p12: bundle.p12Data, password: bundle.password, host: bundle.name)
            return PreparedHost(publisher: host, stop: { host.stop() }, wait: { timeout in
                let delivered = await host.waitForTransfer(timeout: timeout)
                if delivered { do { try await Task.sleep(for: .seconds(3)) } catch { return false } }
                return delivered
            }, served: { host.servedIPA })
        }
        self.prepareServer = prepareServer ?? { endpoint, token in PreparedHost(publisher: OTAUploader(endpoint: endpoint, token: token)) }
        self.store = store
        self.bucketStore = bucketStore
        self.defaults = defaults; self.cleanup = cleanup; self.bucketHost = bucketHost
        self.cleanupStore = cleanupStore ?? BucketCleanupStore(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Install/bucket-cleanup-v1.json"))
        hasToken = store.load() != nil
        hasBucketKeys = bucketStore.load() != nil
        if sweepOnStart { Task { await sweepBucket() } }
    }

    /// The saved setup is complete for the chosen host.
    var isConfigured: Bool {
        switch hostKind {
        case .phone: return LoopbackConfig.isUsableFeed(certificateFeedText)
        case .server: return hasToken && (try? OTAEndpoint(serverText)) != nil
        case .bucket: return hasBucketKeys && bucketCredentials() != nil
        }
    }

    /// Short name of the chosen host for one-line summaries.
    var hostSummary: String {
        switch hostKind {
        case .phone: return hostKind.label
        case .server: return (try? OTAEndpoint(serverText))?.base.host ?? serverText
        case .bucket: return bucketName
        }
    }

    /// Configured and not already uploading.
    var canInstall: Bool {
        activeSession == nil && isConfigured
    }

    func saveToken() {
        let t = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= OTASetup.minimumTokenLength else { tokenNote = "That token is too short (it needs 32 or more characters)."; return }
        do { try store.save(Data(t.utf8)); hasToken = true; tokenDraft = ""; checkTokenWithServer() }
        catch { tokenNote = "Could not store the token. Retry in Settings." }
    }

    /// Applies a `WAXINSTALL1 <server> <token>` line (one paste sets up a new copy of Wax).
    func applySetup(_ text: String) {
        do {
            let p = try OTASetup.parse(text)
            try store.save(Data(p.token.utf8))
            serverText = p.server
            hasToken = true
            ImportLogs.shared.log("ota: setup pasted")
            checkTokenWithServer()
        } catch {
            tokenNote = "Could not read the setup line. Check its format and retry."
        }
    }

    /// Asks the server to confirm the token right after it is saved, so a wrong one is found now and not after signing.
    func checkTokenWithServer() {
        guard let endpoint = try? OTAEndpoint(serverText), let raw = store.load(), let token = String(data: raw, encoding: .utf8) else { return }
        tokenCheck?.cancel()
        let generation = UUID(); tokenCheckID = generation
        tokenNote = "Checking with the server…"
        tokenCheck = Task {
            do {
                try await OTAUploader(endpoint: endpoint, token: token).checkToken()
                guard !Task.isCancelled, tokenCheckID == generation, (try? OTAEndpoint(serverText))?.base == endpoint.base,
                      store.load() == raw else { return }
                tokenNote = "The server accepted the token."
            } catch {
                guard !Task.isCancelled, tokenCheckID == generation,
                      (try? OTAEndpoint(serverText))?.base == endpoint.base, store.load() == raw else { return }
                tokenNote = "The server did not accept the token. Check the address and token, then retry."
            }
        }
    }

    func saveBucketKeys() {
        let a = accessKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), k = secretKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !k.isEmpty, let blob = try? JSONEncoder().encode(["a": a, "s": k]) else { return }
        do { try bucketStore.save(blob); hasBucketKeys = true; accessKeyDraft = ""; secretKeyDraft = "" }
        catch { bucketNote = (error as? LocalizedError)?.errorDescription ?? "Could not store the keys." }
    }

    func forgetBucketKeys() { bucketStore.delete(); hasBucketKeys = false }

    private func bucketCredentials() -> (S3Credentials, String)? {
        let text = bucketEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = bucketRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = try? OTAEndpoint(text), !name.isEmpty, !region.isEmpty,
              let raw = bucketStore.load(), let keys = try? JSONDecoder().decode([String: String].self, from: raw),
              let a = keys["a"], let s = keys["s"] else { return nil }
        return (S3Credentials(accessKey: a, secretKey: s, region: region, endpoint: endpoint.base), name)
    }

    func testBucket() {
        guard let (c, name) = bucketCredentials() else { bucketNote = "Fill in the endpoint, bucket, region and both keys first."; return }
        bucketCheck?.cancel()
        let generation = UUID(); bucketCheckID = generation
        let scope = try? BucketCleanupScope(credentials: c, bucket: name)
        bucketNote = "Checking the bucket…"
        bucketCheck = Task {
            let note: String
            do { try await S3Host(credentials: c, bucket: name).checkAccess(); note = "The bucket accepted the keys." }
            catch { note = "The bucket check failed. Check the endpoint, bucket, region and keys, then retry." }
            guard !Task.isCancelled, bucketCheckID == generation, let (current, currentName) = bucketCredentials(),
                  (try? BucketCleanupScope(credentials: current, bucket: currentName)) == scope,
                  current.secretKey == c.secretKey else { return }
            bucketNote = note
        }
    }

    func retryBucketCleanup() { Task { await sweepBucket() } }

    /// Legacy records lack their destination: preserve them, never guess the current host for deletion.
    private func sweepBucket() async {
        guard let (credentials, bucket) = bucketCredentials() else { return }
        await sweepBucket(credentials: credentials, bucket: bucket)
    }

    func sweepBucket(credentials: S3Credentials, bucket: String, now: Date = Date()) async {
        do {
            let scope = try BucketCleanupScope(credentials: credentials, bucket: bucket)
            let store = cleanupStore
            let records = try await Task.detached { try store.records() }.value
            bucketNote = "Checking expired bucket uploads…"
            let unresolvedLegacy = defaults.dictionary(forKey: "s3Pending")?.count ?? 0
            if unresolvedLegacy > 0 { bucketNote = "\(unresolvedLegacy) older cleanup records have no destination. They are preserved; use your bucket's expiry rule or remove the old objects in its console." }
            for record in records where record.scope == scope && (record.expiresAt == nil || record.expiresAt! <= now) {
                guard activeBucketRecords.insert(record.id).inserted else { continue }
                defer { activeBucketRecords.remove(record.id) }
                do {
                    try await cleanup(credentials, bucket, record.sessionID)
                    try await Task.detached { try store.remove(record) }.value
                } catch { bucketNote = "Bucket cleanup could not finish. Its record is kept; check access and retry on the next upload or launch." }
            }
            if bucketNote == "Checking expired bucket uploads…" { bucketNote = "Expired bucket cleanup finished; unexpired links are kept." }
            if records.contains(where: { $0.scope != scope }) {
                bucketNote = "Cleanup records for another bucket or access key are preserved. Restore that configuration to retry, or use the original bucket's expiry rule."
            }
        } catch { bucketNote = "Bucket cleanup records could not be read. They were preserved; new uploads must wait for storage recovery." }
    }

    /// Admission and configuration capture happen synchronously, before signing/feed/network awaits.
    func reserve() throws -> Session {
        guard activeSession == nil else { throw SessionError(message: "Another installation or identity test is active. Finish or cancel it first.") }
        let configuration: Configuration
        switch hostKind {
        case .phone:
            guard LoopbackConfig.isUsableFeed(certificateFeedText), let feed = URL(string: certificateFeedText) else {
                throw SessionError(message: "Set a valid HTTPS certificate feed in Install settings, or choose My server or Bucket.")
            }
            configuration = .phone(feed)
        case .server:
            guard let endpoint = try? OTAEndpoint(serverText), let raw = store.load(), let token = String(data: raw, encoding: .utf8) else {
                throw SessionError(message: "Set the install server address and token first.")
            }
            configuration = .server(endpoint, token)
        case .bucket:
            guard let (credentials, name) = bucketCredentials() else { throw SessionError(message: "Set up the bucket first (endpoint, name, region and keys).") }
            configuration = .bucket(credentials, name)
        }
        let session = Session(configuration)
        activeSession = session; state = .preparing
        return session
    }

    func owns(_ session: Session) -> Bool { activeSession === session }

    /// Invalidate ownership first. A late readiness/progress/completion can only dispose its own host.
    func release(_ session: Session) {
        guard owns(session) else { return }
        activeSession = nil
        switch state { case .preparing, .uploading: state = .idle; default: break }
        session.uploadTask?.cancel(); session.deliveryTask?.cancel()
        session.host?.stop(); session.host = nil
    }

    func cancel(_ session: Session) {
        guard owns(session) else { return }
        release(session)
        state = .failed("Installation canceled. Signed and saved IPA files are kept; retry or export them.")
    }
    func fail(_ session: Session, reason: String) {
        guard owns(session) else { return }
        release(session); state = .failed(reason)
    }
    func cancelActive() { if let session = activeSession { cancel(session) } }
    func reset() { if let session = activeSession { release(session) }; state = .idle }
    func forgetToken() { tokenCheck?.cancel(); tokenCheckID = UUID(); store.delete(); hasToken = false; tokenNote = nil }

    /// Completion uses the original reservation/host, never the current Settings selection.
    func finishPhoneTransfer(session: Session, timeout: TimeInterval = 600, releaseWhenFinished: Bool = true) async -> Bool {
        guard owns(session), state == .handedToiOS, session.deliveryTask == nil, !session.deliveryFinished else { return false }
        guard session.kind == .phone else {
            session.deliveryFinished = true
            if releaseWhenFinished { release(session) }
            return true
        }
        guard let host = session.host else { return false }
        let task = Task { await host.wait(timeout) }
        session.deliveryTask = task
        let delivered = await withTaskCancellationHandler(operation: { await task.value }, onCancel: {
            task.cancel()
            Task { @MainActor [weak self] in self?.cancel(session) }
        })
        guard owns(session) else { return false }
        session.deliveryTask = nil; session.deliveryFinished = true
        if Task.isCancelled { cancel(session); return false }
        if !delivered { state = .failed(LoopbackHost.transferFailureMessage(served: host.served())) }
        host.stop(); session.host = nil
        if releaseWhenFinished || !delivered { release(session) }
        return delivered
    }

    /// Used for a preflight refusal only; it cannot overwrite another caller's active session.
    func block(_ reason: String) { if activeSession == nil { state = .failed(reason) } }

    /// The retained child owns publication; cancellation is forwarded despite unstructured Task boundaries.
    /// Legacy callers can omit a reservation, but all app flows reserve before doing other async work.
    func upload(ipa: URL, bundleIdentifier: String, version: String, build: String = "", title: String,
                session reserved: Session? = nil) async -> URL? {
        let session: Session
        do { session = try reserved ?? reserve() }
        catch { if activeSession == nil { state = .failed(error.localizedDescription) }; return nil }
        guard owns(session), !session.uploadStarted, !Task.isCancelled else { return nil }
        session.uploadStarted = true
        let task = Task { await publish(session, ipa: ipa, bundleIdentifier: bundleIdentifier, version: version, build: build, title: title) }
        session.uploadTask = task
        let link = await withTaskCancellationHandler(operation: { await task.value }, onCancel: {
            task.cancel()
            Task { @MainActor [weak self] in self?.cancel(session) }
        })
        if owns(session) {
            session.uploadTask = nil
            if Task.isCancelled { cancel(session); return nil }
        }
        return owns(session) ? link : nil
    }

    private func publish(_ session: Session, ipa: URL, bundleIdentifier: String, version: String, build: String, title: String) async -> URL? {
        var bucketRecord: BucketCleanupRecord?
        defer { if let record = bucketRecord { activeBucketRecords.remove(record.id) } }
        do {
            try Task.checkCancellation()
            let host: PreparedHost
            switch session.configuration {
            case .phone(let feed): host = try await preparePhone(feed)
            case .server(let endpoint, let token): host = try await prepareServer(endpoint, token)
            case .bucket(let credentials, let name):
                await sweepBucket(credentials: credentials, bucket: name)
                try Task.checkCancellation()
                guard owns(session) else { return nil }
                let s3 = try bucketHost(credentials, name)
                bucketRecord = try BucketCleanupRecord(sessionID: s3.id, scope: BucketCleanupScope(credentials: credentials, bucket: name))
                host = PreparedHost(publisher: s3)
            }
            guard owns(session), !Task.isCancelled else { host.stop(); return nil }
            session.host = host
            if let record = bucketRecord {
                activeBucketRecords.insert(record.id)
                let store = cleanupStore
                // Atomic ledger writes are allowed to settle even after cancellation; no link escapes without acknowledgment.
                try await Task.detached { try store.put(record) }.value
            }
            try Task.checkCancellation()
            guard owns(session) else { return nil }
            state = .uploading(0)
            let link = try await host.publisher.publish(ipa: ipa, bundleIdentifier: bundleIdentifier, version: version, build: build, title: title) { [weak self, weak session] fraction in
                Task { @MainActor in
                    guard let self, let session, self.owns(session), !Task.isCancelled, self.state != .handedToiOS else { return }
                    self.state = .uploading(min(1, max(0, fraction.isFinite ? fraction : 0)))
                }
            }
            try Task.checkCancellation()
            guard owns(session) else { return nil }
            if var record = bucketRecord {
                record.expiresAt = Date().addingTimeInterval(Double(S3Host.linkLifetime))
                let committed = record, store = cleanupStore
                do { try await Task.detached { try store.put(committed) }.value }
                catch { throw SessionError(message: "The IPA was uploaded, but Wax could not save its cleanup deadline. The installer was not opened. Free space and retry.") }
            }
            try Task.checkCancellation()
            guard owns(session) else { return nil }
            state = .handedToiOS
            return link
        } catch {
            guard owns(session) else { return nil }
            if Task.isCancelled || error is CancellationError { cancel(session) }
            else {
                let message = (error as? LocalizedError)?.errorDescription ?? "Installation preparation or upload failed. Retry with the retained IPA."
                state = .failed(session.kind == .phone ? "\(message) You can also use My server or Bucket under Install." : message)
                release(session)
            }
            return nil
        }
    }
}
