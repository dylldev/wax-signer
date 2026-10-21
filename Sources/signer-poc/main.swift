// Prototype command-line signer. macOS only: uses /usr/bin/unzip, /usr/bin/zip and `codesign` (verification).
// Not the production path: the app will use IPAKit + a native archive writer, never external tools.
import CredentialKit
import Foundation
import IPAKit
import SigningKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
let rewrite = args.contains("--rewrite-bundle-id")
args.removeAll { $0 == "--rewrite-bundle-id" }
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}
let appOut = option("--app-out").map { URL(fileURLWithPath: $0) }
let keychainName = option("--keychain-identity")
let p12Option = option("--p12")
let profileOption = option("--profile")

// Positional forms: <in> <out> --keychain-identity <CN> --profile <p> | <in> <out> --p12 <f> --profile <p> |
// legacy <in> <out> <p12> <profile>
var p12Path = p12Option
var profilePath = profileOption
if args.count == 4, keychainName == nil, p12Path == nil { p12Path = args[2]; profilePath = args[3]; args = Array(args.prefix(2)) }
guard args.count == 2, let profilePath, keychainName != nil || p12Path != nil else {
    fail("usage: signer-poc <in.ipa> <out.ipa> (--keychain-identity <common name> | --p12 <file>) --profile <file> "
         + "[--rewrite-bundle-id] [--app-out <dir>]\n"
         + "       a .p12 password is read from the SIGNER_P12_PASSWORD environment variable.\n"
         + "       --keychain-identity signs with a key that stays in the macOS keychain; nothing is exported.")
}
let (inURL, outURL) = (URL(fileURLWithPath: args[0]), URL(fileURLWithPath: args[1]))

/// Finds identities by certificate label in the keychains, keeps the one whose certificate the profile
/// lists, and builds its chain from certificates the system already has. The key never leaves the keychain.
func loadKeychainIdentity(_ label: String, listedBy profile: ProvisioningProfile) throws
    -> (SecurityFrameworkIdentity, teamID: String?, leafDER: Data) {
    var found: CFTypeRef?
    let status = SecItemCopyMatching([
        kSecClass: kSecClassIdentity, kSecAttrLabel: label, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll,
    ] as CFDictionary, &found)
    guard status == errSecSuccess, let candidates = found as? [SecIdentity], !candidates.isEmpty else {
        throw SigningError.keyOperation("no keychain identity labelled \"\(label)\" (status \(status))")
    }
    var seen: [String] = []
    for identity in candidates {
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else { continue }
        let leaf = SecCertificateCopyData(cert) as Data
        let sha1 = X509Fingerprint.sha1(leaf)
        seen.append(sha1)
        guard profile.info.certificateSHA1s.contains(sha1) else { continue }
        let chain = try buildChain(leaf: cert)
        return (try SecurityFrameworkIdentity(identity: identity, additionalCertificatesDER: Array(chain.dropFirst())),
                CertificateSubject.teamID(of: leaf), leaf)
    }
    throw SigningError.keyOperation("none of the \(candidates.count) keychain identit(ies) labelled \"\(label)\" "
        + "is listed by the profile. Found: \(seen.joined(separator: ", ")). Profile lists: "
        + profile.info.certificateSHA1s.joined(separator: ", "))
}

/// Leaf, then each issuer found among the certificates the system keychains hold, until a self-signed root.
func buildChain(leaf: SecCertificate) throws -> [Data] {
    var chain: [SecCertificate] = [leaf]
    for _ in 0..<5 {
        guard let current = chain.last else { break }
        let issuer = SecCertificateCopyNormalizedIssuerSequence(current) as Data?
        let subject = SecCertificateCopyNormalizedSubjectSequence(current) as Data?
        if issuer == subject { break }                       // self-signed: reached the root
        var all: CFTypeRef?
        guard SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll]
                                  as CFDictionary, &all) == errSecSuccess,
              let certs = all as? [SecCertificate],
              let parent = certs.first(where: { (SecCertificateCopyNormalizedSubjectSequence($0) as Data?) == issuer })
        else { break }
        chain.append(parent)
    }
    return chain.map { SecCertificateCopyData($0) as Data }
}

