import CredentialKit
import CryptoKit
import Foundation
import IPAKit

public struct SigningOptions {
    /// If a bundle identifier is not permitted by any candidate profile, rewrite it (and the identifiers of
    /// extensions beneath it) to fit the best profile instead of failing.
    public var rewriteBundleIdentifier = false
    /// Leave every bundle identifier as it is and sign under any eligible profile, even one whose application
    /// identifier names a different app. The entitlements then carry the profile's own application identifier.
    /// This is what other signers do with a fixed-ID profile; iOS decides at install time whether it accepts it.
    public var keepBundleIdentifier = false
    /// Bundle IDs already changed before signing (by `AppEditor`), old to new. Entitlements named after the old
    /// IDs (keychain and app groups) follow them, the same as for a rename the signer makes itself.
    public var priorRenames: [String: String] = [:]
    /// Entitlements to request for the main app when its executable carries none.
    public var requestedEntitlements: [String: Any]?
    /// A chosen entitlements set that replaces what the main app asks for. Only what the profile grants is kept.
    public var overrideEntitlements: [String: Any]?
    public var entitlementPolicy: EntitlementMismatchPolicy = .dropAndWarn
    public var now = Date()
    public init() {}
}

public struct SignedItem: Equatable {
    public enum Kind: String { case app, appExtension, framework, bundle, dylib }
    public let relativePath: String
    public let identifier: String
    public let kind: Kind
    /// First 20 bytes of the SHA-256 CodeDirectory hash, hex.
    public let cdHash: String
    /// Name of the profile embedded in this bundle, nil for frameworks and loose dylibs.
    public let profileName: String?
    /// Keys of the entitlements this item was signed with, sorted. Empty for frameworks and dylibs.
    public let entitlementKeys: [String]
}

public struct SigningResult {
    public var items: [SignedItem] = []
    public var warnings: [String] = []
    public var bundleIdentifierChanges: [String: String] = [:]
    public var profileSelections: [ProfileSelection] = []
}

/// Signs an unpacked `.app` directory in place. This is a prototype: thin arm64 Mach-O, SHA-256 only.
/// It produces signatures; it does not verify them. Verification is a separate step.
///
/// Everything that can be decided without touching the files (identifiers, profiles, entitlements) is
/// decided first, so a refusal leaves the app directory unmodified.
public enum BundleSigner {
    /// Single-profile convenience. Behaves as before: the one profile must serve every bundle that needs one.
    public static func sign(appDirectory: URL, identity: CodeSigningIdentity, certificateTeamID: String?,
                            profile: ProvisioningProfile, options: SigningOptions = SigningOptions()) throws -> SigningResult {
        try sign(appDirectory: appDirectory, identity: identity, certificateTeamID: certificateTeamID,
                 profiles: ProfileSet(single: profile), options: options)
    }

    public static func sign(appDirectory: URL, identity: CodeSigningIdentity, certificateTeamID: String?,
                            profiles: ProfileSet, options: SigningOptions = SigningOptions()) throws -> SigningResult {
        guard let leaf = identity.certificateChainDER.first else { throw SigningError.keyOperation("no certificate") }
        let leafSHA1 = Insecure.SHA1.hash(data: leaf).map { String(format: "%02X", $0) }.joined()

        // The signing certificate's own validity is independent of any profile and is checked first.
        if let v = CertificateValidity.dates(of: leaf) {
            if options.now > v.notAfter { throw SigningError.certificateExpired(v.notAfter) }
            if options.now < v.notBefore { throw SigningError.certificateNotYetValid(v.notBefore) }
        } else {
            throw SigningError.bundle("signing certificate validity period cannot be read")
        }

        var ctx = Context(identity: identity, profiles: profiles, options: options, rootURL: appDirectory,
                          leafSHA1: leafSHA1, certificateTeamID: certificateTeamID)
        try ctx.preflight()
        try ctx.plan()
        // Validate all inputs before changing any binary in the app tree.
        ctx.result.warnings.append(contentsOf: try FatMachO.thinTree(at: appDirectory))
        try ctx.signBundle(at: appDirectory, kind: .app)
        return ctx.result
    }

    // MARK: -

    private struct Planned {
        var identifier: String
        var profile: ProvisioningProfile
        var requested: [String: Any]
    }

