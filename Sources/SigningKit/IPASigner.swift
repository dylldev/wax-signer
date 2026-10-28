import CredentialKit
import CryptoKit
import Foundation
import IPAKit

/// Where signing is: a short message and how far through the whole job (0...1) it really is.
public struct SigningProgress: Equatable, Sendable {
    public let message: String
    public let fraction: Double
}

public struct IPASigningOutcome {
    public let output: URL
    /// Structure of the archive that came in, and of the one that went out. File presence only.
    public let inputArchive: IPAMetadata
    public let outputArchive: IPAMetadata
    public let signing: SigningResult
    /// Self-check of the produced bundle. Not Apple's verifier; trust, revocation and entitlement approval
    /// are not evaluated, and installation eligibility is never determined here.
    public let selfCheck: VerificationReport
    /// One line for each change the user's signing options made to the app.
    public let editNotes: [String]
}

/// Owns the private scratch tree between preflight review and signing. The source IPA is never changed.
public final class PreparedIPASigning: @unchecked Sendable {
    public let inputArchive: IPAMetadata
    public let editNotes: [String]
    public let minimumOSVersion: String?
    public let preflight: SigningPreflightReport

    fileprivate let work: URL
    fileprivate let tree: URL
    fileprivate let app: URL
    fileprivate let ipaURL: URL
    fileprivate let identity: CodeSigningIdentity
    fileprivate let certificateTeamID: String?
    fileprivate let profiles: ProfileSet
    fileprivate let options: SigningOptions
    fileprivate let source: IPAArchiveSession
    fileprivate let inventory: IPAExtractionInventory
    fileprivate let cancellation: SigningCancellation
    private let lock = NSLock()
    private var running = false
    private var cleaned = false

    fileprivate init(work: URL, tree: URL, app: URL, ipaURL: URL, inputArchive: IPAMetadata, editNotes: [String],
                     minimumOSVersion: String?, preflight: SigningPreflightReport, identity: CodeSigningIdentity, certificateTeamID: String?,
                     profiles: ProfileSet, options: SigningOptions, source: IPAArchiveSession, inventory: IPAExtractionInventory,
                     cancellation: SigningCancellation) {
        self.source = source; self.inventory = inventory; self.cancellation = cancellation
        self.work = work; self.tree = tree; self.app = app; self.ipaURL = ipaURL; self.inputArchive = inputArchive
        self.editNotes = editNotes; self.minimumOSVersion = minimumOSVersion; self.preflight = preflight; self.identity = identity
        self.certificateTeamID = certificateTeamID; self.profiles = profiles; self.options = options
    }

    fileprivate func begin() throws {
        lock.lock(); defer { lock.unlock() }
        guard !running, !cleaned else { throw SigningError.io("this prepared signing run was already used or discarded") }
        running = true
    }

    fileprivate func finish() {
        lock.lock()
        running = false
        let shouldClean = !cleaned
        cleaned = true
        lock.unlock()
        if shouldClean { IPASigner.dispose(work) }
    }

    /// Asks a running sign(prepared:) to stop at its next safe point.
    public func cancel() { cancellation.cancel() }

    /// Discards the scratch tree when the user cancels or changes signing inputs.
    public func discard() {
        lock.lock()
        guard !running, !cleaned else { lock.unlock(); return }
        cleaned = true
        lock.unlock()
        IPASigner.dispose(work)
    }

    deinit { discard() }
}

/// First error from a background tree check.
final class TreeCheckResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    func set(_ error: Error) { lock.lock(); stored = stored ?? error; lock.unlock() }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return stored }
}

/// IPA in, signed IPA out, entirely with the library: validate, extract, sign, self-check, repack.
/// The self-check and final packaged-byte integrity gate must pass before atomic output replacement.
public enum IPASigner {
    private static let preparationPrefix = "Wax-PreparedSigning-"
    private static let trashPrefix = "Wax-Trash-"