do {
    // 1. archive integrity (independent of everything below)
    let before = try IPAInspector.inspect(url: inURL)
    print("[archive] input OK: \(before.bundleIdentifier) \(before.version) (\(before.entryCount) entries)")

    let profile = try ProvisioningProfile.parse(try Data(contentsOf: URL(fileURLWithPath: profilePath)))
    let signer: SecurityFrameworkIdentity
    let teamID: String?
    let leafDER: Data
    if let keychainName {
        (signer, teamID, leafDER) = try loadKeychainIdentity(keychainName, listedBy: profile)
        print("[identity] keychain: \(keychainName), leaf SHA-1 \(X509Fingerprint.sha1(leafDER)), chain of \(signer.certificateChainDER.count) certificate(s)")
    } else {
        guard let password = ProcessInfo.processInfo.environment["SIGNER_P12_PASSWORD"] else { fail("SIGNER_P12_PASSWORD not set") }
        let loaded = try LoadedIdentity.load(p12: try Data(contentsOf: URL(fileURLWithPath: p12Path!)), password: password)
        signer = try SecurityFrameworkIdentity(identity: loaded.identity)
        (teamID, leafDER) = (loaded.teamID, loaded.certificateDER)
    }
    let identity = signer

    let work = FileManager.default.temporaryDirectory.appendingPathComponent("signer-poc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    try run("/usr/bin/unzip", ["-q", inURL.path, "-d", work.path])
    let payload = work.appendingPathComponent("Payload")
    guard let appName = try FileManager.default.contentsOfDirectory(atPath: payload.path).first(where: { $0.hasSuffix(".app") })
    else { fail("no .app in Payload") }
    let app = payload.appendingPathComponent(appName)

    var options = SigningOptions()
    options.rewriteBundleIdentifier = rewrite
    let result = try BundleSigner.sign(appDirectory: app, identity: identity, certificateTeamID: teamID,
                                       profile: profile, options: options)
    for item in result.items { print("[signed]  \(item.kind.rawValue) \(item.relativePath) id=\(item.identifier) cdhash=\(item.cdHash)") }
    for (old, new) in result.bundleIdentifierChanges.sorted(by: { $0.key < $1.key }) { print("[rewrite] \(old) -> \(new)") }
    for w in result.warnings { print("[warning] \(w)") }

    for s in result.profileSelections {
        print("[profile] \(s.bundlePath) <- \"\(s.profileName)\"  signature: \(s.signatureStatus)")
    }

    try? FileManager.default.removeItem(at: outURL)
    try run("/usr/bin/zip", ["-q", "-r", "-y", outURL.path, "Payload"], cwd: work)

    // Separate results. None of them says the device will install this.
    var failed = false
    let after = try IPAInspector.inspect(url: outURL)
    print("[archive] output structure OK: \(after.bundleIdentifier), \(after.entryCount) entries (file presence only)")

    let check = work.appendingPathComponent("check")
    try run("/usr/bin/unzip", ["-q", outURL.path, "-d", check.path])
    let report = SignatureVerifier.verifyBundle(at: check.appendingPathComponent("Payload/\(appName)"),
                                                expectedSignerSHA1: X509Fingerprint.sha1(leafDER))
    print("[verify]  self-check: \(report.passed ? "passed" : "FAILED") (\(report.checks.count) checks; not Apple's verifier)")
    for f in report.failures { print("[verify]  FAILED \(f.name) \(f.detail)") }
    failed = failed || !report.passed
    print("[device]  installation eligibility: not determined (needs a device)")
    if failed { fail("output was written to \(outURL.path) but did not pass the self-check; do not use it") }
    if let appOut {
        try? FileManager.default.removeItem(at: appOut)
        try FileManager.default.createDirectory(at: appOut.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app, to: appOut)
        print("[app]     \(appOut.path)  (unpacked, for `devicectl device install app`)")
    }
    print("[output]  \(outURL.path)")
} catch {
    fail("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
}

func run(_ tool: String, _ arguments: [String], cwd: URL? = nil) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = arguments
    p.currentDirectoryURL = cwd
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw SigningError.io("\(tool) exited \(p.terminationStatus)") }
}