    private struct Context {
        let identity: CodeSigningIdentity
        let profiles: ProfileSet
        let options: SigningOptions
        let rootURL: URL
        let leafSHA1: String
        let certificateTeamID: String?
        var result = SigningResult()
        /// Final identifiers by bundle directory path (only where changed).
        var newIdentifiers: [String: String] = [:]
        /// Profile, identifier and requested entitlements per signable bundle, keyed by directory path.
        var planned: [String: Planned] = [:]
        var trustCache: [UUID: ProfileSignatureStatus] = [:]

        init(identity: CodeSigningIdentity, profiles: ProfileSet, options: SigningOptions, rootURL: URL,
             leafSHA1: String, certificateTeamID: String?) {
            self.identity = identity; self.profiles = profiles; self.options = options; self.rootURL = rootURL
            self.leafSHA1 = leafSHA1; self.certificateTeamID = certificateTeamID
        }

        /// Team written into every CodeDirectory. All usable profiles share the certificate's team.
        var signingTeamID: String? {
            certificateTeamID ?? profiles.pool.first?.info.teamID ?? profiles.overrides.values.first?.info.teamID
        }

        func relative(_ url: URL) -> String {
            let root = rootURL.resolvingSymlinksInPath().path
            let path = url.resolvingSymlinksInPath().path
            return path == root ? "." : String(path.dropFirst(root.count + 1))
        }

        // MARK: Preflight (read-only): refuse anything that would make the output invalid or unsafe

        /// Checks the whole app tree before anything is planned or written:
        /// - no symlink may point outside the app, and the files we write to must not be symlinks;
        /// - every Mach-O file must be code we know how to sign (a bundle executable or a dylib in a
        ///   container directory), otherwise it would ship unsigned;
        /// - FairPlay-encrypted binaries are refused rather than mangled (universal binaries were thinned before this).
        func preflight() throws {
            let fm = FileManager.default
            let root = rootURL.resolvingSymlinksInPath().path
            var handled = Set<String>()
            func rel(_ url: URL) -> String {
                let k = FileKey.of(url)
                return k == root ? "." : String(k.dropFirst(root.count + 1))
            }

            func bundles(in bundle: URL, kind: String) throws {
                let info = bundle.appendingPathComponent("Info.plist")
                guard let plist = (try? Data(contentsOf: info)).flatMap({ try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }),
                      let exe = plist["CFBundleExecutable"] as? String else { return }
                handled.insert(FileKey.of(bundle.appendingPathComponent(exe)))
                for container in BundleLayout.containers {
                    let dir = bundle.appendingPathComponent(container)
                    for item in ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []) {
                        switch item.pathExtension {
                        case "framework", "appex", "app": try bundles(in: item, kind: item.pathExtension)
                        case "dylib": handled.insert(FileKey.of(item))
                        default: break
                        }
                    }
                }
            }
            try bundles(in: rootURL, kind: "app")