    /// Moves a finished worktree aside at once and deletes it in the background: deleting a tree of tens of thousands of
    /// files takes about a second. Anything left when the app is suspended goes with the next `removeStalePreparations`.
    fileprivate static func dispose(_ work: URL) {
        let trash = work.deletingLastPathComponent().appendingPathComponent(trashPrefix + UUID().uuidString, isDirectory: true)
        let target = (try? FileManager.default.moveItem(at: work, to: trash)) != nil ? trash : work
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: target) }
    }

    /// Removes only abandoned scratch directories created by this signer.
    public static func removeStalePreparations(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items where item.lastPathComponent.hasPrefix(preparationPrefix) || item.lastPathComponent.hasPrefix(trashPrefix) {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Inspects and prepares a private worktree without signing or changing the source IPA.
    public static func prepare(ipa: URL, identity: CodeSigningIdentity, certificateTeamID: String?, profiles: ProfileSet,
                               options: SigningOptions = SigningOptions(), edits: AppEdits = AppEdits(),
                               workDirectory: URL, progress: ((SigningProgress) -> Void)? = nil) throws -> PreparedIPASigning {
        let fm = FileManager.default
        func stage(_ message: String, _ lo: Double, _ hi: Double, _ f: Double = 0) {
            progress?(SigningProgress(message: message, fraction: lo + (hi - lo) * min(1, max(0, f))))
        }
        stage("Checking the archive…", 0, 0.02)
        let cancellation = options.cancellation ?? SigningCancellation()
        try cancellation.claim()
        let source = try IPAArchiveSession(url: ipa)
        let input = try source.inspect()
        let work = workDirectory.appendingPathComponent("\(preparationPrefix)\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            stage("Unpacking…", 0.02, 0.40)
            let tree = work.appendingPathComponent("tree", isDirectory: true)
            let inventory = try source.extract(to: tree, byteProgress: { stage("Unpacking…", 0.02, 0.40, $0) },
                                               checkCancellation: { try cancellation.check() })
            let app = tree.appendingPathComponent("Payload", isDirectory: true).appendingPathComponent(input.appFolder)
            let edited = try AppEditor.applyDetailed(edits, to: app)
            var signingOptions = options
            signingOptions.priorRenames = edited.renames
            signingOptions.cancellation = cancellation
            stage("Checking signing inputs…", 0.40, 0.52)
            var report = BundleSigner.preflight(appDirectory: app, identity: identity, certificateTeamID: certificateTeamID,
                                                profiles: profiles, options: signingOptions)
            if !edited.notes.isEmpty {
                report = SigningPreflightReport(findings: report.findings + [
                    PreflightFinding(id: "app-edits", status: .warning, title: "Your app edits will be applied",
                                     detail: edited.notes.joined(separator: " · "))
                ], blockingError: report.blockingError, selections: report.selections)
            }
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")),
                                                                  format: nil) as? [String: Any]
            report = SigningPreflightReport(findings: report.findings + [
                PreflightFinding(id: "ipa-archive", status: .pass, title: "IPA archive can be read",
                                 detail: "Wax validated the archive and found one app bundle.",
                                 evidence: "\(input.entryCount) entries · existing signature: \(input.hasCodeSignature ? "present" : "not found") · embedded profile: \(input.hasEmbeddedProfile ? "present" : "not found")"),
                PreflightFinding(id: "apple-acceptance", status: .unknown, title: "Apple's install decision is unknown",
                                 detail: "Only iOS can make the final installation decision.")
            ], blockingError: report.blockingError, selections: report.selections)
            return PreparedIPASigning(work: work, tree: tree, app: app, ipaURL: ipa, inputArchive: input, editNotes: edited.notes,
                                      minimumOSVersion: plist?["MinimumOSVersion"] as? String, preflight: report, identity: identity, certificateTeamID: certificateTeamID,
                                      profiles: profiles, options: signingOptions, source: source, inventory: inventory,
                                      cancellation: cancellation)
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
    }

    public static func sign(ipa: URL, identity: CodeSigningIdentity, certificateTeamID: String?, profiles: ProfileSet,
                            options: SigningOptions = SigningOptions(), edits: AppEdits = AppEdits(), output: URL, workDirectory: URL,
                            compressChangedFiles: Bool = true, fastDeflate: Bool = false,
                            progress: ((SigningProgress) -> Void)? = nil) throws -> IPASigningOutcome {
        let prepared = try prepare(ipa: ipa, identity: identity, certificateTeamID: certificateTeamID, profiles: profiles,
                                   options: options, edits: edits, workDirectory: workDirectory, progress: progress)
        return try sign(prepared: prepared, output: output, compressChangedFiles: compressChangedFiles, fastDeflate: fastDeflate, progress: progress)
    }

    /// Signs the same worktree the user reviewed in the preflight report.
    public static func sign(prepared: PreparedIPASigning, output: URL, compressChangedFiles: Bool = true, fastDeflate: Bool = false,
                            progress: ((SigningProgress) -> Void)? = nil) throws -> IPASigningOutcome {
        try prepared.begin()
        defer { prepared.finish() }
        guard prepared.preflight.canContinue else {
            throw prepared.preflight.blockingError
                ?? SigningError.bundle(prepared.preflight.findings.first(where: { $0.status == .blocked })?.detail ?? "preflight did not pass")
        }
        let fm = FileManager.default
        func stage(_ message: String, _ lo: Double, _ hi: Double, _ f: Double = 0) {
            progress?(SigningProgress(message: message, fraction: lo + (hi - lo) * min(1, max(0, f))))
        }
        stage("Signing…", 0.40, 0.52)
        let result = try BundleSigner.sign(appDirectory: prepared.app, identity: prepared.identity,
                                           certificateTeamID: prepared.certificateTeamID,
                                           profiles: prepared.profiles, options: prepared.options)

        stage("Checking the signature…", 0.52, 0.62)
        guard let leaf = prepared.identity.certificateChainDER.first else { throw SigningError.keyOperation("no certificate") }
        let cancellation = prepared.cancellation
        try cancellation.check()
        let expected = try IPAArchiveManifest.capture(directory: prepared.tree)
        let selfCheck = SignatureVerifier.verifyBundle(at: prepared.app, expectedSignerSHA1: X509Fingerprint.sha1(leaf))
        guard selfCheck.passed else {
            throw SigningError.selfCheckFailed(selfCheck.failures.prefix(5).map { "\($0.name) \($0.detail)" })
        }

        stage("Packing…", 0.62, 1.0)
        try cancellation.check()
        // The tree must be proven unchanged since the manifest was captured (so the bytes verifyBundle saw are the bytes that
        // get packed). That proof only has to start after verifyBundle, so it runs while the archive is being written. Every
        // file is also compared with its manifest fingerprint as it is read for packing, and the finished archive is compared
        // with the manifest, so nothing the signer did not verify can reach the output.
        let treeCheck = DispatchGroup(), treeBox = TreeCheckResult()
        DispatchQueue.global(qos: .userInitiated).async(group: treeCheck) {
            do { try expected.verifyTree(checkpoint: { try cancellation.check() }) } catch { treeBox.set(error) }
        }
        defer { treeCheck.wait() }
        var inspected: IPAMetadata?
        try IPAArchiver.archive(directory: prepared.tree, to: output, reusing: prepared.ipaURL, compressChangedFiles: compressChangedFiles,
                                fastDeflate: fastDeflate, finalTreeCheck: false,
                                byteProgress: { stage("Packing…", 0.62, 1.0, $0) }, reusingExtraction: prepared.inventory,
                                verifiedManifest: expected, validateArchive: {
                                    treeCheck.wait()
                                    if let error = treeBox.error { throw error }
                                    inspected = try IPAInspector.inspect(url: $0)
                                    // Last safe cancellation point: the byte/tree verification and atomic promotion then
                                    // finish as one publication phase; a completed output is returned, never discarded.
                                    try cancellation.beginPublication()
                                }, checkCancellation: { try cancellation.check() })
        guard let after = inspected else { throw IPAError.integrity("packaged archive was not inspected") }
        return IPASigningOutcome(output: output, inputArchive: prepared.inputArchive, outputArchive: after,
                                 signing: result, selfCheck: selfCheck, editNotes: prepared.editNotes)
    }
}
