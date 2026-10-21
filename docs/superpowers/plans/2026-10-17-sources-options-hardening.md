# Sources, Options, Robustness, Open-Source Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make signing and installing fail less, add a Sources tab and the ESign/Feather signing options, let people without a server install through a free cloud bucket, and make the repo safe to publish.

**Architecture:** Pure logic stays in the Swift packages (`SigningKit`, `CredentialKit`, `InstallKit`, plus a new `SourcesKit`) with unit tests; SwiftUI screens in `App/` stay thin. The server (`Server/wax-ota/wax_ota.py`) stays a small stdlib Python service with its own unittest suite. Each phase (A to G) ships working software.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), XCTest via `swift test`, XcodeGen (`project.yml`), CryptoKit, URLSession, Python 3 stdlib + unittest, Caddy.

**Spec:** `docs/superpowers/specs/2026-10-17-sources-options-hardening-design.md`

## Task template (applies to every task)
Each task is: write the named tests (Step 1), run them and see them fail for the right reason (Step 2), implement the signature given (Step 3), run them green plus `swift test` for the whole package (Step 4), commit with the given message plus the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (Step 5). Run: `swift test --filter <TestClass>` for one class; server tests: `python3 -m unittest Server/wax-ota/test_wax_ota.py`; app build: `xcodegen generate && xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. App-layer tasks (SwiftUI) have no unit tests; their verification step is the build plus a simulator screenshot plus the stated device check.

## Global Constraints
- Everything stays free: no paid service, API, or dependency; Apache-2.0-compatible code only; a helper library is added only after its license file is read.
- Wax ships with NO sources, built in or suggested. Users paste URLs; saved sources live only in the app's own storage.
- Tab order left to right: Sources, IPA, Sign, Settings (Credentials lives inside Settings, already done).
- Install token minimum is 32 characters everywhere (app, setup line, server).
- The repo must never contain the owner's server address, team IDs, personal bundle IDs, tokens, keys or phone IDs; tests use `example.test` and fixture IDs.
- Signing must not regress: `swift test` green and a real-phone check (sign + install the keeper) after phases A, B, D, F.
- Plain, honest copy: never say "no card needed"; never claim an install works until an install was tried.

## Review Focus
1. A source file with odd content (app with no versions, null size, duplicate bundle IDs, 17 MB, HTML instead of JSON): lists only apps with a download, never crashes, never corrupts the cache. Pinned in Task C1 and C2.
2. A download that dies midway or fills the disk: no partial file on the shelf. Pinned in Task C3.
3. Injecting into an app that is encrypted, has no room in its Mach-O header, or is already signed: clear refusal, original untouched. Pinned in Task D3.
4. Cloud bucket with wrong region, expired keys or clock skew: a message naming the cause, no half-uploaded files left. Pinned in Task F2.
5. A server that is up but misconfigured (Caddy root mismatch): upload says success but the link 404s. Pinned in Task B1.

---

## Phase A: small wins

### Task A1: Token minimum 32
**Files:** Modify `Sources/InstallKit/OTA.swift:163`, `App/OTAInstallModel.swift:40`; Test `Tests/InstallKitTests/OTASetupTests.swift`.
**Interfaces:** Produces `OTASetup.minimumTokenLength: Int` (= 32, public static let).
- Tests: `testTokenOf31CharactersIsRejected`, `testTokenOf32CharactersIsAccepted` (via `OTASetup.parse("WAXINSTALL1 https://h.example <token>")`; existing fixtures use 32).
- Implement: replace both literal `16` checks with `OTASetup.minimumTokenLength`; message "That token is too short (needs 32 or more characters)."
- Commit: `Install token must be 32+ characters, matching the server`

### Task A2: Keychain readable after first unlock
**Files:** Modify `Sources/CredentialKit/IdentityKeychain.swift:38,47`, `Sources/InstallKit/SecretStore.swift`; Test `Tests/CredentialKitTests/SystemKeychainTests.swift`, `Tests/InstallKitTests/SecretStoreTests.swift`.
**Interfaces:** Produces `IdentityKeychain.migrateAccessibility()` and `SecretStore.migrateAccessibility()` (no args, no return; call once at app launch from `LocalIPASignerApp.init`).
- Tests: `testNewItemsAreAfterFirstUnlock` (save, `SecItemCopyMatching` with `kSecReturnAttributes`, assert `kSecAttrAccessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); `testMigrationUpgradesAnOldItem` (create an item with `WhenUnlockedThisDeviceOnly`, migrate, assert new value).
- Implement: constants to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; migration uses `SecItemUpdate` on the existing query.
- Commit: `Keychain items readable after first unlock so background signing survives a locked phone`

