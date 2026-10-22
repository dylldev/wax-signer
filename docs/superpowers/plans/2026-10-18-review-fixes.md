# Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding from the 2026-10-17 two-axis code review (Standards + Spec) of the Wax repo: 15 standards findings (6 likely-problematic, 9 nitpicks) and 13 spec findings (7 missing/partial, 3 unspecced, 3 wrong/narrower).

**Architecture:** Three workstreams. (A) Correctness/security: verify one already-fixed finding with evidence, rotate the exposed loopback certificate name, scrub a personal bundle ID. (B) Standards refactors: single sources of truth for nested-bundle enumeration, file keys, ASN.1 OIDs, profile eligibility, zip payload offsets, and install-transport plumbing. (C) Spec gaps: compression levels, library injection settings (folder/path/remove-existing), Sources app page, phone-host failure fallbacks, E2 measurement, doc alignments.

**Tech Stack:** Swift 5.9 packages (IPAKit, CredentialKit, SigningKit, InstallKit, SourcesKit) + SwiftUI app; zlib (iOS SDK module) for deflate levels; Python 3 stdlib HTTP server; bash scripts; XCTest. Build/test on this Mac with `swift test`; app build via generation `xcodegen` + `xcodebuild`.

**Conventions:**
- One commit per task. Commit messages are plain sentences, e.g. `Signer never selects an App Store profile`.
- Refactor tasks keep behavior identical: verification = existing tests stay green (no new test required, but run the named filter). New-behavior tasks use TDD: failing test first, watch it fail, then implement.
- Run commands from the repo root: the repository root.
- Test filter example: `swift test --filter AppEditorTests`. Python: `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`.

**Review finding → task map (self-review coverage check):**

| Finding | Task |
|---|---|
| 4x divergent nested-bundle enumeration | B1 |
| Coverage-key re-derived per file | B2 |
| CMS SignedData parsed twice; OID decode 4x | B3 |
| Two parallel eligibility systems | B4 |
| Zip preamble triplicated | B5 |
| S3Host vs OTA put/verifyReachable duplication | B6 |
| LoopbackHost `head` shadow | C2 |
| IPALibrary dead store | C2 |
| ProgressThrottle double compute | C2 |
| wax_ota.py clock shadow | C1 |
| Bundle ID picker + help copy duplicated | C3 |
| ShareLink rows duplicated | C3 |
| ProfileKind→label switch duplicated | C4 |
| Pass-through wrappers (CertificateValidity/CertificateSubject) | C5 (comment-only; they are the public seam over internal X509Summary) |
| Four local big-endian readers | C6 |
| Tests grouped by review round | C7 |
| Compression level missing | D1 + D2 |
| removeExisting missing | D3 |
| .framework / folder / path in library UI | D3 |
| E2 streamed upload unmeasured | D6 (+ code only if gate passes) |
| Sources app page + description | D4 |
| Phone-host failure offers | D5 |
| Design vs plan profile preference contradiction | D7 |
| Unique final IDs (claimed missing) | A1 (verify-only: already implemented + tested) |
| Feed name is the exposed spike name | A2 |
| Personal bundle ID residuals | A3 |
| Wax Probe test-install unspecced | E1 |
| CI workflow + badge unspecced | E2 |
| Ready-to-install notification unspecced | E3 |

---

## Task 0: Park the plan in the repo

**Files:**
- Create: `docs/superpowers/plans/2026-10-18-review-fixes.md`

- [ ] **Step 1: Copy this plan into the repo**

```bash
mkdir -p docs/superpowers/plans
cp ~/.opencode/plan/2026-10-18-review-fixes.md docs/superpowers/plans/2026-10-18-review-fixes.md
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-10-18-review-fixes.md
git commit -m "Add the review-fix plan"
```

---

## Phase A — Correctness and security

### Task A1: Confirm the unique-final-ID refusal is already in place

The review claimed duplicates among unchanged nested IDs pass silently. Reading the code at HEAD shows the opposite: `BundleSigner.plan()` runs a full uniqueness pass over every planned final ID (`Sources/SigningKit/BundleSigner.swift:248-256`) and `Tests/SigningKitTests/ReviewFixesTests.swift:68` (`testTwoBundlesWithTheSameFinalIdentifierAreRefusedWithBothNamed`) signs a twin-extension app with a wildcard profile (no rewrite) and asserts the refusal names both bundles. This task closes the finding with evidence; no production code changes.

**Files:**
- Test: `Tests/SigningKitTests/ReviewFixesTests.swift` (optional addition only)

- [ ] **Step 1: Run the existing test**

Run: `swift test --filter testTwoBundlesWithTheSameFinalIdentifierAreRefusedWithBothNamed`
Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 2 (optional): Add a rewrite-on characterization test**

Only if you want the rename path covered too. Append to `Tests/SigningKitTests/ReviewFixesTests.swift`:

```swift
func testRenamingTwoExtensionsOntoTheSameIdentifierIsRefused() throws {
    let app = try makeWorkingApp()
    let plugins = app.appendingPathComponent("PlugIns", isDirectory: true)
    let twin = plugins.appendingPathComponent("TwinExt.appex")
    try FileManager.default.copyItem(at: plugins.appendingPathComponent("TestExt.appex"), to: twin)

    var options = SigningOptions()
    options.rewriteBundleIdentifier = true
    options.keepBundleIdentifier = false
    XCTAssertThrowsError(try sign(app, profile: FixtureData.profileExactSingleApp, options: options)) {
        let text = String(describing: $0)
        XCTAssertTrue(text.contains("TestExt.appex"), text)
        XCTAssertTrue(text.contains("TwinExt.appex"), text)
    }
}
```

If `FixtureData.profileExactSingleApp` does not exist, use the exact-single-app fixture already used by `ProfileSelectionTests` for the "keep own bundle ID" tests; if none fits, skip Step 2 and note why in the commit body.

- [ ] **Step 3: Verify**

Run: `swift test --filter ReviewFixesTests`
Expected: all pass.

- [ ] **Step 4: Commit (only if Step 2 was taken)**

```bash
git add Tests/SigningKitTests/ReviewFixesTests.swift
git commit -m "Cover the rename path of the duplicate identifier refusal"
```

### Task A2: Publish the loopback feed under a fresh name

The owner's spike name `<old-name>.example` was exposed in chat and is hardcoded in `Sources/InstallKit/CertificateFeed.swift:23`. Changing the name ships an app update, so do it once, now. This task has an owner part (DuckDNS) and a code part. **The new name is chosen by the owner during this task and substituted literally below — it is the only value in this plan not fixed up front.**

**Files:**
- Modify: `Sources/InstallKit/CertificateFeed.swift:23`
- Modify: `SECURITY.md:33-34`
- Test: `Tests/InstallKitTests/CertificateFeedTests.swift` (no change expected; tests compare against `LoopbackConfig.officialNames` symbolically)

- [ ] **Step 1 (owner): Create the new DuckDNS name**

- In the DuckDNS account, create a new subdomain (suggested: keep the `wax` prefix, e.g. `wax-ota-<random>.duckdns.org`). It must NOT resolve anywhere yet — Wax only accepts the name when it resolves to loopback only.
- In the public GitHub repo settings: Actions → Variables → set `INSTALL_DOMAIN` to the new name (create it if absent).
- Run the `renew-install-cert` workflow once (Actions → renew-install-cert → Run workflow).
- Verify the feed:

```bash
curl -fsS https://<owner>.github.io/<repo>/cert.json | head -c 400
```

Expected: JSON with `"name"` equal to the new host and a fresh `notAfter`.

- [ ] **Step 2: Point the app at the new name**

In `Sources/InstallKit/CertificateFeed.swift` replace the line (currently):

```swift
public static let officialNames: Set<String> = ["<old-name>.example"]
```

with (substitute the new name):

```swift
public static let officialNames: Set<String> = ["<NEW-NAME>.duckdns.org"]
```

- [ ] **Step 3: Update SECURITY.md**

In `SECURITY.md` the "This iPhone" bullet currently reads (line 33-34):

```
The name it uses (`<old-name>.example`) resolves to `127.0.0.1`, and Wax refuses to start unless the name resolves only to loopback. The official feed may publish only that name.
```

Replace the name with the new one. Keep the rest of the sentence.

- [ ] **Step 4: Test**

Run: `swift test --filter CertificateFeedTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/InstallKit/CertificateFeed.swift SECURITY.md
git commit -m "Publish the loopback certificate feed under a fresh name"
```

Migration note to record in the commit body: phones running an older Wax still accept only the old name; they keep working until the shared certificate expires, then need the app update.

### Task A3: Drop the old personal bundle ID from Wax's records

`io.github.dylankirkgirg.wax` is the owner's old personal ID; the repo rule (plan `docs/superpowers/plans/2026-10-17-sources-options-hardening.md:21`) says the repo never carries personal bundle IDs.

