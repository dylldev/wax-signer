import Foundation
import InstallKit

/// Uploads a signed IPA to the owner's own HTTPS server and asks iOS to install it from there.
/// iOS refuses to install from a server on the same phone, so the server has to be another host.
@MainActor
final class OTAInstallModel: ObservableObject {
    enum State: Equatable {
        case idle
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
    private var phoneHost: LoopbackHost?
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
         bucketHost: @escaping (S3Credentials, String) throws -> S3Host = { try S3Host(credentials: $0, bucket: $1) },
         cleanup: @escaping @Sendable (S3Credentials, String, String) async throws -> Void = { credentials, bucket, id in
             try await S3Host(credentials: credentials, bucket: bucket, id: id).cleanupConfirmed()
         }) {
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
        if case .uploading = state { return false }
        return isConfigured
    }

    func saveToken() {
        let t = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= OTASetup.minimumTokenLength else { state = .failed("That token is too short (it needs 32 or more characters)."); return }
        do { try store.save(Data(t.utf8)); hasToken = true; tokenDraft = ""; state = .idle; checkTokenWithServer() }
        catch { state = .failed((error as? LocalizedError)?.errorDescription ?? "Could not store the token.") }
    }

    /// Applies a `WAXINSTALL1 <server> <token>` line (one paste sets up a new copy of Wax).
    func applySetup(_ text: String) {
        do {
            let p = try OTASetup.parse(text)
            try store.save(Data(p.token.utf8))
            serverText = p.server
            hasToken = true
            state = .idle
            ImportLogs.shared.log("ota: setup pasted")
            checkTokenWithServer()
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Could not read the setup line.")
        }
    }

    /// Asks the server to confirm the token right after it is saved, so a wrong one is found now and not after signing.
    func checkTokenWithServer() {
        guard let endpoint = try? OTAEndpoint(serverText), let raw = store.load(), let token = String(data: raw, encoding: .utf8) else { return }
        tokenNote = "Checking with the server…"
        Task {
            do {
                try await OTAUploader(endpoint: endpoint, token: token).checkToken()
                tokenNote = "The server accepted the token."
            } catch {
                tokenNote = nil
                state = .failed((error as? LocalizedError)?.errorDescription ?? "The server did not accept the token.")
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
        bucketNote = "Checking the bucket…"
        Task {
            do { try await S3Host(credentials: c, bucket: name).checkAccess(); bucketNote = "The bucket accepted the keys." }
            catch { bucketNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
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

    func reset() { state = .idle; phoneHost?.stop() }

    func forgetToken() { store.delete(); hasToken = false }

    /// For "This iPhone": keeps the listener up until iOS has taken the whole file, then closes it. A transfer that
    /// never completes becomes a failure with a reason instead of a silent hang. Returns whether the app was delivered.
    /// If the person started over meanwhile (state is no longer "handed to iOS"), their newer state is left alone.
    func finishPhoneTransfer(timeout: TimeInterval = 600) async -> Bool {
        guard hostKind == .phone, let host = phoneHost else { return true }
        let delivered = await host.waitForTransfer(timeout: timeout)
        defer { host.stop() }
        guard state == .handedToiOS else { return false }
        if delivered {
            try? await Task.sleep(nanoseconds: 3_000_000_000)      // let the last connection close cleanly
        } else {
            state = .failed(LoopbackHost.transferFailureMessage(served: host.servedIPA))
            ImportLogs.shared.log("ota: transfer did not finish (served=\(host.servedIPA))")
        }
        return delivered
    }

    /// Shows a reason in place of an upload (used when iOS is known to refuse the app).
    func block(_ reason: String) { state = .failed(reason) }

    /// Returns the install link to open, or nil after setting `state` to a failure.
    func upload(ipa: URL, bundleIdentifier: String, version: String, build: String = "", title: String) async -> URL? {
        let host: InstallHost
        var bucketRecord: BucketCleanupRecord?
        switch hostKind {
        case .phone:
            guard let feed = URL(string: certificateFeedText), !certificateFeedText.isEmpty else {
                state = .failed(certificateFeedText.isEmpty ? "No certificate feed is set. Enter one in the install settings, or switch Install host to My server or Bucket."
                                                            : "The certificate feed address is not valid.")
                return nil
            }
            do {
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Install")
                let bundle = try await CertificateFeed.load(feed: feed, cacheDirectory: dir, allowedNames: LoopbackConfig.allowedNames(for: feed))
                phoneHost?.stop()
                let loopback = try LoopbackHost(p12: bundle.p12Data, password: bundle.password, host: bundle.name)
                phoneHost = loopback; host = loopback
            } catch {
                state = .failed(withFallbacks((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
                ImportLogs.shared.log("ota: phone host failed")
                return nil
            }
        case .server:
            guard let endpoint = try? OTAEndpoint(serverText), let raw = store.load(),
                  let token = String(data: raw, encoding: .utf8) else {
                state = .failed("Set the install server address and token first."); return nil
            }
            host = OTAUploader(endpoint: endpoint, token: token)
        case .bucket:
            guard let (c, name) = bucketCredentials() else { state = .failed("Set up the bucket first (endpoint, name, region and keys)."); return nil }
            await sweepBucket()
            do {
                let s3 = try bucketHost(c, name)
                bucketRecord = try BucketCleanupRecord(sessionID: s3.id, scope: BucketCleanupScope(credentials: c, bucket: name))
                host = s3
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return nil
            }
        }
        state = .uploading(0)
        ImportLogs.shared.log("ota: upload start (\(hostKind.rawValue))")
        let began = Date()
        defer { if let record = bucketRecord { activeBucketRecords.remove(record.id) } }
        do {
            if let record = bucketRecord {
                activeBucketRecords.insert(record.id)
                let store = cleanupStore
                // A preparation record must commit before the first remote object can be created.
                try await Task.detached { try store.put(record) }.value
            }
            let link = try await host.publish(ipa: ipa, bundleIdentifier: bundleIdentifier, version: version, build: build, title: title
            ) { p in Task { @MainActor in self.state = .uploading(p) } }
            if var record = bucketRecord {
                record.expiresAt = Date().addingTimeInterval(Double(S3Host.linkLifetime))
                let committed = record, store = cleanupStore
                do { try await Task.detached { try store.put(committed) }.value }
                catch {
                    state = .failed("The IPA was uploaded, but Wax could not save its cleanup deadline. The installer was not opened. Free space and retry.")
                    return nil
                }
            }
            state = .handedToiOS
            ImportLogs.shared.log("ota: uploaded in \(Int(Date().timeIntervalSince(began))) s, opening installer")
            return link
        } catch {
            state = .failed(withFallbacks((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            ImportLogs.shared.log("ota: failed")
            return nil
        }
    }

    /// "This iPhone" is the default, so a dead certificate feed is the failure a user hits first and the one where
    /// silence costs most: the static help text mentions the alternatives, but the error they are actually reading
    /// did not. Name them there too.
    private func withFallbacks(_ message: String) -> String {
        guard hostKind == .phone else { return message }
        return "\(message) You can also hand the app over from My server or a Bucket, under Install."
    }
}
