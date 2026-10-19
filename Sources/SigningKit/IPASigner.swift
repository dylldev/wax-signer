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

/// IPA in, signed IPA out, entirely with the library: validate, extract, sign, self-check, repack.
/// The self-check and final packaged-byte integrity gate must pass before atomic output replacement.
public enum IPASigner {
    public static func sign(ipa: URL, identity: CodeSigningIdentity, certificateTeamID: String?, profiles: ProfileSet,
                            options: SigningOptions = SigningOptions(), edits: AppEdits = AppEdits(), output: URL, workDirectory: URL,
                            compressChangedFiles: Bool = true, progress: ((SigningProgress) -> Void)? = nil) throws -> IPASigningOutcome {
        let fm = FileManager.default
        guard let leaf = identity.certificateChainDER.first else { throw SigningError.keyOperation("no certificate") }

        // Weights follow measured time (320 MB app): unpack and pack dominate, signing itself is small.
        func stage(_ message: String, _ lo: Double, _ hi: Double, _ f: Double = 0) {
            progress?(SigningProgress(message: message, fraction: lo + (hi - lo) * min(1, max(0, f))))
        }
        stage("Checking the archive…", 0, 0.02)
        let source = try IPAArchiveSession(url: ipa)
        let input = try source.inspect()

        let work = workDirectory.appendingPathComponent("sign-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        stage("Unpacking…", 0.02, 0.40)
        let tree = work.appendingPathComponent("tree", isDirectory: true)
        let inventory = try source.extract(to: tree, byteProgress: { stage("Unpacking…", 0.02, 0.40, $0) })
        let payload = tree.appendingPathComponent("Payload")
        let app = payload.appendingPathComponent(input.appFolder)

        let edited = try AppEditor.applyDetailed(edits, to: app)
        let editNotes = edited.notes
        var signOptions = options
        signOptions.priorRenames = edited.renames
        stage("Signing…", 0.40, 0.52)
        let result = try BundleSigner.sign(appDirectory: app, identity: identity, certificateTeamID: certificateTeamID,
                                           profiles: profiles, options: signOptions)

        stage("Checking the signature…", 0.52, 0.62)
        let expected = try IPAArchiveManifest.capture(directory: tree)
        let report = SignatureVerifier.verifyBundle(at: app, expectedSignerSHA1: X509Fingerprint.sha1(leaf))
        guard report.passed else {
            throw SigningError.selfCheckFailed(report.failures.prefix(5).map { "\($0.name) \($0.detail)" })
        }

        stage("Packing…", 0.62, 1.0)
        var inspected: IPAMetadata?
        try IPAArchiver.archive(directory: tree, to: output, reusing: ipa, compressChangedFiles: compressChangedFiles,
                                byteProgress: { stage("Packing…", 0.62, 1.0, $0) }, reusingExtraction: inventory,
                                verifiedManifest: expected, validateArchive: { inspected = try IPAInspector.inspect(url: $0) })
        guard let after = inspected else { throw IPAError.integrity("packaged archive was not inspected") }
        return IPASigningOutcome(output: output, inputArchive: input, outputArchive: after, signing: result, selfCheck: report, editNotes: editNotes)
    }
}