**Files:**
- Modify: `Sources/InstallKit/OTA.swift:230`
- Modify: `Tests/InstallKitTests/BundleIDGuardTests.swift:16-24`
- Modify: `docs/superpowers/specs/2026-10-14-direct-install-design.md:168`
- Modify: `docs/superpowers/plans/2026-10-17-sources-options-hardening.md` (the line mentioning the ID, around line 79)

- [ ] **Step 1: Update the guard list**

In `Sources/InstallKit/OTA.swift`, `BundleIDGuard.waxIDs` currently:

```swift
static let waxIDs: Set<String> = [
    "io.github.dylldev.wax",            // current ID
    "io.github.dylankirkgirg.wax",      // older builds (all still mean this is Wax)
    "dev.localsigner.app",
    "dev.localsigner.wax.dev",
]
```

Remove the personal line; keep the comment accurate:

```swift
static let waxIDs: Set<String> = [
    "io.github.dylldev.wax",            // current ID
    "dev.localsigner.app",              // older builds
    "dev.localsigner.wax.dev",
]
```

- [ ] **Step 2: Update the tests**

In `Tests/InstallKitTests/BundleIDGuardTests.swift`:
- `testTheCurrentWaxIDUpdatingItselfIsFine` used `"io.github.dylankirkgirg.wax"` — switch it to `"dev.localsigner.wax.dev"` (already public).
- `testTheRenamedWaxIDAndEveryOlderIDCountsAsWax` loops over four IDs — drop the personal one, leaving `["io.github.dylldev.wax", "dev.localsigner.app", "dev.localsigner.wax.dev"]`.

- [ ] **Step 3: Update the docs**

- `docs/superpowers/specs/2026-10-14-direct-install-design.md:168`: replace the personal ID with `dev.localsigner.wax.dev` (fixture-style).
- `docs/superpowers/plans/2026-10-17-sources-options-hardening.md`: find `io.github.dylankirkgirg.wax` and replace with `dev.localsigner.wax.dev`, or drop the sentence if it only illustrated a personal scenario.

- [ ] **Step 4: Verify nothing personal remains**

Run: `grep -rn "dylankirkgirg" --include='*' .`
Expected: no matches outside `.remember/` and `.git/`.

- [ ] **Step 5: Test and commit**

Run: `swift test --filter BundleIDGuardTests && swift test --filter OTATests`
Expected: all pass.

```bash
git add Sources/InstallKit/OTA.swift Tests/InstallKitTests/BundleIDGuardTests.swift docs/superpowers/specs/2026-10-14-direct-install-design.md docs/superpowers/plans/2026-10-17-sources-options-hardening.md
git commit -m "Drop the old personal bundle ID from Wax's records"
```

---

## Phase B — Standards refactors

Every task in this phase is behavior-preserving. Verification is: the named filter first (fast), then `swift test` (full) at the end of the phase. If a filter fails after an edit, the edit is wrong — fix the edit, never the test.

### Task B1: One enumeration of nested bundles

Today four places enumerate the containers/nested bundles: `BundleSigner.nestedContainers` (:51) + `signableBundles` (:340-351), `SignatureVerifier` inline array (:91), `AppEditor.nestedBundles` (:257-271). They already disagree (AppEditor skips `Frameworks`/`XPCServices`).

**Files:**
- Create: `Sources/SigningKit/BundleLayout.swift`
- Modify: `Sources/SigningKit/BundleSigner.swift` (delete `nestedContainers`; `signableBundles` uses the shared helper)
- Modify: `Sources/SigningKit/SignatureVerifier.swift:91`
- Modify: `Sources/SigningKit/AppEditor.swift:257-271`

- [ ] **Step 1: Create the shared layout**

```swift
import Foundation

/// The places a bundle may contain other code we sign, in the order the signer walks them.
public enum BundleLayout {
    /// Directories inside a bundle that may hold nested code.
    public static let containers = ["Frameworks", "PlugIns", "Extensions", "AppClips", "Watch", "XPCServices"]

    /// Every nested .app/.appex inside `bundle`, deepest paths last, sorted for reproducibility.
    /// Mirrors what the signer signs and the editor renames.
    public static func nestedBundles(in bundle: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        func walk(_ dir: URL) {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in items.sorted(by: { $0.path < $1.path }) {
                switch item.pathExtension {
                case "app", "appex":
                    found.append(item)
                    walk(item)
                case "framework", "xpc":
                    break // never a rename target; the signer handles its executable directly
                default:
                    break
                }
            }
        }
        for container in containers { walk(bundle.appendingPathComponent(container)) }
        return found
    }
}
```

- [ ] **Step 2: Use it in BundleSigner**

Delete the private `nestedContainers` constant (:51) and the body of `signableBundles` (:340-351); replace with:

```swift
static func signableBundles(in app: URL) -> [URL] {
    [app] + BundleLayout.nestedBundles(in: app)
}
```

- [ ] **Step 3: Use it in SignatureVerifier**

Replace the inline array at `SignatureVerifier.swift:91`:

```swift
for container in ["Frameworks", "PlugIns", "Extensions", "AppClips", "Watch", "XPCServices"] {
```

with:

```swift
for container in BundleLayout.containers {
```

- [ ] **Step 4: Use it in AppEditor**

Replace the body of `nestedBundles(in:)` (:257-271) with:

```swift
static func nestedBundles(in app: URL) -> [URL] {
    BundleLayout.nestedBundles(in: app)
}
```

Note the intentional widening: the editor now also sees bundles inside `Frameworks`/`XPCServices` (matching the signer). `.framework`/`.xpc` items are still not rename targets, so existing fixtures behave the same.

- [ ] **Step 5: Test**

Run: `swift test --filter AppEditorTests && swift test --filter SignatureVerifierTests && swift test --filter ProfileSelectionTests`
Expected: all pass (unchanged behavior).

- [ ] **Step 6: Commit**

```bash
git add Sources/SigningKit/BundleLayout.swift Sources/SigningKit/BundleSigner.swift Sources/SigningKit/SignatureVerifier.swift Sources/SigningKit/AppEditor.swift
git commit -m "List nested bundles in one place"
```

### Task B2: One file-key formula

The symlink-resolved key `parent-resolved + last component` is re-derived in `SignatureVerifier.key` (:41-43), `CodeResources.build` walker (:63-64), `BundleSigner.preflight` key (:133-135) and `Context.relative` (:116-120). Drift between these makes "covered by a verified signature" verdicts unsound.

**Files:**
- Create: `Sources/IPAKit/FileKey.swift`
- Modify: `Sources/SigningKit/SignatureVerifier.swift:41-43`
- Modify: `Sources/SigningKit/CodeResources.swift:63-64`
- Modify: `Sources/SigningKit/BundleSigner.swift:133-135`

- [ ] **Step 1: Create the helper**

```swift
import Foundation

/// The identity of a file for signature coverage: parent directory resolved through symlinks,
/// own name kept literal. Two paths that will read the same bytes must produce the same key.
public enum FileKey {
    public static func of(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).path
    }
}
```

- [ ] **Step 2: Replace the copies**

`SignatureVerifier.key(_:)`:

```swift
private func key(_ url: URL) -> String { FileKey.of(url) }
```

`CodeResources.build` walker: replace the `full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path` line with `let full = FileKey.of(url)`.

`BundleSigner.preflight` inner `key(_:)`: delete the local function and call `FileKey.of(url)` at its use sites. Leave `Context.relative` as is — it resolves the root once for relative paths, which is a different computation.

- [ ] **Step 3: Test**

Run: `swift test --filter SignatureVerifierTests && swift test --filter ReviewFixesTests && swift test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/IPAKit/FileKey.swift Sources/SigningKit/SignatureVerifier.swift Sources/SigningKit/CodeResources.swift Sources/SigningKit/BundleSigner.swift
git commit -m "Compute file identity in one place"
```

### Task B3: One ASN.1 OID codec, one CMS parse

OID decode exists in `CMSSignedData.oidString` (:158-167), `X509.oid` (:46-55) and `ASN1.oidString` (PKCS12Modern.swift:116-122); OID encode exists in `CMSSignedData.oidBytes` (:169-179) and `PKCS12Modern.TLV.oid` (:103-112). And `ProfileReader.embeddedContent` (:58-83) re-walks the CMS envelope that `CMSSignedData.parse` already parses.

**Files:**
- Create: `Sources/CredentialKit/ASN1+OID.swift`
- Modify: `Sources/CredentialKit/CMSSignedData.swift:28,62,74,82,158-179`
- Modify: `Sources/CredentialKit/X509.swift:30,46-55`
- Modify: `Sources/CredentialKit/PKCS12Modern.swift:103-112,115-127`
- Modify: `Sources/CredentialKit/ProfileReader.swift:58-83`

- [ ] **Step 1: Create the shared codec**

