import CredentialKit
import CryptoKit
import Foundation
import IPAKit

/// An exclusive scratch lease. Preparation edits once; confirmation never re-extracts or resolves again.
/// Callers must retain the lease while showing its preview and discard it when leaving that workflow.
public final class PreparedIPA: @unchecked Sendable {
    public struct Limits: Sendable {
        public var extraction = IPAExtractor.Limits()
        public var packaging = IPAArchiver.Limits()
        public var maximumPreparedBytes = 6 * 1024 * 1024 * 1024
        /// Includes injected code and individual Mach-O buffers used by the existing engine.
        public var maximumCodeFileBytes = 512 * 1024 * 1024
        public var lifetime: TimeInterval = 900
        // Deterministic clock seam, internal to this module and its tests.
        var uptime: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        public init() {}
    }
    public struct AppIdentity: Equatable, Sendable {
        public let identifier: String
        public let name: String
        public let version: String
        public let build: String
    }
    public struct Code: Sendable {
        public let path: String
        public let identifier: String
        public let kind: String
    }
    public struct Preview {
        public let original: AppIdentity
        public let proposed: AppIdentity
        public let bundles: [SigningPlan.Bundle]
        public let identifierChanges: [String: String]
        public let installationAssessment: String
        public let code: [Code]
        public let changes: [String]
        public let sourceSHA256: String
        public let expiresAt: Date
    }
    public enum Failure: LocalizedError, Equatable {
        case expired, consumed, sourceChanged, invalidLimits, scratchLimit, codeLimit
        public var errorDescription: String? {
            switch self {
            case .expired: "This signing preview expired. Prepare the IPA again before confirming."
            case .consumed: "This preview was already used or canceled. Prepare a new preview."
            case .sourceChanged: "The source IPA changed after preparation. Prepare it again."
            case .invalidLimits: "The preparation resource limits are invalid."
            case .scratchLimit: "The prepared IPA exceeds its scratch-storage budget. Remove optional libraries or use a smaller IPA."
            case .codeLimit: "A code or imported library file exceeds the preparation memory budget. Use a smaller supported binary."
            }
        }
    }
    public let preview: Preview
    public let cancellation: SigningCancellation
    // Internal paths allow deterministic tamper tests; the public API exposes no mutable scratch paths.
    let work: URL
    let tree: URL
    private let sourceURL: URL
    private let inventory: IPAExtractionInventory
    private let input: IPAMetadata
    private let manifest: IPAArchiveManifest
    private let plan: SigningPlan
    private let budget: PreparationBudget
    private let lock = NSLock()
    private enum State { case ready, executing, finished }
    private var state = State.ready

    private init(preview: Preview, cancellation: SigningCancellation, work: URL, tree: URL, source: URL,
                 inventory: IPAExtractionInventory, input: IPAMetadata, manifest: IPAArchiveManifest, plan: SigningPlan, budget: PreparationBudget) {
        self.preview = preview; self.cancellation = cancellation; self.work = work; self.tree = tree
        sourceURL = source; self.inventory = inventory; self.input = input; self.manifest = manifest; self.plan = plan; self.budget = budget
    }
    deinit { try? FileManager.default.removeItem(at: work) }