### Task A3: Server TTL 6 hours
**Files:** Modify `Server/wax-ota/wax_ota.py` (default TTL), `Server/wax-ota/README.md`; Test `Server/wax-ota/test_wax_ota.py`.
- Tests: `test_gc_keeps_a_five_hour_old_folder`, `test_gc_removes_a_seven_hour_old_folder`; `test_ttl_zero_is_refused_at_startup` (main refuses TTL below 60).
- Implement: default `WAX_OTA_TTL=21600`; `main()` validates TTL >= 60 and quota values > 0 and exits with a clear message.
- Commit: `Server keeps uploads 6 hours and refuses nonsense settings`
- Deploy step (needs the owner's yes): copy to the VM, set `Environment=WAX_OTA_TTL=21600` in the unit, `systemctl restart wax-ota`, check 401 on a token-less PUT.

### Task A4: Never pick an App Store profile
**Files:** Modify `Sources/SigningKit/ProfileSelection.swift` (`ProfileSelector.eligibility`); Test `Tests/SigningKitTests/ProfileSelectionTests.swift`, fixtures `Tests/CredentialKitTests/generate_fixtures.py` (add `profileAppStore`).
**Interfaces:** `eligibility` keeps returning `String?` (nil = usable); new non-nil text "App Store profile: apps signed with it cannot be installed outside the App Store."
- Tests: `testAppStoreProfileIsNotEligible`, `testDevelopmentProfileStillWinsOverAnAppStoreProfileForTheSameCertificate` (pool of both; `best` picks the development one).
- Implement: reject `info.kind == .appStore`; prefer profiles listing this phone is out of scope here.
- Commit: `Signer never selects an App Store profile`

### Task A5: Manifest bundle-version from the build number
**Files:** Modify `App/SigningModel.swift` (`InstallTarget` creation), `App/InstallSection.swift` (`InstallTarget`), `Sources/InstallKit/OTA.swift` (`OTAUploader.upload`); Test `Tests/InstallKitTests/OTATests.swift`.
**Interfaces:** `InstallTarget` gains `build: String`; `OTAUploader.upload(... version:, build:, ...)`; the manifest's `bundle-version` is `build` when non-empty else `version`.
- Tests: `testManifestUsesBuildNumberWhenPresent`, `testManifestFallsBackToVersionWhenBuildIsEmpty` against `OTAManifest.build(bundleIdentifier:bundleVersion:title:ipaURL:)`.
- Commit: `Install manifest advertises the build number`

### Task A6: Do not delete the old output before the new one is in place
**Files:** Modify `Sources/SigningKit/IPASigner.swift` (end of `sign`); Test `Tests/SigningKitTests/IPASignerTests.swift`.
- Tests: `testSigningTwiceReplacesTheOutput` (second run's file size/CRC differs, valid IPA); `testExistingOutputSurvivesWhenReplacementFails` (make the destination folder read-only after staging by passing an `output` inside a non-writable directory for the second run; assert first file bytes unchanged).
- Implement: `fm.replaceItemAt(output, withItemAt: staged)` when output exists, else `moveItem`.
- Commit: `Keep the previous signed IPA until the new one is written`

### Task A7: Guard the signed-input install path
**Files:** Modify `App/SigningModel.swift` (`signAndInstall`, the `else` branch).
- Implement: before using `signedInputTarget`, call `BundleIDGuard.replacesRunningWax(originalID: target.bundleIdentifier, finalID: target.bundleIdentifier, runningID: Bundle.main.bundleIdentifier)` and `ota.block(BundleIDGuard.explanation)` on true.
- Verify: build; simulator: pick an IPA whose ID equals the running Wax's (the 0.10.1 IPA with the keeper's ID is not needed; use a fixture IPA edited to `io.github.dylankirkgirg.wax`), no certificate chosen, tap Sign & Install, expect the explanation.
- Commit: `Guard replacing the running Wax on the install-as-is path`

### Task A8: Final bundle IDs must be unique
**Files:** Modify `Sources/SigningKit/BundleSigner.swift` (`plan()`), Test `Tests/SigningKitTests/AuditRegressionTests.swift`.
- Tests: `testTwoExtensionsThatEndUpWithTheSameIDAreRefusedWithBothNamed` (copy the fixture appex twice into `PlugIns` with IDs `com.a.widget` and `com.vendor.widget`, sign with `rewriteBundleIdentifier = true`; expect `SigningError.bundle` text containing both original IDs).
- Implement: after `finals` is built (including `options.priorRenames`), throw if two bundles share a final ID, naming both.
- Commit: `Refuse signing when two bundles would share an identifier`

## Phase B: install robustness

### Task B1: Prove the link works, and test the token
**Files:** Modify `Sources/InstallKit/OTA.swift` (`OTAUploader`), `App/OTAInstallModel.swift`, `Server/wax-ota/wax_ota.py`; Test `Tests/InstallKitTests/OTATests.swift` (URLProtocol stub pattern already there), `Server/wax-ota/test_wax_ota.py`.
**Interfaces:** Produces `OTAUploader.verifyReachable(manifest: URL) async throws` (GET, requires 200 and `text/xml`/`application/xml`/`application/x-plist` content type, else throws `OTAError.linkNotReachable(status:)` with text "The server accepted the upload but the install link is not reachable (HTTP n). Check the web root matches the upload folder."); `OTAUploader.checkToken() async throws` (GET `ota-up/health` with Bearer; 204 ok, 401 `OTAError.badToken`); server route `GET /health` returns 204 with a valid token, 401 otherwise.
- Tests: stubbed 404 manifest throws `linkNotReachable(status: 404)`; stubbed 200 passes; stubbed 401 on health throws `badToken`; server: `test_health_requires_token`.
- Implement: `upload` calls `verifyReachable` after the manifest PUT; `OTAInstallModel.saveToken()` calls `checkToken` and shows the result.
- Commit: `Verify the install link after upload and test the token when it is saved`

### Task B2: Import every identity in a .p12
**Files:** Modify `Sources/CredentialKit/PKCS12Reader.swift:52`, `Sources/CredentialKit/CredentialStore.swift` (`importCertificate`), `App/CredentialsModel.swift`; Test `Tests/CredentialKitTests/PKCS12ModernTests.swift`, fixture `generate_fixtures.py` (`p12TwoIdentities`).
**Interfaces:** `CredentialStore.importCertificates(p12: Data, password: String) throws -> [CertificateInfo]` (keeps `importCertificate` as a wrapper that returns the first, for existing tests); `PKCS12Reader.read` returns `[ReadIdentity]`; `CredentialError.multipleIdentities` is no longer thrown.
- Tests: `testTwoIdentityP12ImportsBoth` (both listed, distinct SHA-1), `testSingleIdentityP12BehavesAsBefore`, `testDuplicateIdentityIsNotImportedTwice`.
- Commit: `Import every identity found in a .p12`

### Task B3: Extension ID fallback
**Files:** Create `Sources/SigningKit/NestedIdentifier.swift`; Modify `Sources/SigningKit/BundleSigner.swift:222-226` and `Sources/SigningKit/AppEditor.swift:101-103`; Test `Tests/SigningKitTests/NestedIdentifierTests.swift`.
**Interfaces:** Produces `enum NestedIdentifier { static func candidates(original: String, mainOriginal: String, newMain: String) -> [String] }`, ordered: full suffix after the main's own prefix (`newMain + "." + suffix` when `original.hasPrefix(mainOriginal + ".")`), then `newMain + "." + lastComponent`, then `original` unchanged.
- Tests: `testPrefixedExtensionKeepsItsFullSuffix` (`com.foo.app.share.ext` with main `com.foo.app` to `T.vendor.app` gives `T.vendor.app.share.ext` first); `testUnrelatedExtensionTriesLastComponentThenOriginal`; `testCandidatesAreUnique`.
- Implement: `BundleSigner.plan` picks the first candidate a profile permits (via `select`), throws only if none, naming the bundle and the permitted pattern; `AppEditor` uses the first candidate.
- Commit: `Try several identifiers for nested bundles before giving up`

### Task B4: Fat Mach-O files (thin to arm64)
**Files:** Create `Sources/SigningKit/FatMachO.swift`; Modify `Sources/SigningKit/MachO.swift:29`, `Sources/SigningKit/BundleSigner.swift` (preflight and signExecutable); Test `Tests/SigningKitTests/FatMachOTests.swift`.
**Interfaces:** Produces `enum FatMachO { static func thin(_ data: Data) throws -> Data }` returning the arm64 slice (cpusubtype 0), else arm64e (subtype 2), else throws `SigningError.machO("no arm64 slice")`; returns the input unchanged when it is already thin.
- Tests: build a synthetic fat file (big-endian header, two slices copied from the fixture binary with different cpusubtype) in the test; `testThinPicksArm64OverArm64e`, `testThinReturnsArm64eWhenItIsTheOnlyChoice`, `testThinInputIsReturnedUnchanged`, `testFatFrameworkInAnAppSignsAndVerifies` (place it under Frameworks, sign, `SignatureVerifier.verifyBundle` passes).
- Implement: `BundleSigner` thins fat files in the work tree before parsing; a note "Removed unused architectures from <name>" is added to the result.
- Commit: `Sign universal binaries by keeping the arm64 slice`

## Phase C: Sources tab

### Task C1: Source parser (new package target `SourcesKit`)
**Files:** Modify `Package.swift` (add target `SourcesKit` and test target), `project.yml`; Create `Sources/SourcesKit/SourceParser.swift`, `Tests/SourcesKitTests/SourceParserTests.swift`, fixtures `Tests/SourcesKitTests/Fixtures/{versions.json,legacy.json,broken.json}`.
**Interfaces:** Produces `struct SourceApp: Codable, Equatable, Identifiable { id: String; name: String; bundleID: String; version: String; size: Int?; iconURL: URL?; downloadURL: URL; date: Date?; summary: String }`, `struct SourceRepo: Codable { name: String; apps: [SourceApp] }`, `enum SourceParser { static func parse(_ data: Data) throws -> SourceRepo }`, `enum SourceError: Error { notJSON, noApps }`.
- Tests: `testVersionsLayoutPicksNewestVersionWithADownload`; `testLegacyLayoutReadsAppLevelDownloadURL`; `testAppsWithoutADownloadAreSkipped`; `testDuplicateBundleIDsAreKeptAsSeparateRows` (distinct `id` = bundleID + version); `testHTMLInsteadOfJSONThrowsNotJSON`; `testNullSizeAndMissingIconAreFine`.
- Implement: Codable with lenient decoding (`decodeIfPresent`, tolerant of `size` as Int or String, dates ISO-8601 with or without fractions); never force-unwrap.
- Commit: `SourcesKit: parse AltStore-format sources in both layouts`

### Task C2: Source store and cache
**Files:** Create `Sources/SourcesKit/SourceStore.swift`; Test `Tests/SourcesKitTests/SourceStoreTests.swift`.
**Interfaces:** Produces `final class SourceStore { init(directory: URL, session: URLSession); var sources: [SavedSource] { get }; func add(url: URL) async throws -> SourceRepo; func remove(_ id: UUID); func refresh(_ id: UUID) async throws -> SourceRepo; func cached(_ id: UUID) -> SourceRepo? }`, `struct SavedSource: Codable, Identifiable { id: UUID; url: URL; name: String; updated: Date? }`. Only https URLs are accepted.
- Tests (URLProtocol stub): `testAddDownloadsParsesAndCaches`; `testNotModifiedUsesTheCacheAndKeepsItIntact` (ETag, 304); `testHTMLResponseThrowsAndLeavesTheCacheUntouched`; `testHTTPURLIsRefused`; `testSourcesSurviveReload`.
- Implement: compact cache file per source (`SourceRepo` as JSON), parse off the main thread (called from a detached task by the app), `If-None-Match` support.
- Commit: `SourcesKit: saved sources with an on-disk cache`

### Task C3: Downloader
**Files:** Create `Sources/SourcesKit/IPADownloader.swift`; Test `Tests/SourcesKitTests/IPADownloaderTests.swift`.
**Interfaces:** Produces `struct IPADownloader { init(session: URLSession); func download(_ app: SourceApp, to directory: URL, refetch: @Sendable () async throws -> SourceApp, progress: @Sendable (Double) -> Void) async throws -> URL }`.
- Tests (stub): `testSuccessWritesAFileAndReportsProgress`; `testExpiredLink403TriggersOneRefetchThenSucceeds`; `testSecond403AfterRefetchFails`; `testInterruptedDownloadLeavesNoFileBehind`; `testResponseThatIsNotAnIPAIsRejected` (first bytes not `PK`).
- Implement: `URLSession.download(for:)` with a delegate for progress; move into `directory` only after the ZIP magic check.
- Commit: `SourcesKit: download IPAs with one retry for expired links`

### Task C4: Sources tab UI
**Files:** Create `App/SourcesView.swift`, `App/SourcesModel.swift`; Modify `App/LocalIPASignerApp.swift` (`Router.Tab` gains `.sources`, first in order; screen added), `App/WaxTabBar.swift` (`WaxGlyph.Kind.sources`, a compass/globe path), `App/SettingsView.swift` ("Sign right after download", `@AppStorage("signAfterDownload")`, default false).
**Interfaces:** Consumes `SourceStore`, `IPADownloader`, `LibraryModel.fileNow(_:info:signed:)`, `SigningModel.use(_:)`.
- Behavior: empty state with a paste field and the responsibility note; per source: name, app count, updated, remove; search; app page with Get and progress; pasted single IPA link is downloaded and filed directly; after a download the app lands in Unsigned, and when `signAfterDownload` is on the app opens in Sign.
- Verify: build; simulator screenshots light and dark (empty, with a stub source served by `python3 -m http.server` over a local test file, search); device: add a real source, Get a small app, see it on the shelf.
- Commit: `Sources tab: add sources, search, Get into the Unsigned shelf`

## Phase D: signing options

### Task D1: Plist-only options
**Files:** Modify `Sources/SigningKit/AppEditor.swift` (`AppEdits`, `apply`), `App/SigningOptionsView.swift`; Test `Tests/SigningKitTests/AppEditorTests.swift`.
**Interfaces:** `AppEdits` gains `appearance: Appearance?` (`enum Appearance: String, Codable { light, dark }`), `gameMode: Bool`, `iPadFullScreen: Bool`, `removeDeviceRestriction: Bool`, `plistEdits: [PlistEdit]` (`struct PlistEdit: Codable, Equatable { key: String; value: PlistValue?; }` where nil value deletes; `enum PlistValue: Codable, Equatable { string(String), bool(Bool), number(Double) }`); `defaultsOnly()` and `isEmpty` updated.
- Tests (assert the resulting Info.plist): `testAppearanceSetsUIUserInterfaceStyle` (`Light`/`Dark`); `testGameModeSetsGCSupportsGameMode`; `testIPadFullScreenSetsUIRequiresFullScreen`; `testRemoveDeviceRestrictionDeletesUISupportedDevices`; `testPlistEditAddsChangesAndDeletesKeys`; `testEmptyEditsStillLeavesTheAppByteForByteAlone`.
- Commit: `Signing options: appearance, game mode, iPad full screen, device restriction, plist editor`

### Task D2: Medium options
**Files:** Modify `Sources/SigningKit/AppEditor.swift` (icon), `Sources/SigningKit/BundleSigner.swift` (entitlements, profile override already via `ProfileSet.overrides`), `Sources/IPAKit/IPAArchiver.swift` (level), Create `App/ExpiryReminder.swift`, `Sources/InstallKit/ExpiryPolicy.swift`; Test `Tests/SigningKitTests/AppEditorTests.swift`, `Tests/InstallKitTests/ExpiryPolicyTests.swift`.
**Interfaces:** `AppEdits.iconPNG: Data?` (replaces the primary icon files and `CFBundleIcons`), `AppEdits.customEntitlements: Data?` (plist, feeds `SigningOptions.requestedEntitlements`), `AppEdits.compression: Compression` (`speed|balanced|size` mapped to deflate level 1/6/9 in `IPAArchiver.archive(..., level:)`), `enum ExpiryPolicy { static func reminderDate(profileExpiry: Date, now: Date) -> Date? }` (one day before expiry at 09:00 local; nil when already within a day).
- Tests: `testIconIsReplacedAndPlistPointsAtIt`; `testCustomEntitlementsReachTheSignedApp` (requested key granted by a wildcard fixture profile appears in the output entitlements); `testSizeLevelProducesASmallerOrEqualArchiveThanSpeed`; `testReminderIsOneDayBeforeExpiry`, `testNoReminderWhenLessThanADayLeft`.
- Not building (outputs cannot install, revisit if asked): "remove profile after signing", "modify only, no signature".
- Commit: `Signing options: icon, custom entitlements, compression, expiry reminder`

### Task D3: Library injection
**Files:** Create `Sources/SigningKit/LibraryInjector.swift`, `Sources/SigningKit/DebExtractor.swift`; Modify `Sources/SigningKit/MachO.swift` (add `addLoadDylib(path:)`), `Sources/SigningKit/AppEditor.swift`, `App/SigningOptionsView.swift` (file picker, folder and path choice); Test `Tests/SigningKitTests/LibraryInjectorTests.swift`, `DebExtractorTests.swift`.
**Interfaces:** `struct InjectionSettings: Codable, Equatable { libraries: [URL]; folder: Folder (.root|.frameworks); path: PathStyle (.executable|.rpath); removeExisting: Bool }`; `enum LibraryInjector { static func inject(_ settings: InjectionSettings, into app: URL) throws -> [String] }` returning notes; `enum DebExtractor { static func dylibs(inDeb deb: URL, to directory: URL) throws -> [URL] }` (parses the `ar` container, decompresses `data.tar.gz` and `data.tar.lzma/xz` with the Compression framework, collects `.dylib` files, ignores the rest; `data.tar.zst` is refused with a clear message).
- Tests: `testInjectCopiesTheLibraryAndAddsALoadCommand` (parse with `MachO`, find `LC_LOAD_DYLIB` named `@rpath/Frameworks/x.dylib`); `testRefusesWhenTheHeaderHasNoRoom` (original bytes unchanged); `testRefusesAnEncryptedMainBinary`; `testRemoveExistingDeletesDylibsAndTheirLoadCommands`; `testDebWithAGzipDataTarYieldsItsDylibs`; `testZstdDebIsRefusedClearly`; `testInjectedLibraryIsSignedByTheSigner` (sign afterward, verifier passes).
- Commit: `Signing options: inject .dylib, .framework and .deb into an app`
- Device check: inject a trivial dylib into the Wax Probe app, sign, install, it launches.

## Phase E: install speed

### Task E1: Skip re-uploading an IPA the server already has
**Files:** Modify `Server/wax-ota/wax_ota.py`, `Sources/InstallKit/OTA.swift`; Test `Server/wax-ota/test_wax_ota.py`, `Tests/InstallKitTests/OTATests.swift`.
**Interfaces:** client sends header `X-Wax-SHA256` on the IPA PUT; server hashes while streaming, writes `<id>/.sha256`, and answers `GET /has/<sha256>` with the existing session id (200 JSON `{"id": "..."}`) or 404 (needs the token). `OTAUploader.existingSession(sha256: String) async -> String?`.
- Tests: server: `test_has_returns_the_id_of_a_stored_ipa`, `test_has_404_for_unknown_hash`, `test_has_needs_token`, `test_wrong_hash_header_is_rejected_400`; client (stub): `testUploadSkipsThePutWhenTheServerAlreadyHasTheFile`.
- Commit: `Skip uploading an IPA the server already has`

### Task E2: Start uploading while the archive is still being written
**Files:** Modify `Sources/IPAKit/IPAArchiver.swift` (output to an `OutputStream`), `Sources/InstallKit/OTA.swift` (`uploadTask(withStreamedRequest:)`), `Server/wax-ota/wax_ota.py` (accept `Transfer-Encoding: chunked`); Test `Server/wax-ota/test_wax_ota.py`, `Tests/IPAKitTests/ArchiveRoundTripTests.swift`.
- First step is a measurement: add timing lines to `ImportLogs` for pack seconds and upload seconds; run the 320 MB Chess IPA on the phone and record both in the spec. Continue only if upload is at least 30% of the total.
- Tests: server `test_chunked_put_is_stored_and_matches_hash`; archiver `testStreamedArchiveEqualsFileArchive` (same bytes as the file-based archive).
- Commit: `Overlap packing and upload`

### Task E3: Domain-to-127.0.0.1 spike (throwaway)
**Files:** Create `docs/superpowers/specs/2026-10-17-loopback-domain-spike.md` only; no product code.
- Steps: the owner makes a free DuckDNS subdomain pointing at 127.0.0.1 (token goes in a shell variable on the Mac, never in the repo); get a Let's Encrypt certificate for it with a DNS-01 client (`acme.sh --dns dns_duckdns`); build a throwaway app that serves a manifest and a tiny IPA from `https://<name>.duckdns.org:8443` using that certificate; open the `itms-services://` link on the phone; record exact result (prompt shown, error text) in the spike document; delete the throwaway app, certificate and token.
- Decision rule: works means a follow-up spec for a project-owned domain (note the leaked-key revocation risk); does not work means close it in the spec.
- Commit: `Spike: result of installing from a name that resolves to 127.0.0.1`

## Phase F: cloud bucket install host

### Task F1: S3 SigV4 signing
**Files:** Create `Sources/InstallKit/S3Signer.swift`; Test `Tests/InstallKitTests/S3SignerTests.swift`.
**Interfaces:** Produces `struct S3Credentials { accessKey: String; secretKey: String; region: String; endpoint: URL }` and `enum S3Signer { static func presignGET(_ url: URL, credentials: S3Credentials, expires: Int, date: Date) -> URL; static func signedRequest(method: String, url: URL, payloadSHA256: String, credentials: S3Credentials, date: Date) -> URLRequest }`.
- Tests: the AWS published SigV4 example vectors (use the "GET Object" query-string example and the `get-vanilla` header example from the AWS Signature Version 4 documentation; the implementer copies the exact inputs and expected signatures into the test); plus `testPresignedURLIsPercentEncodedAndHasExpires`.
- Commit: `InstallKit: AWS Signature V4 signing for S3-compatible buckets`

### Task F2: Bucket backend and selection
**Files:** Create `Sources/InstallKit/S3Host.swift`; Modify `App/OTAInstallModel.swift` (choose host), `App/SettingsView.swift` (Install host: My server or Cloud bucket; paste endpoint, bucket, keys; "Test" button), `Sources/InstallKit/SecretStore.swift` (second item for the keys); Test `Tests/InstallKitTests/S3HostTests.swift`.
**Interfaces:** `protocol InstallHost { func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String, progress: @Sendable (Double) -> Void) async throws -> URL }`; `OTAUploader` and `S3Host` conform. `S3Host.cleanup(id:)` deletes both objects.
- Tests (stub): `testPublishPutsIPAAndManifestThenReturnsAnItmsLinkWithSignedURLs`; `testExpiredKeysSurfaceAsAMessageNamingTheKeys` (403 `ExpiredToken`); `testWrongRegionSurfacesTheRegionMessage`; `testFailedManifestPutDeletesTheIPA`; `testSignedLinksExpireAfterSixHours`.
- Setup text names the free tiers and says plainly that some providers ask for a card for identity verification; the guide tells users to add a one-day expiry rule on the bucket.
- Device check: upload to a real free bucket (the owner's choice), install a small app through it.
- Commit: `Install host: any S3-compatible bucket`

## Phase G: open-source prep

### Task G1: Failed-login throttling on the server
**Files:** Modify `Server/wax-ota/wax_ota.py`; Test `Server/wax-ota/test_wax_ota.py`.
- Tests: `test_five_bad_tokens_lock_the_ip_for_fifteen_minutes` (429 afterwards, even with the right token), `test_lock_expires`, `test_good_token_does_not_count`.
- Commit: `Server: lock an address out after repeated wrong tokens`

### Task G2: Server installer for any Ubuntu VPS
**Files:** Create `Server/wax-ota/install.sh`, `Server/wax-ota/Caddyfile.example`, `Server/wax-ota/README.md` (Oracle Always Free walk-through); Test `Server/wax-ota/test_install_script.py`.
- `install.sh [--dry-run] <domain>`: installs Caddy and the service, creates a random 40-character token (written only to `/etc/wax-ota.env`, mode 600), opens only 22/80/443, enables fail2ban, exposes only `/ota-up` and `/ota`, prints `WAXINSTALL1 https://<domain> <token>`.
- Tests: `--dry-run` prints every command and never prints a real token; the generated Caddyfile contains exactly the two routes and a `respond 404` fallback; `bash -n install.sh` passes.
- Commit: `Server: one-command installer and Oracle guide`

### Task G3: Scrub and publish prep
**Files:** Modify `Tests/InstallKitTests/OTATests.swift:29-31` (use `https://ota.example.test/`), `Tests/InstallKitTests/BundleIDGuardTests.swift`, `docs/superpowers/specs/2026-10-14-direct-install-design.md` (remove team IDs and personal bundle IDs); Create `SECURITY.md`, `scripts/publish-prep.sh`; Test `scripts/test_publish_prep.sh`.
- `publish-prep.sh`: refuses to run with uncommitted changes; greps HEAD for a denylist file (`scripts/denylist.txt`, not committed: the owner's server IP, team IDs, email) and fails on any hit; creates a fresh orphan branch with one squashed commit for publishing.
- Tests: the script fails on a planted denylisted string and passes on a clean tree.
- `SECURITY.md`: how the server is protected, what the token is, how to report problems.
- Commit: `Scrub personal identifiers and add publish-prep and SECURITY.md`

## Self-review
Spec coverage: section 1 (C1-C4), 2 (D1-D3; two options dropped and noted), 3 items 1-12 (A1, A2, A3, A4, A5, A6, A7, A8, B1-B4; item 6 chain intermediates is NOT planned: unverified need, revisit with a reseller `.p12`), 4 (E1-E3), 5 (G1-G3), 6 (F1-F2, E3), 6b (Global Constraints, F2 copy), 7 (done). Spec corrections made while planning: fat binaries are thinned to arm64 rather than "left alone"; the 6-hour server TTL has no download-refresh because Caddy serves the files; "remove profile after signing" and "modify only" are dropped.