```swift
import Foundation

extension ASN1 {
    /// Dotted form of DER OID content bytes. Empty input yields "".
    static func oidString(_ b: [UInt8]) -> String {
        guard let first = b.first else { return "" }
        var parts = [Int(first) / 40, Int(first) % 40]
        var v = 0
        for byte in b.dropFirst() {
            v = v << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 { parts.append(v); v = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    /// DER OID content bytes for a dotted string. Malformed input yields [].
    static func oidBytes(_ dotted: String) -> [UInt8] {
        let p = dotted.split(separator: ".").compactMap { Int($0) }
        guard p.count >= 2 else { return [] }
        var out: [UInt8] = [UInt8(p[0] * 40 + p[1])]
        for var v in p.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(v & 0x7f)]
            v >>= 7
            while v > 0 { chunk.insert(UInt8(v & 0x7f) | 0x80, at: 0); v >>= 7 }
            out += chunk
        }
        return out
    }

    /// Dotted form when this node is an OID node.
    var oidString: String? {
        guard tag == 0x06, !content.isEmpty else { return nil }
        return ASN1.oidString(content)
    }

    /// Small non-negative integer content.
    var intValue: Int? {
        guard tag == 0x02, content.count <= 4 else { return nil }
        return content.reduce(0) { $0 << 8 | Int($1) }
    }
}
```

- [ ] **Step 2: Delete the copies and repoint callers**

- `CMSSignedData.swift`: delete `static func oidString` and `private static func oidBytes`. In `parse`(:28) change `oidBytes("1.2.840.113549.1.7.2")` to `ASN1.oidBytes("1.2.840.113549.1.7.2")`; in `parseSigner`(:62,:74,:82) change `oidString(...)` to `ASN1.oidString(...)`.
- `X509.swift`: delete `private static func oid` (:46-55); in `parse` (:30) change `Self.oid(parts[0].content)` to `ASN1.oidString(parts[0].content)`.
- `PKCS12Modern.swift`: replace `DER.oid` body with `tlv(0x06, ASN1.oidBytes(dotted))`; delete the `extension ASN1 { oidString, intValue }` block (:115-127) — it now lives in ASN1+OID.swift.

- [ ] **Step 2b: Replace ProfileReader.embeddedContent**

Replace the whole hand-rolled body (currently `Sources/CredentialKit/ProfileReader.swift:58-83`) with:

```swift
/// The plist inside a signed profile, via the same parser the signature check uses.
static func embeddedContent(of data: Data) throws -> Data {
    let signed: CMSSignedData
    do { signed = try CMSSignedData.parse(data) }
    catch { throw CredentialError.profileNotCMS }
    guard let content = signed.encapsulatedContent else { throw CredentialError.profileNoEmbeddedPlist }
    return content
}
```

Behavior note (deliberate, note it in the commit body): the old code required every constructed-OCTET-STRING chunk to carry tag `0x04`; `CMSSignedData.parse` accepts the chunk contents as-is. No fixture or profile in the wild depends on the stricter check; `ParserTests.testRejectsNonCMS` and `testRejectsCMSWithoutPlist` cover the error mapping.

- [ ] **Step 3: Test**

Run: `swift test --filter CredentialKitTests && swift test --filter ParserTests && swift test --filter PKCS12ModernTests`
Expected: all pass, including `testRejectsNonCMS` (`.profileNotCMS` for the unsigned/truncated fixtures) and `testRejectsCMSWithoutPlist` (`.profileInvalidPlist`).

- [ ] **Step 4: Commit**

```bash
git add Sources/CredentialKit/ASN1+OID.swift Sources/CredentialKit/CMSSignedData.swift Sources/CredentialKit/X509.swift Sources/CredentialKit/PKCS12Modern.swift Sources/CredentialKit/ProfileReader.swift
git commit -m "Decode OIDs and profile content through one parser"
```

### Task B4: One source of truth for profile eligibility

`ProfileSelector.eligibility` (:73-84) and `Compatibility.evaluate` (CredentialKit) answer the same questions separately; `EntitlementsPolicy.permits` (:130-136) and `BundleSigner.rewriteTarget` (:319-337) both interpret application-identifier patterns.

**Files:**
- Create: `Sources/CredentialKit/ProfileFitness.swift`
- Modify: `Sources/SigningKit/Entitlements.swift:130-136`
- Modify: `Sources/SigningKit/BundleSigner.swift:319-337`
- Modify: `Sources/SigningKit/ProfileSelection.swift:73-84`
- Modify: `Sources/CredentialKit/Compatibility.swift` (evaluate)

- [ ] **Step 1: Create the shared predicates and pattern logic**

```swift
import Foundation

extension ProfileInfo {
    public func listsCertificate(sha1: String) -> Bool { certificateSHA1s.contains(sha1) }
    /// True when the certificate's team is unknown or matches.
    public func teamMatches(_ team: String?) -> Bool { team == nil || team == teamID }
    public func runsOnIOS() -> Bool { platforms.isEmpty || platforms.contains("iOS") }
    public var isInstallableKind: Bool { kind != .appStore }
}

/// The one place the application-identifier pattern of a profile is interpreted.
public enum ProfileFitness {
    /// Whether `bundleIdentifier` sits inside this profile's own application identifier.
    public static func permits(bundleIdentifier: String, profileApplicationIdentifier appID: String, teamID: String) -> Bool {
        guard appID.hasPrefix(teamID + ".") else { return false }
        let pattern = appID.dropFirst(teamID.count + 1)
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") { return bundleIdentifier.hasPrefix(String(pattern.dropLast())) }
        return pattern == bundleIdentifier
    }

    /// The identifier the profile forces onto an app, or `original` when the wildcard allows keeping it.
    public static func rewrittenIdentifier(profileApplicationIdentifier appID: String, teamID: String, original: String) -> String {
        guard appID.hasPrefix(teamID + ".") else { return appID }
        let pattern = appID.dropFirst(teamID.count + 1)
        if pattern == "*" { return original }
        if pattern.hasSuffix(".*") {
            let last = original.split(separator: ".").last.map(String.init) ?? original
            return String(pattern.dropLast()) + last
        }
        return String(pattern)
    }
}
```

- [ ] **Step 2: Delegate EntitlementsPolicy.permits**

Replace its body (`Sources/SigningKit/Entitlements.swift:130-136`) with:

```swift
static func permits(profileApplicationIdentifier appID: String, teamID: String, bundleIdentifier: String) -> Bool {
    ProfileFitness.permits(bundleIdentifier: bundleIdentifier, profileApplicationIdentifier: appID, teamID: teamID)
}
```

- [ ] **Step 3: Use the predicates in ProfileSelector.eligibility**

Replace the body of `eligibility` with the same checks expressed through the new predicates (keep the exact rejection cases and order):

```swift
static func eligibility(_ profile: ProvisioningProfile, leafSHA1: String, certificateTeam: String?, now: Date) -> ProfileRejection? {
    if !profile.info.listsCertificate(sha1: leafSHA1) { return .doesNotListCertificate }
    if !profile.info.teamMatches(certificateTeam) { return .teamMismatch }
    if profile.info.isExpired(at: now) { return .expired }
    if !profile.info.isInstallableKind { return .appStoreProfile }
    if !profile.info.runsOnIOS() { return .platformMismatch }
    return nil
}
```

- [ ] **Step 4: Use rewrittenIdentifier in BundleSigner.rewriteTarget**

Inside `rewriteTarget` (`Sources/SigningKit/BundleSigner.swift:319-337`) replace the pattern switch at the end with:

```swift
return ProfileFitness.rewrittenIdentifier(profileApplicationIdentifier: best.info.applicationIdentifier,
                                          teamID: best.info.teamID,
                                          original: main.original)
```

Everything before it (overrides/pool merge, `eligibility == nil` filter, best-by-specificity selection) stays.

- [ ] **Step 5: Compose Compatibility.evaluate from the predicates**

In `Compatibility.evaluate`, re-derive each row from the shared predicates, keeping today's titles and the `unknown` cases:
- "Profile includes this certificate" → `profile.listsCertificate(sha1: certificate.sha1Fingerprint)`.
- "Team ID matches" → `certificate.teamID == nil ? .unknown : (profile.teamMatches(certificate.teamID) ? .pass : .fail)`.
- "Profile not expired" → `profile.isExpired(at: now)`.
- "Device eligibility" → the kind switch, with the App Store branch driven by `profile.isInstallableKind == false`.

- [ ] **Step 6: Test**

Run: `swift test --filter ProfileSelectionTests && swift test --filter SigningTests && swift test --filter CertificateFeedTests`
Expected: all pass (28 profile-selection tests pin the rejection cases).

- [ ] **Step 7: Commit**

```bash
git add Sources/CredentialKit/ProfileFitness.swift Sources/SigningKit/Entitlements.swift Sources/SigningKit/BundleSigner.swift Sources/SigningKit/ProfileSelection.swift Sources/CredentialKit/Compatibility.swift
git commit -m "Ask profile eligibility questions in one voice"
```

