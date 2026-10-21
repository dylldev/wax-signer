import CredentialKit
import Foundation
import InstallKit
import IPAKit
import SigningKit
import UIKit

/// Drives the Sign screen. All heavy work runs off the main thread; every failure ends in `errorText`.
@MainActor
final class SigningModel: ObservableObject {
    struct Report {
        var archiveLines: [String]
        var checkSummary: String
        var checkFailures: [String]
        var profileLines: [String]
        var warnings: [String]
        var output: URL
        var outputSize: Int
        var installTarget: InstallTarget
    }

    @Published private(set) var ipaName: String?
    @Published private(set) var ipaInfo: IPAMetadata?
    /// A result belongs to the settings it was made with; changing them clears it so a stale file cannot be exported.
    @Published var certificateID: UUID? { didSet { if certificateID != oldValue { clearResult() } } }
    /// UI preference only; does not affect how signing works.
    /// On by default: profiles with a fixed app ID are common, and other signers re-label the app for you too.
    @Published var rewriteBundleID = UserDefaults.standard.object(forKey: "rewriteBundleID") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rewriteBundleID, forKey: "rewriteBundleID"); if rewriteBundleID != oldValue { clearResult() } }
    }
    /// Keep the app's own bundle ID and sign under the profile's application ID, as other signers do.
    /// On by default: verified on iOS 27.2 that a Distribution profile with a fixed app ID installs and launches
    /// an app under its own bundle ID. iOS has the final say for other profiles.
    @Published var keepBundleID = UserDefaults.standard.object(forKey: "keepBundleID") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepBundleID, forKey: "keepBundleID"); if keepBundleID != oldValue { clearResult() } }
    }
    /// Extra changes made to the app before signing. The switches start from the saved defaults.
    @Published var edits: AppEdits = SigningModel.loadDefaultEdits() { didSet { if edits != oldValue { clearResult() } } }
    private static let editsKey = "signing.defaultEdits"
    private static func loadDefaultEdits() -> AppEdits {
        UserDefaults.standard.data(forKey: editsKey).flatMap { try? JSONDecoder().decode(AppEdits.self, from: $0) } ?? AppEdits()
    }
    func saveEditsAsDefaults() {
        if let data = try? JSONEncoder().encode(edits.defaultsOnly()) { UserDefaults.standard.set(data, forKey: Self.editsKey) }
    }
    func resetEditsToDefaults() { edits = Self.loadDefaultEdits() }

    /// The profile to sign the app with, or nil for "automatic" (Wax picks the best fit).
    @Published var profileChoice: UUID? { didSet { if profileChoice != oldValue { clearResult() } } }
    @Published var bundleProfiles: [String: UUID] = [:] { didSet { if bundleProfiles != oldValue { clearResult() } } }
    @Published var strictEntitlements = false { didSet { if strictEntitlements != oldValue { clearResult() } } }
    /// A chosen entitlements file (a property list) that replaces the app's own; per app, never kept.
    @Published private(set) var customEntitlements: [String: Any]?
    @Published private(set) var customEntitlementsName: String?

    /// Reads a chosen entitlements file. Throws a plain message when it is not a property list of entitlements.
    func setEntitlements(from url: URL?) throws {
        clearResult()
        guard let url else { customEntitlements = nil; customEntitlementsName = nil; return }
        defer { discardPickerCopy(url) }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var data = Data()
        while let chunk = try input.read(upToCount: min(64 * 1024, 256 * 1024 + 1 - data.count)), !chunk.isEmpty {
            guard chunk.count <= 256 * 1024 - data.count else { throw EntitlementsFileError.tooLarge }
            data.append(chunk)
        }
        try input.close()
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any], !dict.isEmpty else {
            throw EntitlementsFileError.notEntitlements
        }
        customEntitlements = dict
        customEntitlementsName = url.lastPathComponent
    }

    enum EntitlementsFileError: LocalizedError {
        case notEntitlements, tooLarge
        var errorDescription: String? {
            switch self {
            case .notEntitlements: "That file is not an entitlements property list (a .plist or .entitlements file with keys and values)."
            case .tooLarge: "Choose an entitlements property list no larger than 256 KiB."
            }
        }
    }

    @Published private(set) var busyMessage: String?
    /// How far through signing the app really is (0...1), from the engine's own stages.
    @Published private(set) var signFraction: Double = 0
    @Published private(set) var report: Report?
    @Published private(set) var errorText: String?

    private var ipaURL: URL?
    private var signStarted: Date?
    /// How long the last signing run took, for the progress estimate.
    private(set) var lastSignSeconds: Double = 0
    private let credentials: CredentialsModel
    private let library: LibraryModel
    private let background: BackgroundJob
    @Published private(set) var shelfSaveState: LibraryModel.SaveState = .idle
    private var signedPendingID: UUID?
    private var resultGeneration = UUID()
    private var busyOwner = UUID()
    @Published private(set) var runningSign = false

    init(credentials: CredentialsModel, library: LibraryModel? = nil, background: BackgroundJob? = nil) {
        self.credentials = credentials; self.library = library ?? .shared; self.background = background ?? .shared
    }

    /// Weights signing against uploading by how long each took on earlier runs (or sensible defaults).
    func jobProgress(uploadFraction: Double, exportOnly: Bool) -> JobProgress {
        let mb = Double((try? ipaURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        let e = JobEstimator(store: UserDefaults.standard).estimate(megabytes: max(mb, 1))
        return JobProgress(signSeconds: e.sign, uploadSeconds: exportOnly ? 0 : e.upload)
    }

    @Published private(set) var preview: PreparedIPA.Preview?
    @Published private(set) var previewInstalls = false
    private var prepared: PreparedIPA?
    private var credentialSnapshot: [UUID: Data] = [:]
    private var preparationTask: Task<Void, Never>?
    private var previewExpiration: Task<Void, Never>?
    private var activeCancellation: SigningCancellation?

    func cancelPreparation() {
        preparationTask?.cancel(); preparationTask = nil
        previewExpiration?.cancel(); previewExpiration = nil
        activeCancellation?.cancel()
        let lease = prepared; prepared = nil; preview = nil
        // Disposal may enumerate a large tree; never do that on the main actor.
        if let lease { Task.detached { lease.discard() } }
    }
    func clearResult() { cancelPreparation(); resultGeneration = UUID(); report = nil; errorText = nil; readyLink = nil; signedPendingID = nil; shelfSaveState = .idle }

    enum BundleIDMode: String, CaseIterable { case keep, rename }

    /// One choice in place of two switches: keep the app's own bundle ID, or rename it to fit a fixed-ID profile.
    var bundleIDMode: BundleIDMode {
        get { keepBundleID ? .keep : .rename }
        set { keepBundleID = newValue == .keep; if newValue == .rename { rewriteBundleID = true } }
    }

    /// The chosen IPA itself, when it is already signed and carries a profile (installed exactly as it is).
    var signedInputTarget: InstallTarget? {
        guard let info = ipaInfo, info.hasCodeSignature, info.hasEmbeddedProfile, let ipaURL else { return nil }
        return InstallTarget(ipa: ipaURL, bundleIdentifier: info.bundleIdentifier, version: info.version, build: info.build,
                             title: info.displayName)
    }

    /// The install link of the last upload, kept so the Install button still works after a cancelled prompt.
    @Published private(set) var readyLink: URL?
    /// True from the tap on Sign & Install until the app has been handed over (or failed), so a second install cannot start.
    @Published private(set) var installing = false
    private var installSession: OTAInstallModel.Session?

    func ownsInstallation(_ ota: OTAInstallModel) -> Bool { installSession.map { ota.owns($0) } ?? false }
    func cancelInstallation(ota: OTAInstallModel) { if let installSession { ota.cancel(installSession) } }
    func startOver(ota: OTAInstallModel) { cancelInstallation(ota: ota); clearResult(); ota.resetIfIdle() }
    func canOpenInstallLink(_ link: URL, ota: OTAInstallModel) -> Bool {
        ota.activeSession == nil || (ownsInstallation(ota) && readyLink == link)
    }
    /// Notification activation can be delayed by foregrounding. It must not open over a replacement operation.
    func openInstallLink(_ link: URL, ota: OTAInstallModel, prepare: () async throws -> Void, open: (URL) -> Void) async -> Bool {
        guard canOpenInstallLink(link, ota: ota), !Task.isCancelled else { return false }
        let owner = ota.activeSession?.id
        do { try await prepare() } catch { return false }
        guard !Task.isCancelled, owner == ota.activeSession?.id, canOpenInstallLink(link, ota: ota) else { return false }
        open(link); return true
    }

    /// One tap: sign with the chosen certificate (when there is one), then upload and hand the app to iOS.
    /// Nothing is uploaded unless signing succeeded and its self-check passed. Keeps going if Wax is sent to the
    /// background, and posts a notification when the app is ready to install.
    func signAndInstall(ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard !installing, !Task.isCancelled else { return }
        let session: OTAInstallModel.Session
        do { session = try ota.reserve() }
        catch { errorText = error.localizedDescription; return }
        installing = true; installSession = session
        defer { ota.release(session); if installSession === session { installSession = nil } }
        let cancellation = prepared?.cancellation ?? SigningCancellation()
        ota.onRelease(of: session) { cancellation.cancel() }
        let needsSigning = certificateID != nil
        let job = background
        job.askForNotificationPermission()
        let backgroundID = job.begin(title: ipaInfo?.displayName ?? "Wax", onExpiration: {
            cancellation.cancel()
            ota.cancel(session)
        })
        var succeeded = false
        defer { job.end(backgroundID, success: succeeded); installing = false }
        readyLink = nil

        let target: InstallTarget?
        if needsSigning {
            guard let task = sign(standalone: false, storeBigFiles: session.kind == .phone, backgroundID: backgroundID, cancellation: cancellation) else { return }
            await withTaskCancellationHandler(operation: { await task.value }, onCancel: {
                task.cancel()
                Task { @MainActor in ota.cancel(session) }
            })
            guard !Task.isCancelled, ota.owns(session), let r = report, r.checkFailures.isEmpty else { return }
            if BundleIDGuard.replacesRunningWax(originalID: ipaInfo?.bundleIdentifier ?? "",
                                                finalID: r.installTarget.bundleIdentifier,
                                                runningID: Bundle.main.bundleIdentifier) {
                ota.fail(session, reason: BundleIDGuard.explanation)
                return
            }
            target = r.installTarget
        } else {
            target = signedInputTarget
            // Installing an already-signed app under Wax's own ID would replace the running Wax, same as a re-label
            // would. A signed copy of Wax itself (same executable) is an update, not a clash; a different app that
            // merely carries one of Wax's IDs is not.
            let isWaxItself = ipaInfo?.executable == Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            if let t = target, !isWaxItself,
               t.bundleIdentifier == Bundle.main.bundleIdentifier {
                ota.fail(session, reason: BundleIDGuard.explanation)
                return
            }
        }
        guard let target, !Task.isCancelled, ota.owns(session) else { return }

        // Mirror the upload's real progress into the system's background progress.
        let weights = jobProgress(uploadFraction: 0, exportOnly: false)
        let watcher = ota.$state.sink { state in
            if ota.owns(session), case .uploading(let f) = state { job.update(backgroundID, fraction: weights.overall(sign: 1, upload: f), subtitle: "Sending to your server") }
        }
        defer { watcher.cancel() }

        let uploadStart = Date()
        guard let link = await ota.upload(ipa: target.ipa, bundleIdentifier: target.bundleIdentifier,
                                          version: target.version, build: target.build, title: target.title, session: session),
              !Task.isCancelled, ota.owns(session) else { return }
        let megabytes = Double((try? target.ipa.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        var estimator = JobEstimator(store: UserDefaults.standard)
        estimator.record(megabytes: megabytes, signSeconds: needsSigning ? lastSignSeconds : 0,
                         uploadSeconds: Date().timeIntervalSince(uploadStart))
        readyLink = link
        if UIApplication.shared.applicationState == .active {
            open(link)
        } else {
            job.notifyIfInBackground(InstallNotification.readyToInstall(appTitle: target.title, link: link))
        }
        // The phone serves the file itself, so it must stay alive (also in the background) until iOS has it all.
        job.update(backgroundID, fraction: 1, subtitle: "Waiting for iOS to take the app")
        succeeded = await ota.finishPhoneTransfer(session: session)
        if session.kind == .phone || !succeeded { readyLink = nil }      // the listener is closed now; the link no longer works
    }

    var canSignAndInstall: Bool {
        busyMessage == nil && !runningSign && !shelfSaveState.isSaving && !installing && ipaInfo != nil && (certificateID != nil || signedInputTarget != nil)
    }

    var canSign: Bool { ipaInfo != nil && certificateID != nil && busyMessage == nil && !runningSign && !shelfSaveState.isSaving && !installing }

    // MARK: Choosing the IPA

    /// Chooses an IPA already on the shelf.
    func use(_ entry: LibraryEntry) { picked(ipa: library.url(for: entry), fromLibrary: entry) }

    @discardableResult
    func picked(ipa url: URL, fromLibrary: LibraryEntry? = nil) -> Task<Void, Never> {
        clearResult(); ipaInfo = nil
        edits = edits.defaultsOnly()
        profileChoice = nil; bundleProfiles = [:]; customEntitlements = nil; customEntitlementsName = nil
        let generation = resultGeneration; busyOwner = generation
        ipaName = url.lastPathComponent; busyMessage = "Reading “\(url.lastPathComponent)”…"
        return Task {
            do {
                if fromLibrary != nil {
                    let info = try await Task.detached { try IPAInspector.inspect(url: url) }.value
                    guard resultGeneration == generation else { return }
                    ipaURL = url; ipaInfo = info
                } else {
                    let (pending, info) = try await library.preparePicked(url)
                    discardPickerCopy(url)
                    guard resultGeneration == generation else { return }
                    let storage = library.storage
                    ipaURL = try await Task.detached { try storage.pendingURL(pending.id) }.value; ipaInfo = info
                    do {
                        let saved = try await library.finishPending(pending.id)
                        ipaURL = library.url(for: saved.entry)
                    } catch {
                        // Signing can still use the durable input; its shelf failure is a separate outcome.
                        errorText = "The IPA is ready to sign, but its unsigned shelf save failed. " + error.localizedDescription
                    }
                }
            } catch { if resultGeneration == generation { errorText = error.localizedDescription } }
            if busyOwner == generation { busyMessage = nil }
        }
    }

    /// Only the signer calls this after its self-check and R2 artifact gate. Report survives a shelf failure.
    func acceptSignedResult(_ result: Report, pendingID: UUID, generation: UUID? = nil) async {
        guard generation == nil || generation == resultGeneration else { return }
        report = result; signedPendingID = pendingID
        await retrySignedSave()
    }

    func retrySignedSave() async {
        guard let id = signedPendingID, report != nil, !shelfSaveState.isSaving else { return }
        shelfSaveState = .saving
        do {
            let saved = try await library.finishPending(id)
            guard signedPendingID == id else { return }
            relocateReport(to: library.url(for: saved.entry))
            shelfSaveState = .saved(saved)
        } catch {
            guard signedPendingID == id, let report else { return }
            let file = (error as? ShelfSaveFailure)?.artifact ?? report.output
            relocateReport(to: file)
            shelfSaveState = .failed((error as? ShelfSaveFailure) ?? ShelfSaveFailure(reason: error.localizedDescription, artifact: file, pendingID: id))
        }
    }
    private func relocateReport(to file: URL) {
        guard var result = report else { return }
        let old = result.installTarget
        result.output = file
        result.installTarget = InstallTarget(ipa: file, bundleIdentifier: old.bundleIdentifier, version: old.version, build: old.build, title: old.title)
        report = result
    }

    // MARK: Signing

    /// Stage the actual edited tree before presenting decisions. Private signing material is not retained in the preview.
    @discardableResult
    func prepareForSigning(installAfter: Bool = false) -> Task<Void, Never>? {
        guard canSign, let ipaURL, let certificateID, let store = credentials.store,
              let cert = credentials.certificates.first(where: { $0.id == certificateID }) else { return nil }
        clearResult()
        let generation = resultGeneration
        busyOwner = generation; runningSign = true; busyMessage = "Preparing the IPA…"; signFraction = 0
        let token = SigningCancellation(); activeCancellation = token
        let appEdits = edits, chosen = profileChoice, pins = bundleProfiles
        let override = customEntitlements, rewrite = rewriteBundleID, keep = keepBundleID, strict = strictEntitlements
        let backgroundID = background.begin(title: ipaInfo?.displayName ?? "Wax", onExpiration: { token.cancel() })
        let task = Task.detached(priority: .userInitiated) {
            await withTaskCancellationHandler(operation: {
                do {
                    try token.check()
                    let identity = try SecurityFrameworkIdentity(identity: store.identity(for: certificateID))
                    let raw = try Self.profileSnapshot(store)
                    let profiles = try Self.profileSet(raw: raw, main: chosen, pins: pins)
                    var options = SigningOptions(); options.cancellation = token
                    options.rewriteBundleIdentifier = rewrite; options.keepBundleIdentifier = keep
                    options.overrideEntitlements = override; options.entitlementPolicy = strict ? .reject : .dropAndWarn
                    let lease = try PreparedIPA.prepare(ipa: ipaURL, certificateChainDER: identity.certificateChainDER,
                        certificateTeamID: cert.teamID, profiles: profiles, options: options, edits: appEdits,
                        workDirectory: FileManager.default.temporaryDirectory) { progress in
                        Task { @MainActor in
                            guard self.resultGeneration == generation, self.runningSign, self.preview == nil else { return }
                            self.busyMessage = progress.message; self.signFraction = progress.fraction
                            self.background.update(backgroundID, fraction: progress.fraction, subtitle: progress.message)
                        }
                    }
                    await self.acceptPreparation(lease, credentials: raw, generation: generation, installAfter: installAfter)
                } catch {
                    await MainActor.run {
                        if self.resultGeneration == generation {
                            self.errorText = error is CancellationError ? "Preparation canceled. Original and signed IPAs are kept." : error.localizedDescription
                        }
                    }
                }
                await MainActor.run {
                    self.background.end(backgroundID, success: false) // a preview is not a completed signed/save outcome
                    if self.busyOwner == generation { self.runningSign = false; self.busyMessage = nil }
                }
            }, onCancel: { token.cancel() })
        }
        preparationTask = task; return task
    }

    func acceptPreparation(_ lease: PreparedIPA, credentials: [UUID: Data], generation: UUID, installAfter: Bool) {
        guard resultGeneration == generation, (try? lease.cancellation.check()) != nil else {
            Task.detached { lease.discard() }; return
        }
        prepared = lease; preview = lease.preview; previewInstalls = installAfter; credentialSnapshot = credentials
        previewExpiration = Task { [weak self, weak lease] in
            let delay = max(0, lease?.preview.expiresAt.timeIntervalSinceNow ?? 0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let lease, self.prepared === lease else { return }
            self.clearResult(); self.errorText = "This preview expired and its scratch files were released. Prepare the IPA again."
        }
    }

    nonisolated static func profileSnapshot(_ store: CredentialStore) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: store.profiles().map { ($0.id, try store.profileData(for: $0.id)) })
    }
    nonisolated static func profileSet(raw: [UUID: Data], main: UUID?, pins: [String: UUID]) throws -> ProfileSet {
        // Corrupt or unreadable profiles are explicit failures, not silently different candidate sets.
        let all = try raw.mapValues { try ProvisioningProfile.parse($0) }
        var overrides: [String: ProvisioningProfile] = [:]
        var selected = pins
        if let main { selected["."] = main }
        for (path, id) in selected {
            guard let profile = all[id] else { throw SigningError.bundle("Selected profile for \(path) is unavailable. Prepare again after choosing a profile.") }
            overrides[path] = profile
        }
        return ProfileSet(pool: all.keys.sorted { $0.uuidString < $1.uuidString }.map { all[$0]! }, overrides: overrides)
    }

    @discardableResult
    /// `storeBigFiles` writes changed big files uncompressed: right for an install that stays on this phone, wrong for
    /// anything uploaded or exported.
    func sign(standalone: Bool = true, storeBigFiles: Bool = false, backgroundID: UUID? = nil, cancellation: SigningCancellation? = nil) -> Task<Void, Never>? {
        guard busyMessage == nil, !runningSign, !shelfSaveState.isSaving, let info = ipaInfo, let certificateID, let store = credentials.store,
              credentials.certificates.contains(where: { $0.id == certificateID }) else { return nil }
        guard let lease = prepared else { errorText = "Prepare and confirm a signing preview first."; return nil }
        guard cancellation == nil || cancellation === lease.cancellation else {
            errorText = "The signing operation owner changed. Use the preview's original operation or prepare again."
            return nil
        }
        errorText = nil
        let rawProfiles = credentialSnapshot
        prepared = nil; preview = nil; previewExpiration?.cancel(); previewExpiration = nil
        let generation = resultGeneration
        busyOwner = generation; runningSign = true
        busyMessage = "Signing confirmed plan…"
        let title = info.displayName.isEmpty ? "Wax" : info.displayName
        if standalone { background.askForNotificationPermission() }
        // OTA/background cancellation must address the exact owner created during preparation.
        let cancellation = lease.cancellation
        activeCancellation = cancellation
        let ownedBackgroundID = standalone ? background.begin(title: title, onExpiration: { cancellation.cancel() }) : backgroundID
        let weights = jobProgress(uploadFraction: 0, exportOnly: standalone)
        let rewrite = rewriteBundleID
        let keep = keepBundleID
        let model = self
        let shelf = library.storage
        ImportLogs.shared.log("sign: start id=\(ipaInfo?.bundleIdentifier ?? "?") rewrite=\(rewrite)")

        signFraction = 0
        signStarted = Date()
        let throttle = ProgressThrottle()
        return Task.detached(priority: .userInitiated) {
          await withTaskCancellationHandler(operation: {
            do {
                try cancellation.check()
                let identity = try SecurityFrameworkIdentity(identity: store.identity(for: certificateID))

                guard try Self.profileSnapshot(store) == rawProfiles else {
                    throw SigningError.bundle("Provisioning profiles changed after preview. Prepare again.")
                }
                try cancellation.check()
                let pending = try shelf.reserve(kind: .signed, name: title, provenance: .waxSigned)
                let output = try shelf.pendingURL(pending.id)

                let outcome = try lease.execute(identity: identity, output: output,
                    compressChangedFiles: !storeBigFiles
                ) { p in
                    // The engine reports often; only pass on a visible change.
                    guard throttle.shouldPublish(p) else { return }
                    Task { @MainActor in
                        guard model.runningSign, model.report == nil, model.resultGeneration == generation else { return }
                        model.busyMessage = p.message; model.signFraction = p.fraction
                        if let ownedBackgroundID { model.background.update(ownedBackgroundID, fraction: weights.overall(sign: p.fraction, upload: 0), subtitle: p.message) }
                    }
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: outcome.output.path)[.size] as? Int) ?? 0
                let profileLines = outcome.signing.profileSelections.map { sel -> String in
                    "\(sel.bundlePath == "." ? "App" : sel.bundlePath) → “\(sel.profileName)” · \(Self.describe(sel.signatureStatus))"
                }

                var archive = [
                    "Input: \(outcome.inputArchive.displayName) \(outcome.inputArchive.version) (\(outcome.inputArchive.build)), \(outcome.inputArchive.entryCount) files",
                    "Output: \(outcome.outputArchive.entryCount) files, signature files present: \(outcome.outputArchive.hasCodeSignature ? "yes" : "no")",
                ]
                archive += outcome.editNotes
                if keep, let first = outcome.signing.profileSelections.first {
                    archive.append("Bundle IDs kept. Signed under the profile “\(first.profileName)”; iOS decides whether it accepts the app.")
                }
                for (old, new) in outcome.signing.bundleIdentifierChanges.sorted(by: { $0.key < $1.key }) {
                    archive.append("Bundle ID changed: \(old) → \(new)")
                }
                let r = Report(
                    archiveLines: archive,
                    checkSummary: outcome.selfCheck.passed
                        ? "Passed \(outcome.selfCheck.checks.count) consistency checks"
                        : "FAILED \(outcome.selfCheck.failures.count) of \(outcome.selfCheck.checks.count)",
                    checkFailures: outcome.selfCheck.failures.map { "\($0.name) \($0.detail)" },
                    profileLines: profileLines, warnings: outcome.signing.warnings,
                    output: outcome.output, outputSize: size,
                    installTarget: InstallTarget(
                        ipa: outcome.output, bundleIdentifier: outcome.outputArchive.bundleIdentifier,
                        version: outcome.outputArchive.version, build: outcome.outputArchive.build, title: outcome.outputArchive.displayName))
                ImportLogs.shared.log("sign: ok items=\(outcome.signing.items.count) bytes=\(size)")
                await model.acceptSignedResult(r, pendingID: pending.id, generation: generation)
                await MainActor.run {
                    model.runningSign = false
                    if model.busyOwner == generation { model.busyMessage = nil }
                    if model.resultGeneration == generation { model.lastSignSeconds = Date().timeIntervalSince(model.signStarted ?? Date()) }
                    if standalone {
                        let saved = model.resultGeneration == generation && model.shelfSaveState.confirmedSaved
                        if let ownedBackgroundID { model.background.end(ownedBackgroundID, success: saved) }
                        if saved { model.background.notifyIfInBackground(InstallNotification.signed(appTitle: title)) }
                    }
                }
            } catch {
                lease.discard()
                let text = error is CancellationError ? "Signing canceled. The original and earlier signed IPAs are kept. Retry when ready."
                    : ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ImportLogs.shared.log("sign: failed \(ImportLog.describe(error))")
                await MainActor.run {
                    model.runningSign = false
                    if model.resultGeneration == generation { model.errorText = text }
                    if model.busyOwner == generation { model.busyMessage = nil }
                    if standalone, let ownedBackgroundID { model.background.end(ownedBackgroundID, success: false) }
                }
            }
          }, onCancel: { cancellation.cancel() })
        }
    }

    /// Pins the main app to the profile the user chose; empty (automatic) when none was chosen.
    nonisolated static func overrides(chosen: UUID?, store: CredentialStore) throws -> [String: ProvisioningProfile] {
        guard let chosen else { return [:] }
        return ["." : try ProvisioningProfile.parse(try store.profileData(for: chosen))]
    }

    nonisolated static func describe(_ status: ProfileSignatureStatus) -> String {
        switch status {
        case .appleChainVerified: return "CMS intact; chain reaches a pinned Apple root. Profile-signing eligibility is not evaluated."
        case .signatureValidButUntrusted: return "profile signature intact but not shown to be Apple's"
        case .invalid(let why): return "profile signature invalid (\(why))"
        }
    }
}

/// Lets a progress report through when the message changes or it moved by at least one percent.
/// Called from several worker threads at once while unpacking, so the state is guarded.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: SigningProgress?
    func shouldPublish(_ p: SigningProgress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let publish = shouldStore(p)
        if publish { last = p }
        return publish
    }
    private func shouldStore(_ p: SigningProgress) -> Bool {
        guard let last else { return true }
        return last.message != p.message || p.fraction - last.fraction >= 0.01
    }
}