    public static func prepare(ipa: URL, certificateChainDER: [Data], certificateTeamID: String?, profiles: ProfileSet,
                               options: SigningOptions = SigningOptions(), edits: AppEdits = AppEdits(), workDirectory: URL,
                               limits: Limits = Limits(), profilePolicy: SigningPlan.ProfilePolicy = .requireValidCMS,
                               progress: ((SigningProgress) -> Void)? = nil) throws -> PreparedIPA {
        guard ipa.isFileURL, workDirectory.isFileURL else { throw SigningError.io("IPA preparation requires local file URLs") }
        let owner = options.cancellation ?? SigningCancellation()
        try owner.claim()
        let budget = try PreparationBudget(limits: limits, cancellation: owner)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var template = Array(workDirectory.appendingPathComponent("prepared-XXXXXX").path.utf8CString)
        guard mkdtemp(&template) != nil else { throw SigningError.io("cannot create exclusive preparation scratch") }
        let work = URL(fileURLWithPath: String(cString: template), isDirectory: true)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: work) } }
        try budget.check()
        progress?(SigningProgress(message: "Checking the archive…", fraction: 0))
        let digest = try fingerprint(ipa, checkpoint: budget.check)
        let source = try IPAArchiveSession(url: ipa), input = try source.inspect()
        let tree = work.appendingPathComponent("tree", isDirectory: true)
        var extraction = limits.extraction
        extraction.maxTotalBytes = min(extraction.maxTotalBytes, limits.maximumPreparedBytes)
        let inventory = try source.extract(to: tree, limits: extraction, byteProgress: {
            progress?(SigningProgress(message: "Preparing the IPA…", fraction: 0.1 + 0.6 * $0))
        }, checkCancellation: { try budget.check() })
        let app = tree.appendingPathComponent("Payload/" + input.appFolder)
        // Before edits, bound existing code and imported inputs. No whole-file hashing buffer is used.
        budget.chargedBytes = try budget.inspect(tree: tree)
        try budget.inspectImports(edits.injectLibraries)
        try budget.check()
        // Bound edits metadata before it can become oversized plist data in scratch.
        guard try JSONEncoder().encode(edits).count <= 1024 * 1024 else { throw Failure.scratchLimit }
        let edited = try AppEditor.applyDetailed(edits, to: app, scratchDirectory: work,
            checkCancellation: budget.check, beforeLibraryWrite: { try budget.charge($0, directory: work) })
        let thinningNotes = try FatMachO.thinTree(at: app)
        try budget.inspect(tree: tree)
        var frozen = options
        frozen.cancellation = owner; frozen.preparationCheck = { try budget.check() }
        frozen.priorRenames.merge(edited.renames) { _, new in new }
        let plan = try BundleSigner.plan(appDirectory: app, certificateChainDER: certificateChainDER,
            certificateTeamID: certificateTeamID, profiles: profiles, options: frozen, profilePolicy: profilePolicy)
        let manifest = try IPAArchiveManifest.capture(directory: tree, checkpoint: { try budget.check() })
        guard try fingerprint(ipa, checkpoint: budget.check) == digest else { throw Failure.sourceChanged }
        let plist = try readInfo(app)
        guard let mainDecision = plan.bundles.first else { throw SigningError.bundle("prepared app has no main signing decision") }
        let proposed = AppIdentity(identifier: mainDecision.identifier,
            name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? input.displayName,
            version: plist["CFBundleShortVersionString"] as? String ?? "", build: plist["CFBundleVersion"] as? String ?? "")
        var code: [Code] = []
        func walk(_ bundle: URL, kind: String, depth: Int) throws {
            guard depth < 16, code.count < 4096 else { throw Failure.scratchLimit }
            try budget.check()
            guard (try FileManager.default.attributesOfItem(atPath: bundle.path)[.type]) as? FileAttributeType == .typeDirectory else { throw SigningError.bundle("code container must be a plain directory") }
            let path = bundle == app ? "." : String(bundle.path.dropFirst(app.path.count + 1))
            let info = try readInfo(bundle)
            let id = plan.bundles.first { $0.path == path }?.identifier ?? info["CFBundleIdentifier"] as? String ?? ""
            code.append(Code(path: path, identifier: id, kind: kind))
            for container in BundleLayout.containers {
                let folder = bundle.appendingPathComponent(container)
                guard FileManager.default.fileExists(atPath: folder.path) else { continue }
                for item in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                    if ["app", "appex", "framework"].contains(item.pathExtension) { try walk(item, kind: item.pathExtension, depth: depth + 1) }
                    else if item.pathExtension == "dylib" {
                        code.append(Code(path: String(item.path.dropFirst(app.path.count + 1)), identifier: item.lastPathComponent, kind: "dylib"))
                    }
                }
            }
        }
        try walk(app, kind: "app", depth: 0)
        let preview = Preview(original: AppIdentity(identifier: input.bundleIdentifier, name: input.displayName, version: input.version, build: input.build),
            proposed: proposed, bundles: plan.bundles, identifierChanges: edited.renames.merging(plan.identifierChanges) { _, new in new },
            installationAssessment: plan.installationAssessment, code: code, changes: edited.notes + thinningNotes,
            sourceSHA256: digest, expiresAt: Date().addingTimeInterval(budget.remaining))
        try budget.check()
        retained = true
        progress?(SigningProgress(message: "Ready to review", fraction: 1))
        return PreparedIPA(preview: preview, cancellation: owner, work: work, tree: tree, source: ipa,
                           inventory: inventory, input: input, manifest: manifest, plan: plan, budget: budget)
    }

    /// Cancellation during execution requests cooperative stop. It never removes scratch under a worker.
    /// After publication starts it cannot revoke or delete a completed output.
    public func discard() {
        cancellation.cancel()
        let remove = lock.withLock { () -> Bool in
            guard state == .ready else { return false }
            state = .finished; return true
        }
        if remove { try? FileManager.default.removeItem(at: work) }
    }

    public func execute(identity: CodeSigningIdentity, output: URL, compressChangedFiles: Bool = true,
                        now: Date = Date(), progress: ((SigningProgress) -> Void)? = nil) throws -> IPASigningOutcome {
        try lock.withLock {
            guard state == .ready else { throw Failure.consumed }
            state = .executing
        }
        defer { lock.withLock { state = .finished }; try? FileManager.default.removeItem(at: work) }
        // Completed artifacts must not be placed inside the disposable preparation lease.
        guard output.isFileURL else { throw SigningError.io("signed output must be a local file URL") }
        let dest = output.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(output.lastPathComponent).path
        let root = work.resolvingSymlinksInPath().path
        guard dest != root, !dest.hasPrefix(root + "/"), output.standardizedFileURL != sourceURL.standardizedFileURL else {
            throw SigningError.io("signed output must be outside preparation scratch and must not replace the source IPA")
        }
        try budget.check()
        guard try Self.fingerprint(sourceURL, checkpoint: budget.check) == preview.sourceSHA256 else { throw Failure.sourceChanged }
        try manifest.verifyTree(checkpoint: { try self.budget.check() })
        progress?(SigningProgress(message: "Signing confirmed plan…", fraction: 0.05))
        let result = try BundleSigner.sign(plan: plan, identity: identity, now: now)
        try budget.inspect(tree: tree)
        let expected = try IPAArchiveManifest.capture(directory: tree, checkpoint: { try self.budget.check() })
        progress?(SigningProgress(message: "Checking the signature…", fraction: 0.25))
        let app = tree.appendingPathComponent("Payload/" + input.appFolder)
        let report = SignatureVerifier.verifyBundle(at: app, expectedSignerSHA1: identity.certificateChainDER.first.map(X509Fingerprint.sha1))
        guard report.passed else { throw SigningError.selfCheckFailed(report.failures.prefix(5).map { "\($0.name) \($0.detail)" }) }
        try budget.check()
        var inspected: IPAMetadata?
        try IPAArchiver.archive(directory: tree, to: output, reusing: sourceURL, compressChangedFiles: compressChangedFiles,
            byteProgress: { progress?(SigningProgress(message: "Packing…", fraction: 0.35 + 0.65 * $0)) }, reusingExtraction: inventory,
            verifiedManifest: expected, validateArchive: { staged in
                inspected = try IPAInspector.inspect(url: staged)
                guard try Self.fingerprint(self.sourceURL, checkpoint: self.budget.check) == self.preview.sourceSHA256 else { throw Failure.sourceChanged }
                try self.cancellation.beginPublication()
            }, limits: budget.limits.packaging, checkCancellation: { try self.budget.check() })
        guard let after = inspected else { throw IPAError.integrity("packaged archive was not inspected") }
        return IPASigningOutcome(output: output, inputArchive: input, outputArchive: after, signing: result, selfCheck: report, editNotes: preview.changes)
    }

    private static func readInfo(_ app: URL) throws -> [String: Any] {
        guard let dict = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as? [String: Any] else { throw IPAError.invalidInfoPlist }
        return dict
    }
    static func fingerprint(_ url: URL, checkpoint: () throws -> Void) throws -> String {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw SigningError.io("cannot open the source IPA for identity verification") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, before.st_mode & 0o170000 == 0o100000, before.st_size >= 0,
              before.st_size < UInt32.max else { throw IPAError.unsupportedZip("source is not a regular classic-ZIP file") }
        var digest = SHA256(), count: Int64 = 0
        while true {
            try checkpoint()
            guard let chunk = try file.read(upToCount: 256 * 1024), !chunk.isEmpty else { break }
            guard Int64(chunk.count) <= before.st_size - count else { throw Failure.sourceChanged }
            count += Int64(chunk.count); digest.update(data: chunk)
        }
        guard count == before.st_size, fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.sourceChanged }
        try file.close()
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class PreparationBudget: @unchecked Sendable {
    let limits: PreparedIPA.Limits
    let cancellation: SigningCancellation
    var chargedBytes = 0 // editor is synchronous; never accessed by extraction workers
    private let started: UInt64
    init(limits: PreparedIPA.Limits, cancellation: SigningCancellation) throws {
        guard limits.lifetime.isFinite, limits.lifetime > 0, limits.lifetime <= 3600,
              limits.maximumPreparedBytes > 0, limits.maximumPreparedBytes <= 8 * 1024 * 1024 * 1024,
              limits.maximumCodeFileBytes > 0, limits.maximumCodeFileBytes <= 512 * 1024 * 1024 else { throw PreparedIPA.Failure.invalidLimits }
        self.limits = limits; self.cancellation = cancellation; started = limits.uptime()
    }
    var remaining: TimeInterval {
        let current = limits.uptime()
        guard current >= started else { return 0 }
        return max(0, limits.lifetime - Double(current - started) / 1_000_000_000)
    }
    func check() throws {
        try cancellation.check()
        guard remaining > 0 else { throw PreparedIPA.Failure.expired }
    }
    @discardableResult
    func inspect(tree: URL) throws -> Int {
        var bytes = 0, entries = 0
        var failure: Error?
        guard let walk = FileManager.default.enumerator(at: tree, includingPropertiesForKeys: nil, errorHandler: { _, e in failure = e; return false }) else { throw SigningError.io("cannot inspect preparation scratch") }
        for case let file as URL in walk {
            try check(); entries += 1
            guard entries <= 65_534 else { throw PreparedIPA.Failure.scratchLimit }
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { continue }
            let size = (attrs[.size] as? NSNumber)?.intValue ?? -1
            guard size >= 0, size <= limits.maximumPreparedBytes - bytes else { throw PreparedIPA.Failure.scratchLimit }
            bytes += size
            let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
            let header = try h.read(upToCount: 4) ?? Data()
            if MachO.looksLikeMachO(header), size > limits.maximumCodeFileBytes { throw PreparedIPA.Failure.codeLimit }
        }
        if let failure { throw failure }
        return bytes
    }
    func charge(_ bytes: Int, directory: URL) throws {
        try check()
        guard bytes >= 0, bytes <= limits.maximumPreparedBytes - chargedBytes else { throw PreparedIPA.Failure.scratchLimit }
        chargedBytes += bytes
        let disk = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let free = disk[.systemFreeSize] as? NSNumber else { throw SigningError.io("cannot measure preparation storage") }
        let (required, overflow) = limits.extraction.minimumFreeBytes.addingReportingOverflow(Int64(bytes))
        guard !overflow, free.int64Value >= required else { throw PreparedIPA.Failure.scratchLimit }
    }
    func inspectImports(_ urls: [URL]) throws {
        guard urls.count <= 64 else { throw PreparedIPA.Failure.codeLimit }
        for url in urls {
            try check()
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if attrs[.type] as? FileAttributeType == .typeDirectory { try inspect(tree: url) }
            else {
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      let size = attrs[.size] as? NSNumber, size.int64Value >= 0,
                      size.int64Value <= limits.maximumCodeFileBytes else { throw PreparedIPA.Failure.codeLimit }
            }
        }
    }
}