### Task B5: One zip payload-offset helper

`ZipArchive` re-reads the 30-byte local header and validates `0x04034b50` in three places: `copyRaw` (:46-58), `data(for:)` (:60-84), `extract` (:89+).

**Files:**
- Modify: `Sources/IPAKit/ZipArchive.swift:46-101`

- [ ] **Step 1: Add the helper (private)**

```swift
/// Offset of the entry's payload after validating the local header. Throws when the archive lies.
private func payloadStart(of entry: ZipEntry) throws -> Int {
    guard let header = read(at: entry.localHeaderOffset, count: 30), header.u32(0) == 0x04034b50 else {
        throw IPAError.corruptEntry(entry.name)
    }
    let start = entry.localHeaderOffset + 30 + Int(header.u16(26)) + Int(header.u16(28))
    guard start + entry.compressedSize <= fileSize else { throw IPAError.corruptEntry(entry.name) }
    return start
}
```

(Adjust `read(at:count:)`/`fileSize` to the exact private helpers already in the file.)

- [ ] **Step 2: Use it in all three places**

- `copyRaw`: keep the method guard, then `let start = try payloadStart(of: entry)`.
- `data(for:)`: same.
- `extract`: same.

- [ ] **Step 3: Test**

Run: `swift test --filter IPAKitTests && swift test --filter ArchiveRoundTripTests && swift test --filter DebExtractorTests`
Expected: all pass, including the corrupt-archive fixtures (error text unchanged).

- [ ] **Step 4: Commit**

```bash
git add Sources/IPAKit/ZipArchive.swift
git commit -m "Validate a zip entry's payload offset in one helper"
```

### Task B6: Shared upload/fetch plumbing for both install hosts

`OTA.put`/`verifyReachable` (:141-183) and `S3Host.put`/`verifyReachable` (:86-106) are the same request dance with different error text. Keep the text, share the plumbing.

**Files:**
- Create: `Sources/InstallKit/InstallTransport.swift`
- Modify: `Sources/InstallKit/OTA.swift:141-183`
- Modify: `Sources/InstallKit/S3Host.swift:86-106`

- [ ] **Step 1: Create the helper**

```swift
import Foundation

/// The one way this app talks to an install host. Error text stays at the call sites.
enum InstallTransport {
    static func send(_ request: URLRequest, session: URLSession) async throws -> (body: Data, code: Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func sendUpload(_ request: URLRequest, file: URL, session: URLSession, delegate: URLSessionTaskDelegate?) async throws -> (body: Data, code: Int) {
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func looksLikeManifest(_ data: Data) -> Bool {
        String(decoding: data.prefix(2048), as: UTF8.self).contains("<plist")
    }
}
```

- [ ] **Step 2: Rewrite OTA.put and OTA.verifyReachable onto it**

`verifyReachable` keeps its exact messages:

```swift
public func verifyReachable(manifest: URL) async throws {
    var r = URLRequest(url: manifest); r.timeoutInterval = 20
    let result: (body: Data, code: Int)
    do { result = try await InstallTransport.send(r, session: session) }
    catch { throw Failure(message: "Could not reach the install server to check the link: \(error.localizedDescription)") }
    guard result.code == 200, InstallTransport.looksLikeManifest(result.body) else {
        throw Failure(message: "The server accepted the upload but the install link is not reachable (HTTP \(result.code)). Check that the server's web folder matches the upload folder.")
    }
}
```

`put` uses `InstallTransport.sendUpload(r, file: file, session: session, delegate: ProgressDelegate(progress))` inside the same do/catch and keeps its 201/401/413/507 switch verbatim.

- [ ] **Step 3: Rewrite S3Host.put and S3Host.verifyReachable onto it**

`put` sends via `InstallTransport.sendUpload` keeping its `S3Host.explain(code, body:)` mapping; `verifyReachable` keeps the bucket messages:

```swift
guard result.code == 200, InstallTransport.looksLikeManifest(result.body) else {
    throw Failure(message: "The bucket stored the files but the install link did not open (HTTP \(result.code)). Check the endpoint and region.")
}
```

- [ ] **Step 4: Test**

Run: `swift test --filter OTATests && swift test --filter S3HostTests && swift test --filter OTALiveTests`
Expected: all pass (OTATests uses a local URLProtocol stub; the JSON/body assertions pin the behavior).

- [ ] **Step 5: Commit**

```bash
git add Sources/InstallKit/InstallTransport.swift Sources/InstallKit/OTA.swift Sources/InstallKit/S3Host.swift
git commit -m "Talk to install hosts through one transport"
```

---

## Phase C — Nitpicks

### Task C1: wax_ota.py clock shadow

**Files:**
- Modify: `Server/wax-ota/wax_ota.py:36`

- [ ] **Step 1: Rename the local clock in gc()**

```python
def gc(root, ttl):
    wall = time.time()
    for name in os.listdir(root):
        p = os.path.join(root, name)
        try:
            if os.path.isdir(p) and wall - os.path.getmtime(p) > ttl:
                shutil.rmtree(p, ignore_errors=True)
        except OSError:
            pass
```

- [ ] **Step 2: Test and commit**

Run: `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`
Expected: all pass.

```bash
git add Server/wax-ota/wax_ota.py
git commit -m "Stop shadowing the server's movable clock in garbage collection"
```

### Task C2: Three one-line cleanups

**Files:**
- Modify: `Sources/InstallKit/LoopbackHost.swift:195` (and uses at :197, :201, :212)
- Modify: `Sources/InstallKit/IPALibrary.swift:26-32`
- Modify: `App/SigningModel.swift:360-371`

- [ ] **Step 1: LoopbackHost**

```swift
let isHead = method == "HEAD"
```

Replace the three uses of the old local `head` with `isHead` (do not touch the `head:` parameter of `respond`).

- [ ] **Step 2: IPALibrary**

Delete the dead assignment `stored = all` (:27); keep only the filtered assignment:

```swift
let all = data.flatMap { try? JSONDecoder().decode([LibraryEntry].self, from: $0) } ?? []
// A file name is a single path component; anything else in a damaged index is ignored, never followed.
stored = all.filter { ... }
```

- [ ] **Step 3: ProgressThrottle**

```swift
func shouldPublish(_ p: SigningProgress) -> Bool {
    let publish = shouldStore(p)
    if publish { last = p }
    return publish
}
```

- [ ] **Step 4: Test and commit**

Run: `swift test --filter LoopbackHostTests && swift test --filter IPALibraryTests`
Expected: all pass.

```bash
git add Sources/InstallKit/LoopbackHost.swift Sources/InstallKit/IPALibrary.swift App/SigningModel.swift
git commit -m "Clear out three one-line leftovers"
```

### Task C3: One bundle-ID picker, one export row

**Files:**
- Create: `App/BundleIDModePicker.swift`
- Modify: `App/SignView.swift:314-320` (ShareLink), `:353-369` (picker block)
- Modify: `App/SettingsView.swift:44-59`

- [ ] **Step 1: Create the picker view**

```swift
import SwiftUI

/// Keep original / Rename to fit, with the same help text everywhere it appears.
struct BundleIDModePicker: View {
    @Binding var mode: SigningModel.BundleIDMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundle ID")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Wax.text)
            Picker("Bundle ID", selection: $mode) {
                Text("Keep original").tag(SigningModel.BundleIDMode.keep)
                Text("Rename to fit").tag(SigningModel.BundleIDMode.rename)
            }
            .pickerStyle(.segmented)
            Text(mode == .keep
                 ? "Signs under the profile's app ID and leaves the app's own ID alone. Recommended."
                 : "Renames the app to fit a profile that allows one app ID. Only needed if iOS refuses the original ID.")
                .font(.footnote)
                .foregroundStyle(Wax.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
```

- [ ] **Step 2: Swap it into SignView and SettingsView**

- SignView detailsSheet: replace the whole bundle ID VStack (`:358-369`) with `BundleIDModePicker(mode: $model.bundleIDMode)`.
- SettingsView: replace the identical block (`:46-57`) with `BundleIDModePicker(mode: $signing.bundleIDMode).padding(.vertical, 12)`.

- [ ] **Step 3: Deduplicate the ShareLink**

Replace the two identical ShareLink branches in `resultCard` (`:314-320`) with one:

```swift
let export = ShareLink(item: r.output) {
    Label("Export signed IPA · \(size)", systemImage: "square.and.arrow.up")
}
if model.readyLink == nil {
    export.buttonStyle(WaxPrimaryButtonStyle())
} else {
    export.buttonStyle(WaxSecondaryButtonStyle())
}
```

(`r` is the report binding in scope; keep the exact label text used today.)

- [ ] **Step 4: Build and commit**