            guard let walker = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                                             options: []) else { throw SigningError.io("cannot read \(rootURL.path)") }
            let writeTargets: Set<String> = ["embedded.mobileprovision", "CodeResources", "_CodeSignature", "Info.plist"]
            for case let url as URL in walker {
                let rel = rel(url)
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                if values.isSymbolicLink == true {
                    let dest = url.resolvingSymlinksInPath().path
                    guard dest == root || dest.hasPrefix(root + "/") else {
                        throw SigningError.bundle("symlink \(rel) points outside the app (\(dest))")
                    }
                    if writeTargets.contains(url.lastPathComponent) || handled.contains(FileKey.of(url)) {
                        throw SigningError.bundle("\(rel) is a symbolic link; the signer writes this file and will not follow links")
                    }
                    continue
                }
                guard values.isRegularFile == true, let h = try? FileHandle(forReadingFrom: url) else { continue }
                let head = (try? h.read(upToCount: 4)) ?? Data()
                try? h.close()
                guard MachO.looksLikeMachO(head) else { continue }

                guard handled.contains(FileKey.of(url)) else {
                    throw SigningError.bundle("unsupported code location: \(rel) is a Mach-O file outside the "
                        + "bundle executables and container dylibs, so it would ship unsigned")
                }
                let macho: MachO
                do { macho = try MachO(FatMachO.thin(Data(contentsOf: url))) } catch let e as SigningError {
                    throw SigningError.machO("\(rel): \(e.errorDescription ?? "unreadable")")
                }
                if macho.isEncrypted {
                    throw SigningError.machO("\(rel) is FairPlay-encrypted (cryptid != 0); a re-signed copy cannot run. Decrypt it first")
                }
            }
        }

        // MARK: Planning (no file is modified here)

        mutating func plan() throws {
            let bundles = Self.signableBundles(in: rootURL)
            var infos: [(url: URL, original: String, requested: [String: Any])] = []
            for url in bundles {
                let id = (try infoPlist(at: url)["CFBundleIdentifier"] as? String) ?? ""
                guard !id.isEmpty else { throw SigningError.bundle("\(relative(url)): Info.plist has no CFBundleIdentifier") }
                var requested = existingEntitlements(try MachO(FatMachO.thin(Data(contentsOf: executableURL(of: url))))) ?? [:]
                if requested.isEmpty, url.path == rootURL.path { requested = options.requestedEntitlements ?? [:] }
                if url.path == rootURL.path, let chosen = options.overrideEntitlements { requested = chosen }
                infos.append((url, id, requested))
            }
            guard let main = infos.first else { throw SigningError.bundle("no app bundle") }

            // Identifier rewrite: only if no candidate can sign the main app under its current identifier.
            var newMain = main.original
            if try select(for: main.url, identifier: main.original, requested: main.requested, throwing: false) == nil {
                guard options.rewriteBundleIdentifier, let target = try rewriteTarget(for: main) else {
                    // Raises the specific reason; nothing else can happen here.
                    _ = try select(for: main.url, identifier: main.original, requested: main.requested, throwing: true)
                    throw SigningError.bundle("no usable provisioning profile for the main app")
                }
                newMain = target
                newIdentifiers[main.url.path] = newMain
                result.bundleIdentifierChanges[main.original] = newMain
            }

            // Every final identifier is decided before any entitlement is rewritten, so references between
            // bundles (a group named after another extension) see the complete rename map.
            var finals: [String: String] = [:]
            for info in infos {
                var finalID = info.original
                if info.url.path == main.url.path {
                    finalID = newMain
                } else if newMain != main.original {
                    // The first identifier a profile permits wins; when none does, the best guess goes on and
                    // the per-bundle selection below raises the specific reason, naming this bundle.
                    let candidates = NestedIdentifier.candidates(original: info.original, mainOriginal: main.original, newMain: newMain)
                    finalID = try candidates.first(where: { candidate in
                        if finals.values.contains(candidate) { return false }
                        return try select(for: info.url, identifier: candidate, requested: info.requested, throwing: false) != nil
                    }) ?? candidates[0]
                    if finals.values.contains(finalID) {
                        throw SigningError.bundle("re-labelling would give two bundles the same identifier (\(finalID)); sign with a wildcard profile instead")
                    }
                    if finalID != info.original {
                        newIdentifiers[info.url.path] = finalID
                        result.bundleIdentifierChanges[info.original] = finalID
                    }
                }
                finals[info.url.path] = finalID
            }

            // However the identifiers came about (renames here, or ID edits before signing), no two bundles may share one.
            var owner: [String: URL] = [:]
            for info in infos {
                let id = finals[info.url.path] ?? info.original
                if let other = owner[id] {
                    throw SigningError.bundle("\(relative(other)) and \(relative(info.url)) would both be identifier \(id). Remove one of them or give them different IDs.")
                }
                owner[id] = info.url
            }

            for info in infos {
                let finalID = finals[info.url.path] ?? info.original
                let requested = EntitlementsPolicy.rewriteBundleScoped(info.requested, renames: options.priorRenames.merging(result.bundleIdentifierChanges) { _, signer in signer })
                guard let chosen = try select(for: info.url, identifier: finalID, requested: requested, throwing: true) else {
                    continue
                }
                planned[info.url.path] = Planned(identifier: finalID, profile: chosen.profile, requested: requested)
                var selection = ProfileSelection(
                    bundlePath: relative(info.url), bundleIdentifier: finalID, profileName: chosen.profile.info.name,
                    profileID: chosen.profile.info.id, rejected: chosen.rejected)
                let id = chosen.profile.info.id
                let status = trustCache[id] ?? ProfileTrust.evaluate(chosen.profile.rawData)
                trustCache[id] = status
                selection.signatureStatus = status
                result.profileSelections.append(selection)
            }
        }

        /// Chooses the profile for one bundle. With `throwing`, a failure raises a specific error.
        private func select(for url: URL, identifier: String, requested: [String: Any],
                            throwing: Bool) throws -> (profile: ProvisioningProfile, rejected: [(profile: String, reason: String)])? {
            let path = relative(url)
            var rejected: [(String, String)] = []
            var compatible: [ProfileSelector.Candidate] = []

            let considered = profiles.overrides[path].map { [$0] } ?? profiles.pool
            var firstRejections: [ProfileRejection] = []
            for p in considered {
                if let why = ProfileSelector.rejection(p, bundleIdentifier: identifier, requested: requested, leafSHA1: leafSHA1,
                                                       certificateTeam: certificateTeamID, now: options.now,
                                                       policy: options.entitlementPolicy,
                                                       ignoreApplicationIdentifier: options.keepBundleIdentifier) {
                    rejected.append((p.info.name, why.description))
                    firstRejections.append(why)
                } else {
                    compatible.append(.init(
                        profile: p,
                        unmet: EntitlementsPolicy.unmet(requested: requested, profile: p.entitlements, teamID: p.info.teamID),
                        specificity: ProfileSelector.specificity(of: p.info)))
                }
            }
            if let best = ProfileSelector.best(compatible) { return (best.profile, rejected) }
            guard throwing else { return nil }

            if considered.count == 1, let why = firstRejections.first, let only = considered.first {
                switch why {
                case .doesNotListCertificate: throw SigningError.profileDoesNotListCertificate
                case .teamMismatch(let p, let c): throw SigningError.profileTeamMismatch(profile: p, certificate: c)
                case .applicationIdentifierMismatch(let p, _):
                    throw SigningError.appIdentifierMismatch(bundle: path, id: identifier, profile: p)
                default: throw SigningError.profileRejected(bundle: path, profile: only.info.name, reason: why.description)
                }
            }
            throw SigningError.noCompatibleProfile(
                bundle: path, id: identifier,
                reasons: considered.isEmpty ? ["no provisioning profiles were supplied"]
                    : rejected.map { "\($0.0): \($0.1)" })
        }

        /// Identifier to use for the main app when its own is not permitted: the most specific profile that
        /// passes every other check decides it.
        private func rewriteTarget(for main: (url: URL, original: String, requested: [String: Any])) throws -> String? {
            let considered = profiles.overrides[relative(main.url)].map { [$0] } ?? profiles.pool
            let usable = considered.filter {
                ProfileSelector.eligibility($0, leafSHA1: leafSHA1, certificateTeam: certificateTeamID, now: options.now) == nil
            }
            guard let best = usable.min(by: { a, b in
                let sa = ProfileSelector.specificity(of: a.info), sb = ProfileSelector.specificity(of: b.info)
                if sa != sb { return sa < sb }
                // Same specificity: the same choice on every run (the UUID is random per import).
                return (a.info.name, a.info.bundleIdentifierPattern, a.info.id.uuidString)
                    < (b.info.name, b.info.bundleIdentifierPattern, b.info.id.uuidString)
            }) else { return nil }
            return ProfileFitness.rewrittenIdentifier(profileApplicationIdentifier: best.info.applicationIdentifier,
                                                      teamID: best.info.teamID, original: main.original)
        }

        /// The app and every application or extension bundle beneath it, main app first.
        static func signableBundles(in app: URL) -> [URL] {
            [app] + BundleLayout.nestedBundles(in: app)
        }

        // MARK: Signing

        mutating func signBundle(at bundle: URL, kind: SignedItem.Kind) throws {
            // 1. nested code first: its final bytes are sealed into this bundle's CodeResources
            for container in BundleLayout.containers {
                let dir = bundle.appendingPathComponent(container)
                let items = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                    .sorted { $0.path < $1.path }
                for item in items {
                    switch item.pathExtension {
                    case "framework": try signBundle(at: item, kind: .framework)
                    case "appex": try signBundle(at: item, kind: .appExtension)
                    case "app": try signBundle(at: item, kind: .app)
                    case "dylib": try signLooseDylib(item)
                    default: break
                    }
                }
            }

            // 2. identifier rewrite and profile embedding
            var plist = try infoPlist(at: bundle)
            var plistChanged = false
            if let new = newIdentifiers[bundle.path] {
                let old = plist["CFBundleIdentifier"] as? String ?? ""
                plist["CFBundleIdentifier"] = new
                // Background task identifiers must start with the bundle ID, so they follow a rename.
                if !old.isEmpty, let ids = plist["BGTaskSchedulerPermittedIdentifiers"] as? [String] {
                    plist["BGTaskSchedulerPermittedIdentifiers"] = ids.map { $0.hasPrefix(old + ".") ? new + $0.dropFirst(old.count) : $0 }
                }
                plistChanged = true
            }
            // Cross-references between a Watch app, its extension and the parent app follow renamed identifiers.
            let renames = result.bundleIdentifierChanges
            if let companion = plist["WKCompanionAppBundleIdentifier"] as? String, let new = renames[companion] {
                plist["WKCompanionAppBundleIdentifier"] = new
                plistChanged = true
            }
            if var ext = plist["NSExtension"] as? [String: Any], var attrs = ext["NSExtensionAttributes"] as? [String: Any],
               let target = attrs["WKAppBundleIdentifier"] as? String, let new = renames[target] {
                attrs["WKAppBundleIdentifier"] = new
                ext["NSExtensionAttributes"] = attrs
                plist["NSExtension"] = ext
                plistChanged = true
            }
            if plistChanged { try writeInfoPlist(plist, at: bundle) }
            guard let identifier = plist["CFBundleIdentifier"] as? String,
                  let executableName = plist["CFBundleExecutable"] as? String else {
                throw SigningError.bundle("\(relative(bundle)): Info.plist lacks CFBundleIdentifier or CFBundleExecutable")
            }
            let executableURL = bundle.appendingPathComponent(executableName)
            guard FileManager.default.fileExists(atPath: executableURL.path) else {
                throw SigningError.bundle("\(relative(bundle)): executable \(executableName) is missing")
            }

            // 3. profile and entitlements (applications and extensions only; frameworks get neither)
            var entitlements: [String: Any]?
            var profileName: String?
            if let plan = planned[bundle.path] {
                try plan.profile.rawData.write(to: bundle.appendingPathComponent("embedded.mobileprovision"))
                profileName = plan.profile.info.name
                let resolved = EntitlementsPolicy.resolve(
                    requested: plan.requested, profile: plan.profile.entitlements, teamID: plan.profile.info.teamID,
                    resolvedApplicationIdentifier: options.keepBundleIdentifier && !plan.profile.info.bundleIdentifierPattern.contains("*")
                        ? plan.profile.info.applicationIdentifier : plan.profile.info.teamID + "." + identifier)
                entitlements = resolved.entitlements
                for key in resolved.dropped {
                    result.warnings.append("\(relative(bundle)): entitlement \(key) is not granted by profile "
                                           + "\"\(plan.profile.info.name)\" and was removed")
                }
            }

            // 4. seal resources, then sign the executable
            let resources = try CodeResources.build(bundleRoot: bundle, executable: executableName)
            let sigDir = bundle.appendingPathComponent("_CodeSignature", isDirectory: true)
            try FileManager.default.createDirectory(at: sigDir, withIntermediateDirectories: true)
            try resources.write(to: sigDir.appendingPathComponent("CodeResources"))

            let infoData = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
            let cdhash = try signExecutable(
                at: executableURL, identifier: identifier, teamID: planned[bundle.path]?.profile.info.teamID ?? signingTeamID, infoPlist: infoData, codeResources: resources,
                entitlements: entitlements)
            result.items.append(SignedItem(relativePath: relative(bundle), identifier: identifier, kind: kind, cdHash: cdhash,
                                           profileName: profileName, entitlementKeys: (entitlements ?? [:]).keys.sorted()))
        }

        mutating func signLooseDylib(_ url: URL) throws {
            let cdhash = try signExecutable(at: url, identifier: url.lastPathComponent, teamID: signingTeamID, infoPlist: nil,
                                            codeResources: nil, entitlements: nil)
            result.items.append(SignedItem(relativePath: relative(url), identifier: url.lastPathComponent, kind: .dylib,
                                           cdHash: cdhash, profileName: nil, entitlementKeys: []))
        }

        func signExecutable(at url: URL, identifier: String, teamID: String?, infoPlist: Data?, codeResources: Data?,
                            entitlements: [String: Any]?) throws -> String {
            let original = try MachO(Data(contentsOf: url))

            let requirements = Requirements.designated(identifier: identifier, chainDER: identity.certificateChainDER)
            var specials: [Int: Data] = [2: sha256(requirements)]
            if let infoPlist { specials[1] = sha256(infoPlist) }
            if let codeResources { specials[3] = sha256(codeResources) }

            var entitlementBlobs: [(UInt32, Data)] = []
            var getTaskAllow = false
            if let entitlements {
                let xml = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
                let xmlBlob = Blob.wrap(Blob.entitlementsXML, xml)
                let derBlob = Blob.wrap(Blob.entitlementsDER, try EntitlementsDER.encode(entitlements))
                specials[5] = sha256(xmlBlob)
                specials[7] = sha256(derBlob)
                entitlementBlobs = [(Blob.Slot.entitlementsXML, xmlBlob), (Blob.Slot.entitlementsDER, derBlob)]
                getTaskAllow = (entitlements["get-task-allow"] as? Bool) == true
            }

            func buildSignature(for image: MachO) throws -> Data {
                let directory = CodeDirectory(
                    identifier: identifier, teamIdentifier: teamID, codeLimit: image.signedLength,
                    execSegmentBase: image.textFileOffset, execSegmentLimit: image.textFileSize,
                    execSegmentFlags: (image.fileType == MachO.executeFileType ? CodeDirectory.execMainBinary : 0)
                        | (getTaskAllow ? CodeDirectory.execAllowUnsigned : 0),
                    specialHashes: specials)
                let cd = directory.build(image: image.data)
                let cms = try CMS.detachedSignature(over: cd, identity: identity, now: options.now)
                let entries: [(slot: UInt32, blob: Data)] =
                    [(Blob.Slot.codeDirectory, cd), (Blob.Slot.requirements, requirements)]
                    + entitlementBlobs.map { ($0.0, $0.1) }
                    + [(Blob.Slot.cms, Blob.wrap(Blob.cmsWrapper, cms))]
                return Blob.superBlob(magic: Blob.embeddedSignature, entries: entries)
            }

            // The signature's size must be known before the headers (which are hashed) are final.
            var probe = original
            try probe.prepareForSignature(size: 0)
            let size = try buildSignature(for: probe).count

            var image = original
            try image.prepareForSignature(size: size)
            let signature = try buildSignature(for: image)
            guard signature.count == size else { throw SigningError.machO("signature size changed between passes") }
            try image.attach(signature: signature)
            try image.data.write(to: url)

            return Self.cdHashHex(signature: signature)
        }

        private static func cdHashHex(signature: Data) -> String {
            // SuperBlob: slot 0 is the CodeDirectory at the offset in the first index entry.
            let offset = Int(signature.u32BE(16))
            let length = Int(signature.u32BE(offset + 4))
            let cd = signature[offset..<(offset + length)]
            return SHA256.hash(data: cd).prefix(20).map { String(format: "%02x", $0) }.joined()
        }

        private func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }

        // MARK: Plist helpers

        private func executableURL(of bundle: URL) throws -> URL {
            guard let name = try infoPlist(at: bundle)["CFBundleExecutable"] as? String else {
                throw SigningError.bundle("\(relative(bundle)): Info.plist has no CFBundleExecutable")
            }
            return bundle.appendingPathComponent(name)
        }

        private func infoPlist(at bundle: URL) throws -> [String: Any] {
            let url = bundle.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { throw SigningError.bundle("\(relative(bundle)): missing or invalid Info.plist") }
            return plist
        }

        private func writeInfoPlist(_ plist: [String: Any], at bundle: URL) throws {
            let url = bundle.appendingPathComponent("Info.plist")
            var format = PropertyListSerialization.PropertyListFormat.xml
            _ = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: &format)
            try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0).write(to: url)
        }

        /// Entitlements already present in an executable's signature (XML slot), if any.
        private func existingEntitlements(_ macho: MachO) -> [String: Any]? {
            guard let sig = macho.existingSignature, sig.offset >= 0, sig.size >= 12, sig.offset + sig.size <= macho.data.count else { return nil }
            return BlobReader.entitlements(inSignature: macho.data[sig.offset..<(sig.offset + sig.size)])
        }
    }
}

private extension Data {
    func u32BE(_ o: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[startIndex + o + $1]) }
    }
}