Run: `echo 'import AppKit' >/dev/null; xcodegen generate && xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

```bash
git add App/BundleIDModePicker.swift App/SignView.swift App/SettingsView.swift
git commit -m "Draw the bundle ID choice and export row once"
```

### Task C4: One profile-kind label

`CredentialsView.kind` says "Ad hoc"; `IdentityReadiness.kindLabel` says "Ad Hoc". Move the switch onto `ProfileKind` itself.

**Files:**
- Modify: `Sources/CredentialKit/Models.swift` (add `ProfileKind.title`)
- Modify: `App/CredentialsView.swift:254-261`
- Modify: `App/IdentityReadiness.swift:11-20`

- [ ] **Step 1: Add title to ProfileKind**

```swift
extension ProfileKind {
    public var title: String {
        switch self {
        case .development: "Development"
        case .adHoc: "Ad hoc"
        case .enterprise: "Enterprise"
        case .appStore: "App Store"
        }
    }
}
```

- [ ] **Step 2: Use it**

- `CredentialsView.kind(_:)`: `profile.kind.title`.
- `IdentityReadiness.kindLabel(for:profiles:)`: after finding the first profile with `CompatibilityReport.evaluate(...).hasFailures == false`, return `compatible.kind.title`; keep the no-profile fallback text as is.

- [ ] **Step 3: Build and commit**

Run: `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

```bash
git add Sources/CredentialKit/Models.swift App/CredentialsView.swift App/IdentityReadiness.swift
git commit -m "Name profile kinds in one place"
```

### Task C5: Document the certificate seams (comment-only)

`CertificateValidity`/`CertificateSubject` in `Sources/CredentialKit/SigningInputs.swift:31-49` are not wrappers to delete: `X509Summary` is internal, and these are the public surface other kits and the POC use.

- [ ] **Step 1: Add the comment**

```swift
/// The public face of the internal X.509 reader: date and subject lookups for signing callers.
public enum CertificateValidity { ... }
public enum CertificateSubject { ... }
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CredentialKit/SigningInputs.swift
git commit -m "Say why the certificate lookups are their own types"
```

### Task C6: One big-endian reader set

`MachO.swift:217-230` has unbounded `Data.u32/u64/setU32/setU64`; `FatMachO.swift:16-19`, `BundleSigner.swift:539-543` and `SignatureVerifier.swift:131` each have their own reader.

**Files:**
- Modify: `Sources/SigningKit/MachO.swift:217-230` (add `u32Checked`)
- Modify: `Sources/SigningKit/FatMachO.swift:16-19`
- Modify: `Sources/SigningKit/BundleSigner.swift:539-543`
- Modify: `Sources/SigningKit/SignatureVerifier.swift:131`

- [ ] **Step 1: Add the shared bounded reader**

```swift
func u32Checked(_ o: Int) -> UInt32? {
    guard o >= 0, o + 4 <= count else { return nil }
    return u32(o)
}
```

- [ ] **Step 2: Delete the copies**

- `FatMachO.swift`: delete its local `u32(_:) -> UInt32?`; call `data.u32Checked(...)`.
- `BundleSigner.swift`: delete the private extension `u32BE` (:539-543); replace uses with `data.u32(...)` (its offsets are already validated).
- `SignatureVerifier.swift`: delete the local `be32` (:131); replace uses with `Int(data.u32(...))`.

- [ ] **Step 3: Test and commit**

Run: `swift test --filter FatMachOTests && swift test --filter MachOMalformedTests && swift test --filter SignatureVerifierTests`
Expected: all pass.

```bash
git add Sources/SigningKit/MachO.swift Sources/SigningKit/FatMachO.swift Sources/SigningKit/BundleSigner.swift Sources/SigningKit/SignatureVerifier.swift
git commit -m "Read big-endian fields with one set of helpers"
```

### Task C7: Regroup the round-named test files by behavior

`AuditRegressionTests.swift` and `ReviewFixesTests.swift` are named after review rounds. Move each group to the file that names its subject. Pure moves; test bodies unchanged. Do this task last in Phase C.

**Files:**
- Modify: `Tests/SigningKitTests/AuditRegressionTests.swift`, `Tests/SigningKitTests/ReviewFixesTests.swift`
- Modify: `Tests/SigningKitTests/SignatureVerifierTests.swift`, `AppEditorTests.swift`, `IPASignerTests.swift`, `SigningTests.swift`, `ProfileSelectionTests.swift`
- Modify: `Tests/SigningKitTests/SigningTestSupport.swift` (shared helpers)

- [ ] **Step 1: Move the helpers**

Move these free helpers from `AuditRegressionTests.swift` into `SigningTestSupport.swift`: `sign(_:p12:profile:options:)`, `signedApp()`, `snapshot(_:)`, `le32(_:)`, `syntheticMachO(cryptid:signature:trailer:)`. Keep them internal (same target); if a name clashes, prefix the moved copies and update their callers.

- [ ] **Step 2: Move AuditRegression groups**

- A Encrypted binaries, B Trailing bytes, C Code outside locations, E Signing certificate → `IPASignerTests.swift` (A's verifier-side flag test → `SignatureVerifierTests.swift`).
- D Symlinks → `IPASignerTests.swift`.
- F Profile trust → `ProfileSelectionTests.swift`.
- G Requested-false entitlement → `SigningTests.swift`.
- H/H2 Identifier rewrite → `AppEditorTests.swift`.
- I Verifier malformed containers, Apple-issued chains → `SignatureVerifierTests.swift`.
- Chain completion → `SignatureVerifierTests.swift`.
- The `MARK: - ...` section comments move along and keep their names.

- [ ] **Step 3: Move ReviewFixes tests**

- `testMalformedSignatureBlobsAreRefusedNotTrapped`, `testWellFormedSignatureBlobStillYieldsEntitlements`, `testSymlinkToAnotherDirectoryIsSealedUnderItsOwnPath` → `SignatureVerifierTests.swift` (move `be32` with them).
- `testBundleIDEditAlsoMovesExtensionsFolderBundles`, `testBundleIDEditReportsEveryRename` → `AppEditorTests.swift`.
- `testTwoBundlesWithTheSameFinalIdentifierAreRefusedWithBothNamed` → `IPASignerTests.swift`.
- Custom entitlements MARK (both tests) → `SigningTests.swift`.
- Delete the now-empty source files.

- [ ] **Step 4: Test and commit**

Run: `swift test --filter SigningKitTests`
Expected: same test count as before the move, all pass.

```bash
git add Tests/SigningKitTests
git commit -m "Group the signing tests by what they test"
```

---

## Phase D — Spec gaps

### Task D1: Compression levels in the archive writer

Spec §2 Medium: "compression level (speed, balanced, size)"; plan D2 pins levels 1/6/9. The `Compression` framework only exposes the default level, so deflate moves to zlib (the iOS SDK exports the `zlib` module — `extern module zlib` in `iPhoneOS.sdk/usr/include/module.modulemap` — and `import zlib` compiles).

**Files:**
- Create: `Sources/IPAKit/ArchiveCompression.swift`
- Modify: `Sources/IPAKit/IPAArchiver.swift` (`archive` :11, `writeFile` :180-189, `precompress` :209-216, `deflate` :219-265)

- [ ] **Step 1: Create the level type**

```swift
import Foundation

/// How hard the packer tries. Names the three choices the UI offers.
public enum ArchiveCompression: String, Codable, CaseIterable, Sendable {
    case speed, balanced, size

    /// zlib deflate level.
    public var deflateLevel: Int32 {
        switch self {
        case .speed: 1
        case .balanced: 6
        case .size: 9
        }
    }
}
```

- [ ] **Step 2: Thread the level through the archiver**

- `archive(...)` signature gains `level: Int32 = ArchiveCompression.balanced.deflateLevel` (place it after `reusing:`).
- `precompress(_ url: URL, in tempDirectory: URL, level: Int32)`; call site in the `concurrentPerform` block passes `level`.
- `writeFile(...)` passes `level` to `deflate`.

- [ ] **Step 3: Replace deflate with a zlib implementation**

Keep the return shape and the guards. New body:

```swift
import zlib   // top of file, next to `import Compression`

private static func deflate(_ url: URL, level: Int32, emit write: (Data) throws -> Void) throws -> (crc: UInt32, compressed: Int, uncompressed: Int) {
    let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
    var stream = z_stream()
    let initResult = deflateInit2_(&stream, level, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY,
                                   zlibVersion(), Int32(MemoryLayout<z_stream>.size))
    guard initResult == Z_OK else { throw IPAError.unreadable(url.lastPathComponent) }
    defer { deflateEnd(&stream) }

    var crc = CRC32()
    var compressed = 0, uncompressed = 0
    var out = [UInt8](repeating: 0, count: 256 * 1024)
    var pending = Data()
    var inputDone = false

    while true {
        if pending.isEmpty && !inputDone {
            let chunk = try input.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { inputDone = true } else { pending.append(chunk) }
        }

        let idleBefore = stream.total_out
        pending.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(pending.count)
            repeat {
                stream.next_out = &out
                stream.avail_out = uInt(out.count)
                _ = deflate(&stream, inputDone ? Z_FINISH : Z_NO_FLUSH)
                let produced = out.count - Int(stream.avail_out)
                if produced > 0 { compressed += produced; pending_out.append(contentsOf: out[0..<produced]) }
            } while stream.avail_out == 0
            pending.removeFirst(pending.count - Int(stream.avail_in))
        }
        crc.update(pending-consumed-bytes-as-they-were-freed)   // see note below
        ...
    }
}
```

Do not paste this skeleton blindly — write it as a straight adaptation of the current function:
- read 256 KiB chunks; CRC32 over every input byte consumed (the current function computes the CRC in the read loop — keep that exact structure, it already produces the right value);
- feed zlib with `Z_NO_FLUSH` until input ends, then `Z_NO_FLUSH`+`Z_FINISH` to drain;
- count `uncompressed += consumed`, `compressed += produced`;
- keep the existing zip64 guard (`uncompressed > 4 GiB` → the current error) and the existing stall guard: if three consecutive rounds produce no output and consume no input, throw the current `compression stalled` error;
- collect produced bytes and `try write(...)` — the current function emits small `Data` chunks; do the same per round.

- [ ] **Step 4: Prove it with a test**

Append to `Tests/IPAKitTests/ArchiveRoundTripTests.swift`:

```swift
func testCompressionLevelsChangeTheOutputSizeAndStillRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wax-level-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Highly compressible payload, big enough that levels 1 and 9 differ.
    let payload = Data(String(repeating: "the quick brown fox jumps over the lazy dog 0123456789\n", count: 6_000).utf8)
    try payload.write(to: dir.appendingPathComponent("file.bin"))

    func pack(level: ArchiveCompression) throws -> (url: URL, size: Int) {
        let out = dir.appendingPathComponent("\(level.rawValue).zip")
        try IPAArchiver.archive(directory: dir, to: out, rootFolder: "Payload", reusing: nil, level: level.deflateLevel)
        return (out, try Data(contentsOf: out).count)
    }

    let speed = try pack(level: .speed)
    let size = try pack(level: .size)
    XCTAssertLessThan(size.size, speed.size, "level 9 must beat level 1 on compressible data")

    // Round-trip through the reader.
    let za = try ZipArchive(url: size.url)
    let entry = try XCTUnwrap(za.entries.first { $0.name == "Payload/file.bin" })
    XCTAssertEqual(try za.data(for: entry), payload)
}
```

(Adapt the `ZipArchive` constructor/entry accessors to the file's existing style if they differ.)

- [ ] **Step 5: Run**

Run: `swift test --filter ArchiveRoundTripTests`
Expected: new test fails before Step 3 (`archive` has no `level:` — compile error is the red), passes after. Then: `swift test --filter IPAKitTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/IPAKit/ArchiveCompression.swift Sources/IPAKit/IPAArchiver.swift Tests/IPAKitTests/ArchiveRoundTripTests.swift
git commit -m "Pack at the chosen compression level"
```

### Task D2: Compression choice in the app

**Files:**
- Modify: `Sources/SigningKit/AppEditor.swift` (`AppEdits` :1-100)
- Modify: `Sources/SigningKit/IPASigner.swift:67`
- Modify: `App/SigningOptionsView.swift` ("Changes to every app" panel, after `appearancePicker`)

- [ ] **Step 1: AppEdits gains the field**

- Field: `public var compression: ArchiveCompression?` with doc comment `// Signing choice, kept as a default.`
- `CodingKeys`: add `compression`; in `init(from:)` decode with `decodeIfPresent`.
- `defaultsOnly()`: copy it (it is a default, not per-app state).
- `isEmpty`: ignore it (it never marks an app as edited).
- `IPASigner.swift:67`: pass the level — `try IPAArchiver.archive(directory: tree, to: staged, reusing: ipa, level: (edits.compression ?? .balanced).deflateLevel, byteProgress: { ... })`.

- [ ] **Step 2: Add the picker row**

In `SigningOptionsView`'s "Changes to every app" panel, after `appearancePicker`:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("Compression")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Wax.text)
    Picker("Compression", selection: $model.edits.compression) {
        Text("Balanced").tag(ArchiveCompression?.none)
        Text("Faster").tag(ArchiveCompression?.some(.speed))
        Text("Smaller").tag(ArchiveCompression?.some(.size))
    }
    .pickerStyle(.segmented)
    Text("Faster packs quicker; Smaller spends more time to shrink the download.")
        .font(.footnote)
        .foregroundStyle(Wax.sub)
}
```

(`SigningOptionsView` already imports `SigningKit`; if `ArchiveCompression` lives in IPAKit, add `import IPAKit` or re-export from SigningKit — SigningKit already depends on IPAKit, so make the enum's home `IPAKit` and the file already imports it.)

- [ ] **Step 3: Test**

Run: `swift test --filter IPASignerTests && swift test --filter AppEditorTests`
Expected: all pass.

- [ ] **Step 4: Build and commit**

Run: `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

```bash
git add Sources/SigningKit/AppEditor.swift Sources/SigningKit/IPASigner.swift App/SigningOptionsView.swift
git commit -m "Offer a compression choice when signing"
```

### Task D3: Library injection settings (folder, path, remove existing)

Plan D3 pinned this interface: `InjectionSettings { libraries, folder (.root|.frameworks), path (.executable|.rpath), removeExisting }`. Removal is deferred-weaken, not byte-surgery: the file is deleted and its load command becomes weak (`LC_LOAD_WEAK_DYLIB`), so no Mach-O offset ever shifts. Re-injecting the same library flips the command back to strong. This is a deliberate ceiling — full command removal would require rewriting every file offset in the Mach-O. Mark it with `// ponytail: weak-convert instead of removing the command; upgrade when shrink-and-fix-offsets is needed`.

**Files:**
- Modify: `Sources/SigningKit/MachO.swift:95-165` (add `weakenLoadDylib`; upgrade path in `addLoadDylib`)
- Modify: `Sources/SigningKit/LibraryInjector.swift` (whole flow)
- Modify: `Sources/SigningKit/AppEditor.swift` (`AppEdits` + call site :200-202)
- Modify: `App/SigningOptionsView.swift:193-267`
- Modify: `App/DocumentPicker.swift`
- Test: `Tests/SigningKitTests/LibraryInjectorTests.swift`, `Tests/SigningKitTests/AppEditorTests.swift:102-109`

- [ ] **Step 1: MachO — weaken and upgrade**

Add:

```swift
/// Marks a loaded dylib weak in place. Returns true when a command was changed.
public func weakenLoadDylib(_ name: String) -> Bool {
    for off in commands(of: [Self.lcLoadDylib, Self.lcLoadWeakDylib]) {
        if dylibName(at: off) == name {
            data.setU32(off, Self.lcLoadWeakDylib)
            return true
        }
    }
    return false
}
```

In `addLoadDylib`, before the current "already present" early return, add the upgrade: if a **weak** command matches `name`, retype it to strong and return:

```swift
if let off = commands(of: [Self.lcLoadWeakDylib]).first(where: { dylibName(at: $0) == name }) {
    data.setU32(off, Self.lcLoadDylib)
    return
}
if commands(of: [Self.lcLoadDylib]).contains(where: { dylibName(at: $0) == name }) { return }
```

- [ ] **Step 2: InjectionSettings refactor in LibraryInjector**

```swift
/// Where libraries land and how they are wired. Per-app choices.
public struct InjectionSettings: Equatable {
    public enum Folder: String, Codable, CaseIterable { case root, frameworks }
    public enum PathStyle: String, Codable, CaseIterable { case executable, rpath }

    public var libraries: [URL]
    public var folder: Folder
    public var path: PathStyle
    public var removeExisting: Bool

    public init(libraries: [URL], folder: Folder = .frameworks, path: PathStyle = .rpath, removeExisting: Bool = false) {
        self.libraries = libraries; self.folder = folder; self.path = path; self.removeExisting = removeExisting
    }
}

public static func inject(_ settings: InjectionSettings, into app: URL) throws -> [String] {
    // same preflight as today (readInfo, CFBundleExecutable, encrypted refusal)
    // destination directory: settings.folder == .frameworks ? app/Frameworks : app
    // load-name prefix: settings.path == .rpath ? "@rpath/" : "@executable_path/<folder>/"
    // removeExisting pass before adding: delete "*.dylib" in the destination directory
    //   (excluding the files being injected) and call exe.weakenLoadDylib(name) for each;
    //   delete the file, keep the (now weak) command.
    // everything else unchanged: all addLoadDylib calls before any write, copy, perms, notes.
}
```

Keep `inject(_ libraries:into:)` as a thin forwarder (`inject(InjectionSettings(libraries: libraries), into: app)`) so nothing else breaks.

- [ ] **Step 3: AppEdits + AppEditor**

- `AppEdits` gains `injectionFolder: InjectionSettings.Folder?`, `injectionPath: InjectionSettings.PathStyle?`, `removeExisting: Bool` — per-app like `injectLibraries` (NOT in CodingKeys; `init(from:)` defaults them; `defaultsOnly()` does not copy them).
- Call site (`AppEditor.swift:200-202`) becomes:

```swift
if !edits.injectLibraries.isEmpty || edits.removeExisting {
    notes.append(contentsOf: try LibraryInjector.inject(
        InjectionSettings(libraries: edits.injectLibraries,
                          folder: edits.injectionFolder ?? .frameworks,
                          path: edits.injectionPath ?? .rpath,
                          removeExisting: edits.removeExisting),
        into: app))
}
```

- [ ] **Step 4: UI**

In `SigningOptionsView.libraryPanel` (and its sheet):
- Add a folder segmented picker ("Frameworks" / "App root") bound to `model.edits.injectionFolder` via a non-optional binding (map nil → `.frameworks`), and a path picker ("@rpath" / "@executable_path").
- Add a toggle `Remove existing libraries` bound to `$model.edits.removeExisting`.
- The library sheet's `DocumentPicker` gains `types: [.item, .folder]`; update `keepLibrary` to accept `.framework` directories: if the picked URL is a directory, keep it as-is (copy the folder into the temp dir, preserving the name); if a file, keep the current extension guard (`dylib`, `framework`, `deb`).
- Update the note text: "Adds .dylib files, .framework folders, or the .dylib files inside a .deb. Choose whether they land in Frameworks/ or the app root, and remove existing libraries before adding."

In `DocumentPicker.swift`, add `let types: [UTType]` with `init(types: [UTType] = [.item], onPick:)` so existing callers compile unchanged; use `types` in `UIDocumentPickerViewController(forOpeningContentTypes:)`.

- [ ] **Step 5: Tests**

In `LibraryInjectorTests.swift`: update the seven `inject([lib], into: app)` call sites to `inject(InjectionSettings(libraries: [lib]), into: app)`. Keep existing tests green, then add:

```swift
func testRemoveExistingDeletesTheFilesAndWeakensTheirCommands() throws {
    // build an app, inject mock.dylib, then run with removeExisting and no new libraries
    // assert: Frameworks/mock.dylib is gone; the main executable no longer has a strong mock.dylib command
}

func testReinjectingAfterRemovalMakesTheCommandStrongAgain() throws {
    // run the removal pass, inject mock.dylib again, assert the command is strong and the file is back
}

func testFolderAndPathChoicesChangeLoadNames() throws {
    // inject with folder .root, path .executable; assert destination and command name
}
```

Fill the bodies using the file's existing fixture builders (read the file first; reuse `makeApp()`/`fixture` helpers and its test app on disk). In `AppEditorTests.swift:102-109`, update the call path to the new `inject(_ settings:into:)` shim and run.

Assertions can use `MachO.loadDylibNames` and `MachO.commands(of:)` — both exist and are public within the target.

- [ ] **Step 6: Test and commit**

Run: `swift test --filter LibraryInjectorTests && swift test --filter AppEditorTests && swift test --filter SigningTests`
Expected: all pass.

```bash
git add Sources/SigningKit/MachO.swift Sources/SigningKit/LibraryInjector.swift Sources/SigningKit/AppEditor.swift App/SigningOptionsView.swift App/DocumentPicker.swift Tests/SigningKitTests/LibraryInjectorTests.swift Tests/SigningKitTests/AppEditorTests.swift
git commit -m "Choose where injected libraries land and clear the old ones"
```

### Task D4: Sources app page

Spec §1: the app row shows "icon, name, version, size, description, Get". Today the row shows no description and there is no app page (`App/SourcesView.swift:156-178`).

**Files:**
- Create: `App/SourceAppDetailView.swift`
- Modify: `App/SourcesView.swift:106-201`

- [ ] **Step 1: Create the detail view**

```swift
import SwiftUI
import SourcesKit

/// The app page behind a Sources row: everything the source lists, with one Get button.
struct SourceAppDetailView: View {
    let app: SourceApp
    let progress: Double?
    let isDone: Bool
    let get: (SourceApp) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    AsyncImage(url: app.iconURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "app.dashed").font(.system(size: 36)).foregroundStyle(Wax.sub)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title3.weight(.semibold)).foregroundStyle(Wax.text)
                        if !app.developer.isEmpty {
                            Text(app.developer).font(.subheadline).foregroundStyle(Wax.sub)
                        }
                        Text(meta).font(.footnote).foregroundStyle(Wax.sub)
                    }
                    Spacer()
                }
                .padding()
                .waxPanel()

                if !app.summary.isEmpty {
                    Text(app.summary)
                        .font(.subheadline)
                        .foregroundStyle(Wax.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .waxPanel()
                }

                getButton
                Spacer()
            }
            .padding()
            .background(Wax.bg)
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private var meta: String {
        [app.version, app.size.map(Self.sizeText)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var getButton: some View {
        Button { get(app) } label: {
            HStack {
                if let progress { ProgressView(value: progress).frame(width: 20) }
                Text(isDone ? "Downloaded" : "Get")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(progress != nil || isDone)
        .buttonStyle(WaxPrimaryButtonStyle())
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

Match the exact `waxPanel()`/theme API in `Theme.swift` (use `WaxPanel` if panels are views, not modifiers). Reuse `SourcesView.getButton`'s size formatting if it exists (`size` may already be a formatted `String?`).

- [ ] **Step 2: Show the description in the row and open the page**

In `SourceAppsView`:
- Add `@State private var detailApp: SourceApp?`.
- Under the name in `appRow`, add `if !app.summary.isEmpty { Text(app.summary).font(.footnote).foregroundStyle(Wax.sub).lineLimit(2) }`.
- Make the row content tappable: `.contentShape(Rectangle()).onTapGesture { detailApp = app }` (keep the existing Get button as is).
- Add `.sheet(item: $detailApp) { app in SourceAppDetailView(app: app, progress: model.downloads[app.id], isDone: model.filed.contains(app.id), get: { app in model.get(app, from: sourceID, signAfter: ..., library: ..., signing: ..., router: ...) }) }` — pass the same arguments the row's Get button already uses (copy them from `getButton`).

- [ ] **Step 3: Build and commit**

Run: `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

```bash
git add App/SourceAppDetailView.swift App/SourcesView.swift
git commit -m "Open a Sources app page with the full description"
```

### Task D5: Phone-host failure offers a way forward

Spec §6: when the loopback install fails, Wax "says so and offers the other hosts (own server, cloud bucket) or Export." Today `SignView.errorCard` shows text only.

**Files:**
- Modify: `App/SignView.swift:333-343`

- [ ] **Step 1: Extend errorCard**

```swift
private func errorCard(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Wax.bad)
            Text(text).font(.subheadline).foregroundStyle(Wax.text)
        }
        if case .failed = ota.state, ota.hostKind == .phone, let output = model.report?.output {
            HStack(spacing: 10) {
                Button("Use my server") { ota.hostKind = .server }
                Button("Use a bucket") { ota.hostKind = .bucket }
                ShareLink(item: output) { Text("Export signed IPA") }
            }
            .font(.footnote.weight(.semibold))
        }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Wax.badBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityLabel("Problem. \(text)")
}
```

(Adapt the styling lines to the current `errorCard`; keep its existing padding/background/accessibility choices.)

- [ ] **Step 2: Build and commit**

Run: `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

```bash
git add App/SignView.swift
git commit -m "Offer the other hosts when the phone transfer fails"
```

### Task D6: Measure packing vs upload on a real device (E2 gate)

Plan E2's own first step: time packing and upload, run the 320 MB Chess IPA on the phone, record both numbers; only build streamed upload if upload is ≥ 30% of the total.

**Files:**
- Modify: `Sources/SigningKit/IPASigner.swift` (outcome + timing)
- Modify: `App/SigningModel.swift` (`sign: ok` log line)
- Modify: `docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md` (record numbers)

- [ ] **Step 1: Carry packSeconds in the outcome**

In `IPASigningOutcome` add `public let packSeconds: Double`. At the archive call, measure:

```swift
let packStarted = Date()
try IPAArchiver.archive(directory: tree, to: staged, reusing: ipa, byteProgress: { stage("Packing…", 0.62, 1.0, $0) })
let packSeconds = Date().timeIntervalSince(packStarted)
```

and pass it into the returned outcome.

- [ ] **Step 2: Log it**

In `SigningModel` where `sign: ok items=... bytes=...` is written, append `pack=\(Int(outcome.packSeconds)) s`. Upload is already logged (`ota: uploaded in Xs`).

- [ ] **Step 3: Test**

Run: `swift test --filter IPASignerTests`
Expected: all pass.

- [ ] **Step 4: Device measurement (owner)**

Install this build on the phone, sign the 320 MB Chess IPA with the phone host, then read the log:

1. Wax → Settings → the import log screen (or Files app → Wax → wax-import.log).
2. Copy the two lines: `sign: ok ... pack=NN s` and `ota: uploaded in NN s`.

Record both numbers in `docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md` under the E2 paragraph (line ~44), as: `2026-10-18 measurement: pack NN s, upload NN s (NN% of total) on <device> with the 320 MB Chess IPA.`

- [ ] **Step 5: Decide the gate, then commit**

If upload < 30% of total: add one sentence to the same paragraph — `Streamed upload is not worth it at this ratio; E2 is closed.` If ≥ 30%: keep E2 open, and this task ends with the paragraph unchanged except the numbers.

```bash
git add Sources/SigningKit/IPASigner.swift App/SigningModel.swift docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md
git commit -m "Measure packing and upload before deciding on streamed upload"
```

### Task D7: Align the design doc with the plan on profile preference

The hardening design (line 29) says the signer should "prefer profiles that include this phone"; the implemented plan (`docs/superpowers/plans/2026-10-17-sources-options-hardening.md`, plan step A4) explicitly put that out of scope, and the design's own §89-90 explains why the phone cannot be identified (no UDID access). Align the design doc with the plan; implement nothing.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md:29`

- [ ] **Step 1: Edit the line**

Current text: `1. Signer ignores profile kind: never pick an App Store profile; prefer profiles that include this phone.`

New text: `1. Signer ignores profile kind: never pick an App Store profile. (Preferring profiles that include this phone is out of scope: the app cannot see the device UDID, so it cannot tell which profiles include it — see the ipa-signer design.)`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md
git commit -m "Match the design doc to the shipped profile rules"
```

---

## Phase E — Document the unspecced surfaces

### Task E1: Document the Wax Probe test install

**Files:**
- Modify: `docs/superpowers/specs/2026-10-13-real-device-test-plan.md` (add a final section)

- [ ] **Step 1: Append the section**

```markdown
## 7. Wax Probe: the in-app test install

The Credentials screen can prove a certificate end-to-end without the owner leaving Wax:

- `IdentityTester` (App/IdentityReadiness.swift) signs the bundled `WaxProbe.ipa` with the chosen identity and keeps its own bundle ID (`io.github.dylldev.wax.probe`).
- The signed probe goes through the currently selected install host (phone loopback, own server, or bucket) via the normal `OTAInstallModel.upload` path.
- Wax opens the returned install link; the probe app, when opened by iOS, calls back `waxprobe://` with `installed` or `failed`.
- The result lands in `InstallTestStore` and is shown as the identity-readiness line on the Sign screen.

This flow exists because the alternative — signing and installing a large third-party IPA — makes a failed certificate take much longer to diagnose.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-10-13-real-device-test-plan.md
git commit -m "Document the Wax Probe test install"
```

### Task E2: Document the CI workflow

**Files:**
- Modify: `docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md` (add a section)
- Modify: `README.md:3` (only if the badge is missing)

- [ ] **Step 1: Append the section**

```markdown
## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main`/`master` and every pull request, on `macos-26` runner:

1. `swift test` — all Swift packages.
2. `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'` — the upload server.
3. `bash scripts/test_make_install_cert.sh` — the certificate tooling.
4. `bash scripts/test_publish_prep.sh` — the publish prep script.
5. `brew install xcodegen && xcodegen generate` then `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` — the app compiles unsigned.

The README badge mirrors this workflow on the public repo.
```

- [ ] **Step 2: Check the badge**

Run: `head -3 README.md`
Expected: line 3 contains the CI badge image linked to the repo's actions page. If missing, add:

```markdown
[![CI](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml/badge.svg)](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml)
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md README.md
git commit -m "Document continuous integration"
```

### Task E3: Document the ready-to-install notification

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-direct-install-design.md` (add a section)

- [ ] **Step 1: Append the section**

```markdown
## Ready-to-install notifications

When Wax hands an install link to iOS while the app is in the background, the owner may miss the system prompt. Wax therefore posts a local notification, "Wax is ready to install <app>", and remembers the pending link:

- `InstallInbox` (App/BackgroundJob.swift) holds the link and an `openedFromNotification` flag; `SignView` observes it and re-opens the install flow when the owner returns from the notification.
- The notification is only posted when the app is not in the foreground (`BackgroundJob.notifyIfInBackground`), and only for the `readyToInstall` step; a finished export-only sign posts nothing.
- Notifications are requested through the normal iOS permission prompt the first time; refusing it changes nothing else.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-10-14-direct-install-design.md
git commit -m "Document the ready-to-install notification"
```

---

## Self-review (completed when this plan was written)

1. **Spec/standards coverage:** every review finding maps to a task (table at the top; Standards findings 15/15, Spec findings 13/13 — one closed as verify-only with evidence, three unspecced surfaces documented rather than removed).
2. **Placeholder scan:** the only deferred value is the new DuckDNS name in Task A2 (chosen by the owner during the task, substituted literally at Steps 2-3 — the surrounding code and commands are complete). The deflate rewrite in Task D1 names exact keep-behaviors (CRC, guards, error text) and Step 4 pins the observable contract with a test.
3. **Type consistency:** `ArchiveCompression` (IPAKit) → `deflateLevel: Int32` → `archive(..., level:)` → `AppEdits.compression` → picker; `InjectionSettings {libraries, folder, path, removeExisting}` defined in D3 Step 2 and used in D3 Steps 3-4; `FileKey.of(_:)`, `BundleLayout.nestedBundles(in:)`, `ProfileFitness.permits/rewrittenIdentifier`, `InstallTransport.send/sendUpload/looksLikeManifest`, `BundleIDModePicker(mode:)`, `IPASigningOutcome.packSeconds` — names and signatures match across tasks.
4. **Ordering:** Phase B before Phase D where D2/D3 build on the refactored call sites; C7 (test regrouping) lands after all new tests exist.

**Execution handoff:** plan complete. Run it with subagent-driven-development (fresh subagent per task, review between tasks) or executing-plans (inline, checkpoints). Both need an agent switch: this session is in Plan mode and cannot edit source files.

---

# Post-execution corrections (2026-10-18)

Recorded after running the fixes. The review that produced this plan reported 24 findings. Four of them were wrong and were **not** "fixed". They are listed here so a later reader does not re-raise them as open bugs.

## Findings that were false positives

| Finding | Claim | What was actually true |
|---|---|---|
| Standards #6 | The comparator in `Sources/SourcesKit/SourceParser.swift:130-137` orders sources wrongly | Traced all four cases of `max(by:)`: `(nil, date?)` returns true, `(date?, nil)` falls through to `a.offset > b.offset` = false, `(nil, nil)` returns false and keeps the earlier index. Every case matches the comment above it. No change made. |
| Spec #2 | Install keys are never rotated | `scripts/make-install-cert.sh:12` uses `HOME_DIR="$(mktemp -d)"` with `--force`, so a fresh key IS produced every run. The comment at :5 says so. The real latent defect is a fresh ACME **account** each run, which burns Let's Encrypt's per-IP account limit on shared Actions runners — that is Task A2's actual subject. |
| Spec #11 | `.framework` cannot be picked | `LibraryInjector` already handles `case "framework":` and `Tests/SigningKitTests/LibraryInjectorTests.swift:81-88` already tests it. The gap was three characters of UI validation at `App/SigningOptionsView.swift`. |
| Standards #9 | `DebExtractor.swift:99` silently yields empty `Data` for truncated input | The `guard let base = ... else { return }` branch is **unreachable**: `Data().withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }` is never nil, verified for both an empty `Data` and an empty slice. Empty and truncated payloads already threw. The dead branch was changed to `throw bad` for clarity — no behaviour change — and two regression tests were added to pin it. |

## Deviations from the plan

- **T2 added an entropy check.** `OTASessionID.make()` refuses all-zero entropy as well as a non-`errSecSuccess` status. This was not in the plan. `SECURITY.md` calls that value the only thing protecting a download link, so a generator that reports success and returns a constant must not publish a guessable secret.
- **T11 was scoped down.** The plan called for one shared pump. Only the stream plumbing (`CompressionStream`) was shared; each call site's loop, CRC and byte accounting were kept, because they differ in direction, chunk size, error type and what they count. A single generic loop over all three would have been worse code. Measured: compression suites ran 0.923-0.942s before and 0.927s after.
- **T1 did not rename the DuckDNS name.** The name was removed from the repository instead: `WAX_DEFAULT_FEED` and `WAX_INSTALL_DOMAIN` now come from the built Info.plist, and an empty value degrades to "no official feed" rather than to a stale hostname. **The release build must set both**, or the "This iPhone" install option ships with no feed.

## Testing gaps that are structural, not oversights

`Package.swift` defines no `App` target. `App/` exists only in the Xcode project (`project.yml`), so every change under `App/` — the `.framework` picker, the `HostKind` label table, the phone-host fallback message — ships without unit-test coverage. Only the `SigningKit` half of the appearance change is tested.
