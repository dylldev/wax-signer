# Wax master roadmap execution checkpoint

**Program status: PARTIALLY COMPLETE.** Earlier milestone heads retain passing applicable macOS CI; new R8/R7/R15 continuation heads and their exact verification are recorded below. Partial milestones do not complete their original R identifiers. Documentation/checkpoint updates are separate from code verification.

Baseline source: `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379` (R2 merge); R1 ancestor `ff50f001f8ee768b5fe3cbd5835377bc563fd2b9`. Distribution baseline: `d4d4ca79160e75f9dc119b9e6ab4bf8908f16123`.

Original definitions recovered from the existing, untracked `ROADMAP.md` and `WAX-ENGINEERING-AUDIT.md` under `/workspace/wax-signer/docs/audits/2026-10-19/`. Those source artifacts are read-only and are not added by this program. Inventory below transcribes their actual descriptions, dependencies, scope and acceptance criteria; it does not invent replacement R identifiers.

No newly implemented PR may be merged automatically. No releases, deployments, credential changes or user-IPA uploads are authorized. This is a continuation checkpoint, not a claim that every item is complete.

## Priority and dependency order

First finish R3 verification, without waiting indefinitely for its independent review. Independent P0 R4 and P1 R5 proceed from main. Next prioritize P1 R6/R7/R8/R9 and the R12 release gate. R10 depends on R3/R8; R14 depends on R3/R6/R8. R11 follows R4; R13 measurement precedes R18 optimization. R15 precedes R17, while R19 requires issuer-policy/domain/device evidence. R20 consists of three separate milestones and cannot be called complete from the R3 artifact journal alone.

## Status ledger

| ID | Original task | State / disposition | Branch / PR / verification |
|---|---|---|---|
| R3 | P1: Durable non-destructive library | Implemented with verification limitations; final cleanup containment regression added | [PR #3](https://github.com/dylldev/wax-signer/pull/3) `2a045f9` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39309629029/job/118255543908) |
| R4 | P0: Cohesive distribution update | Ready for review — staged repair; no publication | `codex/r4-distribution-correctness`, [PR #4](https://github.com/dylldev/wax-signer/pull/4), `4534231`, [green CI 39286293647](https://github.com/dylldev/wax-signer/actions/runs/39286293647) |
| R5 | P1: Isolate uploads/session mutation | Ready for review — actual SHA cache-hit verification also green | `codex/r5-ota-upload-reliability`, [PR #5](https://github.com/dylldev/wax-signer/pull/5), `3e30326`, [green CI39304752811](https://github.com/dylldev/wax-signer/actions/runs/39304752811) |
| R6 | P1: Independent App ID prefixes | Ready for review — implemented; real-profile/keychain device gate open | `codex/r6-app-id-prefix`, [PR #7](https://github.com/dylldev/wax-signer/pull/7), `3ef32fe`, [green CI 39283732825](https://github.com/dylldev/wax-signer/actions/runs/39283732825) |
| R7 | P1: Input/scratch budgets | Partial: source/IPA acquisition, install replies/feed and custom-icon budgets; extraction/scratch/worker budgets unfinished | `codex/r7-download-budgets`, [PR #10](https://github.com/dylldev/wax-signer/pull/10), `023a29b`, [green CI 39285751184](https://github.com/dylldev/wax-signer/actions/runs/39285751184) |
| R8 | P1: Job/cancellation/session ownership | Partial: loopback, background and OTA session coordination implemented; full cooperative engine cancellation unfinished | [PR #13](https://github.com/dylldev/wax-signer/pull/13) `0a044e0` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39305374860/job/118240929086); [PR #17](https://github.com/dylldev/wax-signer/pull/17) `731e5fc` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310132797/job/118257254509) |
| R9 | P1: Responsive retryable imports | Implemented with verification limitations; stacked on updated R3 | [PR #12](https://github.com/dylldev/wax-signer/pull/12) `e607741` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310127468/job/118257236365) |
| R10 | P2: Truthful result/retry state | Partial: observed outcome language + R3 save truth; snapshots/contextual history/retry scope unfinished | [PR #15](https://github.com/dylldev/wax-signer/pull/15) `73d3020` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39306630462/job/118245275860) |
| R11 | P2 release gate: Artifact/feed consistency | Partial: tagged-source candidate gate; actual approved-tag build/protected promotion/rollback unfinished | [PR #18](https://github.com/dylldev/wax-signer/pull/18) `524ef77` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310041670/job/118256951748) |
| R12 | P1 release gate: Independent/device conformance | Partial milestone ready for review — source-built probe/CI evidence; physical controls not run | `codex/r12-probe-conformance`, [PR #11](https://github.com/dylldev/wax-signer/pull/11), `afb1ce5`, [green CI 39287037674](https://github.com/dylldev/wax-signer/actions/runs/39287037674) |
| R13 | P2: Trustworthy performance measurements | Partial milestone ready for review — synchronized timing/output isolation; corpus/metrics/phone budgets not completed | `codex/r13-performance-evidence`, [PR #9](https://github.com/dylldev/wax-signer/pull/9), `6d4ccf0`, [green CI 39285180880](https://github.com/dylldev/wax-signer/actions/runs/39285180880) |
| R14 | P2: Persistence/secrets/host cleanup | Partial: cache transactions + bucket ledger; remaining secret/accessibility migration unfinished | [PR #8](https://github.com/dylldev/wax-signer/pull/8) `be5c53c` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39284307056/job/118165791707); [PR #14](https://github.com/dylldev/wax-signer/pull/14) `0760cf5` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310132639/job/118257253470) |
| R15 | P2: Read-only preflight/change preview | Partial: immutable library plan/execution parity implemented; app/edits preview and production policy adoption unfinished | [PR #21](https://github.com/dylldev/wax-signer/pull/21), `c8248a8`; exact CI below |
| R16 | P2: Source browsing/accessibility | Partial: hidden/inactive animation + R3 source IDs; details/artwork/localization/AX unfinished | [PR #16](https://github.com/dylldev/wax-signer/pull/16) `035c0dd` / [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39306866626/job/118246083078) |
| R17 | P3: Signing graph/integrity history | Investigated — not completed | See revalidation and continuation below |
| R18 | P3: Measured engine/new formats | Investigated — not completed; R12/R13/R17 gates remain | See revalidation and continuation below |
| R19 | P3 research: User-owned loopback TLS | Research partly completed; domain/issuer authorization and physical experiments blocked | [Primary-source evidence and protocol](R19-RESEARCH.md); no product implementation or successful device acceptance claimed |
| R20 | P3: Recoverable jobs/probes/diagnostics | Investigated — not completed; library journal/probe v1 only groundwork | See revalidation and continuation below |

## Original implementation specifications

Each original scope below supplies severity, files, evidence, solution, dependencies, complexity/risk, acceptance and tests. Device-only requirements are retained as unverified requirements.

### R3 — P1: Make local artifact saving durable and non-destructive

- **Files:** `Sources/InstallKit/IPALibrary.swift`; `App/LibraryModel.swift`, `SourcesModel.swift`, `ContentView.swift`, `SigningModel.swift`, `SignView.swift`; `Tests/InstallKitTests/IPALibraryTests.swift`; proposed app-model persistence tests.
- **Evidence/problem:** F08/F09. Save nil is treated as success; distinct files collide under metadata/size deduplication and old bytes are deleted.
- **Solution:** Propagate typed save errors; retain a retryable staged file until the library commit or explicit export succeeds. Identify exact duplicates by SHA-256 and preserve different builds/signatures/options. Add build/provenance metadata through a backward-readable index migration; calculate missing hashes lazily.
- **Dependencies:** No need to wait for new signing format work. Coordinate the digest format with R2/R17.
- **Difficulty/risk:** M; medium persistence/migration risk. Never migrate by deleting files whose identity is uncertain.
- **Acceptance:** A failed copy/index write cannot show Added/On shelf/Saved or discard the sole retryable copy. Same metadata and size with different bytes remain distinct. Exact duplicates do not multiply silently. Existing indexes open and user originals remain untouched.
- **Tests:** Permission/copy/index failures via injectable filesystem seam; distinct equal-size payloads; same marketing version/different build; different signer/edits; crash between staging and index commit; restart recovery; UI/model success and failure assertions, not only library unit tests.

### R4 — P0: Prepare a correct, cohesive distribution update

- **Files:** `Source/make_source.py`, `validate_source.py`, `test_make_source.py`, `test_validate_source.py`; `README.md`, `CHANGELOG.md`, `scripts/build-release-ipa.sh`; distribution repository `apps.json`, `index.html`, IPA/checksum assets. Modify `project.yml` only if the chosen release version needs an intentional update.
- **Evidence/problem:** F06 and live release ledger. New Pages location serves a feed containing old-account 404 links and obsolete product copy. Multiple version/bundle-ID generations are public.
- **Solution:** Choose the intended tested release artifact; derive version/build/ID/size/hash from it; generate accurate capability copy and current canonical URLs; make configured versus unconfigured phone-host builds explicit. Stage a complete allowlisted site and verify each URL locally and remotely. Prepare a diff and exact publication commands for final owner review; do not publish during this audit follow-up unless separately authorized.
- **Dependencies:** R1–R3 for the next new binary; metadata-only repair can point to an already verified existing artifact while clearly naming its limits. R11 later automates this.
- **Difficulty/risk:** S for metadata repair, M for complete artifact preparation; medium migration/release risk.
- **Acceptance:** Every advertised icon/download/add-source URL resolves; feed plist metadata and checksum match the intended bytes; no “cannot sign/install” copy for a capable build; old/new bundle-ID implications are documented. No private identity, token, server configuration or unpublished artifacts enter the stage.
- **Tests:** Generated-release fixture equality, old/new account base, URL encoding, required fields and historical versions, checksum mismatch, stale description/version rejection, offline allowlist and postdeploy smoke plan, manual AltStore/SideStore ingestion on available devices.

### R5 — P1: Isolate server uploads and session mutation

- **Files:** `Server/wax-ota/wax_ota.py`, `test_wax_ota.py`, `Caddyfile.example`, `README.md`; related `Sources/InstallKit/OTA.swift` behavior only if a new conflict response needs mapping.
- **Evidence/problem:** F19, executed against the real local server. Concurrent `_store` calls use the same `.app.ipa.part` path. One acknowledged file is modified by the other open writer.
- **Solution:** Unique temporary files per request plus a per-session mutation lock or explicit 409 conflict policy. Protect IPA/hash/manifest publication as a coherent sequence and keep active sessions out of GC/DELETE. Reserve/release quota consistently including temporary files. Bound active body readers and configure header/body limits at the proxy. Stdlib implementation is sufficient.
- **Dependencies:** None; client mapping changes only if necessary. Keep existing per-owner token model and no public access logging.
- **Difficulty/risk:** M; medium race/quota/GC regression risk.
- **Acceptance:** A 201 file's bytes never change because of another in-flight request; hash metadata always describes the published file; same-session overlap is serialized or rejected predictably; distinct-session uploads still progress; cancellation/GC/delete cannot leak quota or corrupt another session.
- **Tests:** Promote `repros/server_collision.py` into deterministic server regressions; concurrent same filename, IPA/manifest, DELETE, and GC; short body/hash failure while replacement exists; quota exhaustion/release; proxy integration and hidden temporary-file behavior. Avoid timing-only tests when events/barriers can synchronize requests.

### R6 — P1: Preserve App ID prefixes independently of Team IDs

- **Files:** `Sources/CredentialKit/Models.swift`, `ProfileReader.swift`, `ProfileFitness.swift`, `SigningInputs.swift`, `Compatibility.swift`; `Sources/SigningKit/Entitlements.swift`, `BundleSigner.swift`, `ProfileSelection.swift`; fixture generator and `Tests/SigningKitTests/ProfileSelectionTests.swift`, credential parser tests.
- **Evidence/problem:** F05, supported by Apple's TN2311. Real historical prefixes can differ from Team ID; current parsing/matching conflates them.
- **Solution:** Add a validated application-identifier prefix model; keep Team ID for team entitlement/CodeDirectory; derive app ID/keychain groups from the appropriate allowed prefix and profile values. Explain prefix changes and potential keychain loss in the preview.
- **Dependencies:** R1 for malformed-input invariants; coordinate backward-compatible metadata decoding with R3/R14.
- **Difficulty/risk:** M; high compatibility/keychain-continuity risk. Keep keep-ID mode's deliberate semantics unchanged except for correct prefix derivation.
- **Acceptance:** Synthetic and authorized real profiles with distinct prefixes work correctly in exact/wildcard/keep/rename modes; matching same-prefix profiles retain behavior; no unauthorized group is added; updates retain expected keychain access where provisioning permits.
- **Tests:** Distinct TeamIdentifier/ApplicationIdentifierPrefix; missing/ambiguous/malformed prefix; exact/full/prefix wildcard; keychain/application-group decisions; independent entitlement extraction; device update and keychain continuity with authorized test material.

### R7 — P1: Enforce input and scratch-space budgets while work happens

- **Files:** `Sources/SourcesKit/SourceStore.swift`, `IPADownloader.swift`; `Sources/InstallKit/InstallTransport.swift`, `CertificateFeed.swift`; `Sources/IPAKit/ExternalFile.swift`, `IPAExtractor.swift`; `Sources/SigningKit/DebExtractor.swift`; `App/CredentialsModel.swift`, `SigningOptionsView.swift`; affected parser/download tests.
- **Evidence/problem:** F07. Several limits apply only after full materialization; compressed/uncompressed input paths have inconsistent budgets.
- **Solution:** Introduce small explicit operation budgets: actual received bytes, read bytes, cumulative decoded bytes/object count, total deadline, minimum free space, max image pixels and worker memory. Use Content-Length only for early rejection, never as authority. Enforce actual chunks, stop the task and delete partials immediately. Cap uncompressed tar too. Keep reasonable configurable IPA limits.
- **Dependencies:** R8 ownership for cancellation/cleanup; can land bounded-read and source-download pieces earlier.
- **Difficulty/risk:** M–L; medium risk of rejecting legitimate large inputs and expired-link retries.
- **Acceptance:** Known-length, chunked and lying-length responses stop near the configured cap; oversized credentials are rejected before full read; partials are removed; existing library/user inputs survive; errors name size/disk/deadline cause and recovery.
- **Tests:** Chunked oversized JSON/IPA, expanding Content-Encoding, very slow response, no length, redirect chain, low disk at each stage, 1 GiB tar boundary metadata without giant committed fixtures, image pixel bomb, cancellation and restart cleanup.

### R8 — P1: Own jobs, cancellation and install sessions explicitly

- **Files:** `App/BackgroundJob.swift`, `SigningModel.swift`, `SourcesModel.swift`, `IdentityReadiness.swift`, `OTAInstallModel.swift`, `SignView.swift`; `Sources/InstallKit/LoopbackHost.swift`; proposed `App/JobCoordinator.swift`; loopback and model lifecycle tests.
- **Evidence/problem:** F11/F12. Singleton lifecycle/state can be overwritten by multiple operations; listener stop omits accepted connections; detached work lacks retained cancellation ownership.
- **Solution:** Introduce operation tokens, immutable configuration snapshots, retained task handles and a serial install coordinator. Use per-job background resources or a carefully refcounted aggregate. Mark host preparation busy before awaits; generation-check all progress/completion callbacks. Track NWConnections/file handles, close on stop/expiration. Implement cooperative cancellation at safe I/O/page/file boundaries; never cancel halfway through publishing an output.
- **Dependencies:** R1/R2 make abort boundaries safer; integrate resource-budget cleanup from R7.
- **Difficulty/risk:** L; high lifecycle risk. Incremental coordinator adoption is safer than converting every store to actors at once.
- **Acceptance:** Concurrent downloads don't complete each other's background jobs; testing cannot replace an active installation unnoticed; stale callbacks cannot revive canceled state; stop/expiry terminates existing transfers; iOS task completion occurs once per task; cancellation preserves previous output and removes owned partials.
- **Tests:** Deterministic delayed-operation model tests, queued task adopted after foreground job ends, expiration during each pipeline stage, cancel-before-start downloader race, stop during range/body transfer, republish with old callbacks, lock/background/notification-permission device matrix.

### R9 — P1: Keep credential imports responsive and retryable

- **Files:** `App/CredentialsModel.swift`, `CredentialsView.swift`; `Sources/CredentialKit/CredentialStore.swift`, `PKCS12Reader.swift`, `PKCS12Modern.swift`; proposed app import-worker/model tests.
- **Evidence/problem:** F10. Crypto and import persistence remain on MainActor after background byte reading.
- **Solution:** Off-main retained import operation with immutable bytes/password, bounded work and visible busy/error state. MainActor only publishes results. Keep a short-lived pending import for password retry; explicitly clear it on success/cancel/dismiss and do not log it. Do not require hardware-backed RSA or introduce a remote converter.
- **Dependencies:** R7 early read/work limits; R8 task ownership. Existing Keychain store locking can remain until measured contention justifies changes.
- **Difficulty/risk:** M; medium concurrency/secrets-lifetime risk.
- **Acceptance:** UI remains responsive with high-work-factor synthetic P12; repeated wrong-password retries work without repeated picks; cancel/dismiss cannot import into the wrong pending item or leave secrets on disk.
- **Tests:** Slow injectable importer, overlapping picks/cancel/retry, partial multi-identity outcomes, Keychain failure, password redaction, MainActor responsiveness on device; actual modern/legacy fallback regressions.

### R10 — P2: Make result state, provenance and retry actions match reality

- **Files:** `App/SigningModel.swift`, `SignView.swift`, `SigningOptionsView.swift`, `ContentView.swift`, `LibraryModel.swift`, `OTAInstallModel.swift`, `InstallSection.swift`, `IdentityReadiness.swift`; `Sources/InstallKit/IdentityStatus.swift`, `SignScreenLogic.swift`; model/state tests.
- **Evidence/problem:** F13/F15, misleading save/install certainty, certificate-only probe history, generic “choose another file” recovery.
- **Solution:** Snapshot signing configuration and bind result identity to it; invalidate or visibly present historical results after edits. Separate source signature presence from Wax provenance and install eligibility. Add Re-sign everywhere, Retry delivery without re-signing, Change host and Export. Record probe observation/profile digest/OS/time; differentiate delivery, detected install and launch.
- **Dependencies:** R3 durable artifacts and R8 session-owned states.
- **Difficulty/risk:** M; medium UI behavior/migration risk.
- **Acceptance:** Every signing-affecting input change has defined result behavior; no stale Install link persists after its host expires; third-party signed IPAs remain re-signable; failure preserves the signed artifact; status words never imply unobserved installation/launch.
- **Tests:** State transition table, settings edits after export/signing, expired links, import routing, failed library save, probe stale-profile/OS results, user cancels install prompt, VoiceOver outcome announcement once per operation.

### R11 — P2 release gate: Automate source-to-artifact-to-feed consistency

- **Files:** `scripts/build-release-ipa.sh`, `publish-main.sh`, `publish-prep.sh`; `Source/make_source.py`, `validate_source.py` and tests; `.github/workflows/ci.yml`; proposed `.github/workflows/release.yml` and artifact manifest schema; `README.md`, `CHANGELOG.md`; generated distribution assets.
- **Opportunity/evidence:** Live release divergence, hashes checked but no source mapping/attestation, orphan public snapshots, mutable tool/action versions.
- **Solution:** Build once from reviewed immutable tag, record toolchain and public configuration flavor; generate feed/page/checksums from built metadata; attach provenance; allowlist and scan stage; review promotion; fetch deployed bytes and compare. Preserve useful old versions deliberately. Adopt future clean public history without disclosing old private history.
- **Dependencies:** R4 staged process; R1/R2/R12 quality gates before promoting a new binary.
- **Difficulty/risk:** M–L; medium release/credential-exposure risk; reduce permissions and isolate build from deploy.
- **Acceptance:** Wrong version/build/ID/hash/URL, missing probe, stale copy and secret fixture exceptions fail before promotion. Release stage is independently reviewable. Same artifact bytes appear in release/feed. Rollback does not delete the previous usable release. No claim of bit reproducibility without a second build comparison.
- **Tests:** Release-tool fixtures, no-feed/configured builds, checksum mismatch, unexpected stage file, old base/account, encoded filename, incomplete prior versions, tag/plist mismatch, postdeploy smoke and rollback rehearsal using a local staging service.

### R12 — P1 release gate: Establish independent conformance and device evidence

- **Files:** `Tests/SigningKitTests/SigningTests.swift`, `SignatureVerifierTests.swift`, `IPASignerTests.swift`, `CodeResourcesTests.swift`, `AuditRegressionTests.swift`; `.github/workflows/ci.yml`, `project.yml`; `Prototype/`; proposed versioned WaxProbe project/source; `docs/device-results/` and verification procedure.
- **Opportunity/evidence:** One project-reported device, optional tests/skips, no independent launch/extension evidence from this audit; bundled probe lacks a clear corresponding build target.
- **Solution:** Explicit test plans and retained xcresult/skip summaries; final-IPA codesign/OpenSSL verification; source-built probe; documented device matrix in the audit. Run app launch and actual extension/keychain/group behavior for claimed combinations.
- **Dependencies:** R1/R2/R6/R8. Authorized device material must come from the owner; never commit it.
- **Difficulty/risk:** L; low product-code risk, meaningful test/tooling work and device scheduling.
- **Acceptance:** Results record exact commit/build, device/OS, credential type without secrets and distinct verify/install/launch/extension outcomes. Required checks cannot silently skip. Unsupported cases are documented and rejected or labeled experimental.
- **Tests:** Baseline Xcode-signed control, Wax final IPA, tampered resource/page/CMS, supported nested bundle matrix, prefix variation, development/Ad Hoc, local/external host, iOS 17/current stable, locked/background/low disk. Simulator alone is insufficient.

### R13 — P2: Establish trustworthy performance measurements and tune budgets

- **Files:** `Tests/SigningKitTests/PerfTests.swift`; `Sources/IPAKit/IPAExtractor.swift`, `IPAArchiver.swift`; `Sources/SigningKit/CodeResources.swift`, `BundleSigner.swift`, `IPASigner.swift`; `Sources/InstallKit/JobProgress.swift`; proposed benchmark fixture generator/harness and results under `docs/benchmarks/`.
- **Evidence/problem:** F14 and repeated whole-file/scanning costs. Changelog's Mac timing is not an iPhone baseline.
- **Solution:** Synchronize measurement collection, add monotonic stage signposts and RSS/scratch instrumentation. Benchmark the audit's small/medium/large corpora. Compare bounded worker counts and content-inventory reuse; adopt only measured improvements. Separate network upload from local engine.
- **Dependencies:** R1/R2/R7/R8 to measure correct bounded behavior.
- **Difficulty/risk:** M for harness; medium for worker/scan changes. Streaming engine work is R18, not bundled here.
- **Acceptance:** Reproducible corpus hashes, raw samples, median/p95, toolchain/device context, peak RSS/scratch and thermal behavior. No benchmark data races. User-visible regressions and memory ceilings are explicit; correctness checks remain enabled.
- **Tests:** Thread Sanitizer on harness and workers, output byte/digest equality, fixed-seed corpus regeneration, baseline regression thresholds with noise tolerance, cancellation latency and low-memory completion.

### R14 — P2: Harden persistence, secret migration and host cleanup

- **Files:** `Sources/CredentialKit/CredentialStore.swift`, `IdentityKeychain.swift`, `Models.swift`; `Sources/InstallKit/SecretStore.swift`, `S3Host.swift`; `Sources/SourcesKit/SourceStore.swift`; `App/LocalIPASignerApp.swift`, `OTAInstallModel.swift`; credential/store/secret/source/S3 tests.
- **Opportunity/evidence:** Key/cert partial deletion and backup rollback need fault testing; bucket keys omit launch migration; pending cleanup forgets original host; refresh/cache transactions race.
- **Solution:** Versioned migration/reconciliation, explicit partial outcomes rather than false rollback promises, per-file exclusion/protection migration, bucket-key accessibility migration, original endpoint/bucket identity on cleanup records and retryable errors. Serialize source cache/index/ETag changes and clear obsolete ETags on new 200 responses.
- **Dependencies:** R3 index schemas, R6 prefix model and R8 operation ownership.
- **Difficulty/risk:** L; high migration/custody risk, so separate small patches and preserve original files.
- **Acceptance:** Upgrade never silently loses accessible credentials/artifacts; partial Keychain failures remain repairable and visible; profile exclusion flags survive rollback; failed bucket cleanup is retained until expiration/backstop; removed sources cannot be resurrected by stale refresh.
- **Tests:** Upgrade fixtures, crash/fault injection between components, shared-key distinct certs on device, reinstall/access groups, cache/ETag races, host change while pending cleanup, delete failure and privacy-preserving error messages.

### R15 — P2: Deliver an explainable read-only preflight and change preview

- **Files:** `Sources/SigningKit/BundleSigner.swift`, `ProfileSelection.swift`, `Entitlements.swift`, `BundleLayout.swift`, `AppEditor.swift`; `Sources/CredentialKit/ProfileTrust.swift`, `Compatibility.swift`; proposed `Sources/SigningKit/SigningPlan.swift`; `App/SigningOptionsView.swift`, `SignView.swift`, `CredentialsView.swift`, `IdentityReadiness.swift`.
- **Opportunity/evidence:** Much compatibility reasoning exists but is buried in failures/post-sign strings; CMS invalidity is reported only afterward; UI pins only main profile.
- **Solution:** Immutable bounded plan: per-bundle profile/rejections, requested/granted/dropped/rewritten entitlements, changes and risks. Separate invalid CMS from unknown trust and apply an explicit app production policy. Advanced per-bundle profile assignment and strict entitlement mode. Reuse plan for execution with stale-input detection.
- **Dependencies:** R1/R6/R10/R14; retain explicit permissive fixture policy for synthetic tests without weakening production defaults.
- **Difficulty/risk:** L; medium–high semantic risk. Do not present predicted compatibility as device approval.
- **Acceptance:** Preview explains all mutations and capability losses before a long run; plan and executed result agree or stale input is rejected; selected overrides are checked; no grant is broadened; installation and revocation remain unknown where untested.
- **Tests:** Plan/execution parity, malformed/tampered profiles, override failures, entitlement arrays/groups, rename cross-references, concurrent settings/input changes, no file mutation during preview, usability/accessibility review.

### R16 — P2: Complete source browsing and accessibility polish

- **Files:** `App/SourcesView.swift`, `SourcesModel.swift`, `Theme.swift`, `WaxTabBar.swift`, `WaxMelt.swift`, `SigningOptionsView.swift`, `CredentialsView.swift`, `InstallSection.swift`, `SignView.swift`; `Sources/SourcesKit/SourceParser.swift`; proposed string catalog, bounded artwork loader and UI tests.
- **Opportunity/evidence:** Unused source summary/developer, source IDs collide across repos, adaptive-layout/motion gaps and network image budgets.
- **Solution:** Source-scoped identities and details page; compare advertised versus inspected metadata; bounded downsampled artwork; optional artwork suppression; adaptive action-sheet detents and 44-point controls; Dynamic Type/VoiceOver/Reduce Motion/localization, pause hidden/inactive animations. Keep existing palette/tokens.
- **Dependencies:** R7 network budgets, R10 honest states, R15 terminology.
- **Difficulty/risk:** M–L; low–medium UX risk; avoid visual rewrites unrelated to demonstrated issues.
- **Acceptance:** AX1–AX5 narrow-phone flows usable; controls discoverable to VoiceOver and large text; no clipped security decisions; no continuous hidden animation; multiple repos offering same app/version have independent state; first-run still ships no third-party sources.
- **Tests:** XCUITest happy/recovery flows, accessibility inspector and physical VoiceOver pass, Reduce Motion/light/dark screenshots, huge labels/source lists, corrupt/oversized artwork, source mismatch warning and localization expansion.

### R17 — P3: Signing graph, local integrity reports and health history

- **Files:** proposed `Sources/SigningKit/SigningGraph.swift`, `IntegrityReport.swift`; `Sources/SigningKit/SigningPlan.swift`, `IPASigner.swift`; `Sources/InstallKit/IPALibrary.swift`; new App graph/report/history views.
- **Opportunity:** Explain exactly which binary/profile/capability failed and make outputs independently traceable. Current selections/CDHashes are partial groundwork.
- **Solution:** One immutable graph and bounded report schema binding source/output hashes, checks, public fingerprints, edit plan, toolchain/build and optional user-signed report. Local-only by default; redacted opt-in export.
- **Dependencies:** R2/R3/R12/R15.
- **Difficulty/risk:** L; medium schema/privacy risk.
- **Acceptance:** Report can be validated without private credentials; graph references actual final bytes and displays uncertainty; fingerprints do not masquerade as trust. Large graphs render lazily.
- **Tests:** Report tampering/schema migration, digest mismatch, missing nodes, provenance redaction and scale/VoiceOver tests.

### R18 — P3: Large-file engine and broader format support, gated by measurement

- **Files:** `Sources/SigningKit/MachO.swift`, `CodeDirectory.swift`, `BundleSigner.swift`, `SignatureVerifier.swift`; `Sources/IPAKit/ZipArchive.swift`, `IPAArchiver.swift`, `IPAExtractor.swift`; new large-file conformance/benchmark tests.
- **Opportunity:** Whole executable Data buffers and classic-ZIP limits remain barriers after ordinary worker tuning.
- **Solution:** File-backed validated Mach-O views, streaming page hashes and transactional rewrite; add ZIP64 only after final-IPA/iOS compatibility evidence. Multi-slice and ECDSA support are separate subprojects with real need/fixtures and independent CMS/device conformance gates.
- **Dependencies:** R1/R2/R12/R13/R17.
- **Difficulty/risk:** XL; high signing/archive compatibility risk.
- **Acceptance:** Measured RSS/scratch improvement on phones with output correctness unchanged; malformed huge offsets fail without large allocation. Any new format is independently validated and documented as supported, not silently attempted.
- **Tests:** Sparse-file boundaries without giant fixtures, interrupted writes, >4 GiB metadata, all existing fuzz/conformance cases, independent tools and physical install/launch matrix for each new format/algorithm.

### R19 — P3 research: Private user-owned loopback TLS identity

- **Files:** experimental branch of `Sources/InstallKit/CertificateFeed.swift`, `LoopbackHost.swift`, `SecretStore.swift`; new transport-identity store; `App/OTAInstallModel.swift`, `InstallSection.swift`; `SECURITY.md` and experiment protocol.
- **Opportunity/evidence:** F17 cannot be fixed by merely signing the public shared-key feed or hiding a hostname.
- **Solution:** Evaluate legitimate issuer-permitted user-owned domain/certificate import and renewal, private key in Keychain, narrowly scoped optional DNS-01 credential. Compare setup/renewal reliability against existing export/server/bucket fallbacks. Keep existing product functional without adopting this experiment.
- **Dependencies:** R8/R12/R14 plus an issuer-policy decision and authorized domain owner. No production issuance/revocation without explicit separate authorization.
- **Difficulty/risk:** L research, potentially XL productization; high operational/security risk.
- **Acceptance:** Document CA-policy feasibility, tested modern-iOS OTA acceptance and renewal/failure behavior; DNS-only substitution fails TLS; no mandatory new server/account for ordinary local signing. If these gates fail, reject the design rather than promising it.
- **Tests:** Controlled domain/DNS and synthetic attacker endpoint in a lab, expired/untrusted/wrong-host identity, Keychain lifecycle, offline renewal/fallback, feed tamper, listener bounds and device installations. Never weaken installer trust.

### R20 — P3: Recoverable jobs, reproducible probes and community diagnostics

- **Files:** proposed `Sources/InstallKit/JobJournal.swift`, diagnostic schema/rule evaluator; `App/JobCoordinator.swift`, `BackgroundJob.swift`, `IdentityReadiness.swift`; proposed versioned probe app/extension project; `docs/compatibility/`.
- **Opportunity:** Termination recovery, meaningful observed capability evidence, and a community corpus without collecting apps or identifiers.
- **Solution:** Split into three reviewable milestones: (a) validated local stage journal and resume/cleanup, (b) nonce-bound probe app/extension tests with explicit observations, (c) opt-in redacted diagnostic export and community-reviewed signed static recipes. No executable remote rules, telemetry, or automatic security bypasses.
- **Dependencies:** R3/R8/R12/R15/R17. Prototype probe source is prerequisite, not an untracked binary replacement.
- **Difficulty/risk:** XL; medium–high persistence/privacy risk.
- **Acceptance:** Recovery preserves originals and never reuses unverified partial stages; probe detection is distinguished from launch/capability execution; reports exclude keys/tokens/UDIDs/install URLs by default; rule evaluation is bounded/offline and cannot patch code or grant entitlements.
- **Tests:** Kill/restart at every journal commit, stale/corrupt manifests, replayed/wrong probe nonce, extension/keychain sandboxed fixtures, report redaction corpus, rule signature/version/size rejection, battery/disk measurements.

## Verification ledger and constraints

Latest branch heads and green checks above were queried from GitHub on 2026-10-19. R9, bucket cleanup and background ownership stack on R3; R11 stacks on R4. Other implementation milestones branch independently from R2/main. Their exact bases are recorded in the inventory. Green individual branches do not establish a combined R3–R14 integration result. All PRs remain open/unmerged.

R3 implementation `28b865d` CI39279219282: **576 package / 13 skips / 0 failures**, unsigned iOS build passed, **253 simulator / 11 skips / 0 failures** (13 app-model, 166 SigningKit, 74 CredentialKit), server45/source3; shell19 assertions. Documentation-only head469a10e also green. R5 initial61b21ca CI39282982588: **540 package / 13 skips / 0 failures**, **240 simulator / 11 skips / 0 failures**, unsigned build passed, server53/source3. Historical pre-integration runs are retained below; current final heads are covered by Final combined CI evidence. Counts include skips; failures were zero and unsigned iOS builds succeeded:

| Item / CI | Package tests / skips | Simulator tests / skips | Additional executed checks |
|---|---:|---:|---|
| R3 39284426692 | 576 /13 | 253 /11 | 13 app-model; server45/source3 |
| R4 39286293647 | 540 /13 | 240 /11 | server45/source15 |
| R5 39304752811 | 540 /13 | 240 /11 | server55/source3; actual SHA cache-hit follow-up |
| R6 39283732825 | 548 /13 | 248 /11 | eight new prefix cases; server45/source3 |
| R7 39285751184 | 550 /13 | 240 /11 | all10 new budget tests including redirect refusal; server45/source3 |
| R12 39287037674 | 540 /13 | 241 /11 | actual source-built probe manifest test passed; server45/source3/probe-packager6 |
| R13 39285180880 | 543 /13 | 243 /11 | three recorder regressions; server45/source3 |
| R14 source cache 39284307056 | 545 /13 | 240 /11 | five source transaction regressions; server45/source3 |
| R9 f16cb5c 39304944244 | 576 /13 | 264 /11 | 24 app-model (all11 new credential cases),74 credential,166 signing; server45/source3 |

The R9 tab-departure correction and later R3 cleanup integrations now have successful final-head CI, as do R8/R10/R11/R14/R16 milestones. Use the final combined table and exact-head inventory instead of substituting earlier evidence. All existing shell assertions run in these workflows. Skips remain environment-dependent, not removed. No combined branch or physical device result is claimed.

Local executed milestones: R4 source tooling15 Python tests; strict offline actual legacy distribution stage validation; R5 strengthened server55 tests; R6 seven isolated actual Foundation-only profile checks; R7 37 actual SourcesKit tests with a temporary Linux FoundationNetworking adapter (committed redirect test runs in macOS CI); R12 six Python probe packaging tests; R13 three actual recorder checks; R14 six actual source transaction/parser checks. Earlier unchanged R1 portable suite33 tests and shell19 assertions passed. None substitutes for Apple integration/device testing. Linux host has no Xcode/Apple SDK; existing offline Swift6.2.3 Docker image provides portable checks only.

Distribution metadata repair is [dylldev/wax PR #1](https://github.com/dylldev/wax/pull/1), staged only. Actual historical IPA0.3.2/build7 IDdev.localsigner.app, 1,254,084 bytes, SHA256 `f2afa54a7e2dbf50a72307a4ae394fa41e15ded71a67be5b71ed61174e3f9fbd`; IPA bytes unchanged. Do not describe this old inspector binary as current signer0.14.1. Deployment and postdeploy ingestion remain owner gates.

### Revalidation of outstanding scope

- R8: PR #13 owns loopback resources/generations (five new TLS/lifecycle tests). PR #17 owns per-job grace/progress and aggregate continued processing (11 new deterministic app tests). OTA preparation/snapshots, serial install/IdentityTester coordinator and pipeline cancellation remain.
- R9: Off-main worker, bounded reads, password retry/cancel/redaction and generation guards implemented with11 new app-model cases. Final view follow-up handles mounted-but-hidden tab departure; successful final combined CI is recorded below.
- R10: R3 addresses shelf truth/provenance; PR #15 fixes observed delivery/probe language and eligibility uncertainty. Certificate-only historical context and immutable result/config binding still remain.23 actual Foundation-only Swift tests passed locally.
- R11: PR #18 adds fresh annotated-tag export/build, toolchain/SDK/configuration/source-built-probe checks, common credential-file refusal and validated candidate staging;26 Python tests pass locally. Its real Mac release path is unexecuted; approved tag/R12 integration required. Protected promotion and rollback remain. Do not run history-rewriting publish scripts.
- R12: Source-built versioned probe replaces opaque resource in its PR; scheme availability is not launch/capability proof. All physical matrix rows remain NOT RUN.
- R13: Parallel timing mutation/shared output fixed in milestone; no measured engine speedup, corpus or phone budget claimed.
- R14: Source-cache milestone ready. PR #14 adds a destination/access-key-bound atomic bucket ledger, strict confirmed DELETE outcomes, legacy retention, retry and preparation/acknowledgment boundaries (21 new tests). Keychain partial outcomes/accessibility migration and broader backup policy remain.
- R15: Unchanged main has no SigningPlan; new PR #21 exposes frozen read-only library decisions and stale-tree rejection, but app/AppEditor preview and production policy adoption remain unfinished.
- R16: R3 isolates same-app downloads across repositories. Details/artwork limits/AX/localization still outstanding. Existing Reduce Motion preserved;035c0dd pauses decorative ticks on hidden/inactive/completed signing screens. Physical Instruments/AX checks remain.
- R17: No SigningGraph/IntegrityReport feature; hashes/CDHashes are groundwork only.
- R18: Whole executable Data/classic-ZIP restrictions remain intentionally unchanged. New formats require conformance and measurement gates.
- R19: Current primary sources corroborate public-domain DNS-01 feasibility and shared-key disclosure/revocation risks. See R19-RESEARCH.md. No authorized domain/issuer context or physical acceptance evidence; no issuance/DNS/Keychain changes made.
- R20: No pipeline JobJournal/JobCoordinator or bounded diagnostic recipe feature. R3 library transactions are not pipeline resume; probe v1 has no nonce/capability execution.

## Performance evidence and resource costs

No new iPhone speed, battery, thermal or peak-RSS result is claimed. R13 fixes measurement correctness before optimization; it does not establish a complete benchmark corpus. Reproduce the existing observations on macOS with `swift test --filter LibraryTransactionTests.testLargeStreamingSaveTimingObservation` and the R2 archive benchmark case in the full package suite. Existing CI39284426692 printed:

- `R3_BENCH bytes=8388608 save_s=0.0626840591430664 buffer_bytes=262144` — one warm-run8MiB file-save observation, not a realistic large-IPA/device benchmark or before/after speedup.
- `R2_BENCH fixture=8MiB mixed-compressibility snapshot_hash_s=0.06616699695587158 compress_and_gate_s=0.3582940101623535 extraction_s=0.08353698253631592 reuse_and_gate_s=0.25481998920440674 archive_bytes=2159571` — synthetic fixture on one CI runner, not a phone result. Timings can vary substantially across runs/cache state.

R7 downloads stream decoded chunks into owned temporary files, enforcing actual-byte caps; later JSON decoding still materializes the bounded source and lacks full object/image budgets. R9 bounds encrypted input to5MiB P12/1MiB profile, but system crypto allocations/CPU and iCloud waits need further measurement. R3 retains pending/staged/stored copies across transaction boundaries; space amplification is intentional for recoverability and must be included in remaining R7 scratch budgets. R14's journal is capped at4MiB/10,000 records and rewrites atomic snapshots; source-cache and cleanup latency remain unmeasured. R5 cache hits now reread/hash actual stored bytes (bounded chunk memory; additional sequential I/O), prioritizing identity correctness over metadata-only speed. R16 pauses decorative schedule ticks, but no measured energy savings or zero-redraw claim is made. R11 is desktop release preparation, with fresh-source/build/stage scratch costs and repeated verification reads; no runtime-phone impact.

For final performance approval, use fixed small/medium/large corpus bytes and runner/OS/toolchain metadata, cold/warm distributions, RSS/CPU/read-write/scratch metrics, iPhone thermal/lock state and matched baseline runs. Never remove integrity/containment checks to achieve a timing target.

## Executed commands and skipped verification

Common macOS CI commands actually run: `swift test`; `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`; `bash scripts/test_make_install_cert.sh`; `bash scripts/test_publish_prep.sh`; `python3 -m unittest discover -s Source -p 'test_*.py'`; `xcodegen generate`; `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`; `xcodebuild test -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination "id=$ID" CODE_SIGNING_ALLOWED=NO` after selecting an available iPhone Simulator with simctl. R12 additionally runs `python3 -m unittest discover -s scripts -p 'test_package_probe.py'` and retains package log/xcresult. Per-run counts/links are above; don't sum duplicate suite executions across branches as unique tests.

Observed package13 skips: eight Keychain entitlement-gated cases (six SystemKeychainTests/two KeychainIdentityTests, errSecMissingEntitlement), two real-profile cases without PROFILE_PATH, one real IPA without IPA_PATH, one live OTA without a configured server, one performance corpus without WAX_PERF_IPA. Simulator11 skips: the eight Keychain cases, two real profiles and performance corpus. These were not disabled by this work. Passing injected app-model policy tests does not prove actual Keychain entitlement/custody behavior on a phone. Modern/legacy PKCS#12 parser/crypto fixture tests do run separately.

Local Linux has no host Swift/Xcode/Apple SDK/simulator. Existing offline Docker Swift6.2.3 provided syntax/portable checks. Actual Foundation-only source/tests passed:23 observation-logic tests in `/tmp/wax-r10-portable`, seven picker-cleanup filesystem tests in `/tmp/wax-picker-portable`; `swift test` was executed inside each bounded offline container package. These extract actual functions/files without substituting fake parser/crypto implementations, but do not replace full Apple integration. Local Python: server55; R4 source15; final R11 source26 (15 R4+11 candidate cases); probe packager6. The full package workflow independently repeats its applicable suites on macOS. No live bucket/server, physical iPhone, power-cut test or protected release-tag candidate build is claimed.

### Final cleanup integration evidence

R3 head `2a045f9` [CI39309629029](https://github.com/dylldev/wax-signer/actions/runs/39309629029) passed:576 package/13 skips/0 failures; unsigned iOS build; **260 simulator/11 skips/0 failures** (20 app-model including all seven picker containment tests,166 SigningKit/3 skips,74 CredentialKit/8 skips), server45/source3 and shell assertions. Its single8MiB save observation was0.07361102104187012s with256KiB chunks; this differs from earlier warm observations and is not a regression benchmark or phone result.

The same cleanup fix was integrated into #12/#14/#17 via ordinary forward merge commits on their development branches, with no history rewrite and no PR/main merge. Their latest combined checks supersede pre-integration evidence. R11's final credential-file/physical-platform gate head524ef77 has its own successful CI39310041670; old candidate-gate runs are not substituted.

## Final combined CI evidence

Latest heads were matched against completed successful workflow head SHAs, and raw logs were read. No queued/older run substitutes for a changed head. Counts include declared skips; every listed failure count is zero.

| PR / head / CI | Package / skips | Simulator / skips | Python server / source |
|---|---:|---:|---:|
| [#3](https://github.com/dylldev/wax-signer/pull/3) `2a045f9` [CI39309629029](https://github.com/dylldev/wax-signer/actions/runs/39309629029) | 576 /13 | 260 /11 | 45 / 3 |
| [#12](https://github.com/dylldev/wax-signer/pull/12) `e607741` [CI39310127468](https://github.com/dylldev/wax-signer/actions/runs/39310127468) | 576 /13 | 271 /11 | 45 / 3 |
| [#14](https://github.com/dylldev/wax-signer/pull/14) `0760cf5` [CI39310132639](https://github.com/dylldev/wax-signer/actions/runs/39310132639) | 589 /13 | 268 /11 | 45 / 3 |
| [#17](https://github.com/dylldev/wax-signer/pull/17) `731e5fc` [CI39310132797](https://github.com/dylldev/wax-signer/actions/runs/39310132797) | 576 /13 | 271 /11 | 45 / 3 |
| [#18](https://github.com/dylldev/wax-signer/pull/18) `524ef77` [CI39310041670](https://github.com/dylldev/wax-signer/actions/runs/39310041670) | 540 /13 | 240 /11 | 45 / 26 |

All five also passed unsigned iOS build and existing shell assertions. R3 model20; R9 model31; bucket ledger model28; background model31. Other independent final green heads are in the inventory above (R4/R5/R6/R7/R8 loopback/R10/R12/R13/R14 source/R16). No all-roadmap combined integration or physical-device result is claimed.

## Exact baseline evidence anchors

These ranges were rechecked using `git show 8ad4b2e:PATH | nl -ba`. They correct approximate line ranges in the individual milestone reports; the mechanisms and fixes are unchanged. Links bind to the immutable R2 source, not a moving branch.

| Confirmed defect | Exact original source |
|---|---|
| Listener stop leaves accepted resources alive | [LoopbackHost.swift:162](https://github.com/dylldev/wax-signer/blob/8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379/Sources/InstallKit/LoopbackHost.swift#L162), lines162–165; unowned accept/read170–184; send/stream below |
| Delivery absence falsely implies nothing installed | [LoopbackHost.swift:60](https://github.com/dylldev/wax-signer/blob/8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379/Sources/InstallKit/LoopbackHost.swift#L60), lines60–65 |
| Cleanup loses original bucket and forgets failures | [OTAInstallModel.swift:167](https://github.com/dylldev/wax-signer/blob/8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379/App/OTAInstallModel.swift#L167), lines167–180 |
| S3 delete discards network/status result | [S3Host.swift:76](https://github.com/dylldev/wax-signer/blob/8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379/Sources/InstallKit/S3Host.swift#L76), lines76–83 |
| Shared grace/title overwritten; global end releases another job | [BackgroundJob.swift:44](https://github.com/dylldev/wax-signer/blob/8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379/App/BackgroundJob.swift#L44), lines44–58,72–79; expiration identity check32–38 |

Independent Apple fixture verification is real but limited: macOS package logs show `testSignedAppPassesAppleCodesignVerification`, `testOutputPassesAppleCodesignAfterNativeRepack`, `testCMSSignatureVerifiesWithIndependentTool`, and system-unzip controls executed/passed. These invoke `/usr/bin/codesign --verify --deep --strict` and OpenSSL CMS verification with controls. OpenSSL `-noverify` does not establish Apple certificate trust, and none proves physical provisioning/install/launch acceptance.

## GitHub implementation inventory

<!-- BEGIN GENERATED PR INVENTORY -->
| Task / PR | Branch → base | Exact head SHA | Latest check |
|---|---|---|---|
| [R3: Make IPA library storage durable and non-destructive](https://github.com/dylldev/wax-signer/pull/3) | `codex/r3-durable-library` → `main` | `2a045f98c18ae2d09fc881c192c13b3828f9f610` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39309629029/job/118255543908) |
| [R4: Generate coherent distribution metadata from verified IPA artifacts](https://github.com/dylldev/wax-signer/pull/4) | `codex/r4-distribution-correctness` → `main` | `45342312868f6e31af28f1b7402edcdc55631b2e` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39286293647/job/118173356289) |
| [R5: Isolate OTA uploads and protect active session publication](https://github.com/dylldev/wax-signer/pull/5) | `codex/r5-ota-upload-reliability` → `main` | `3e30326629fa1db3536b0e03dd994122b502fa47` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39304752811/job/118238801038) |
| [R6: Preserve App ID prefixes independently of Team IDs](https://github.com/dylldev/wax-signer/pull/7) | `codex/r6-app-id-prefix` → `main` | `3ef32fec540cc7af3ea979ce9cb2b17a42786d8a` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39283732825/job/118163751366) |
| [R14: Serialize source cache commits and invalidate obsolete ETags](https://github.com/dylldev/wax-signer/pull/8) | `codex/r14-source-cache-transactions` → `main` | `be5c53c6a63c0f8d5dd2a86e41f1f0b90a74d249` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39284307056/job/118165791707) |
| [R13: Make benchmark timing collection deterministic and race-free](https://github.com/dylldev/wax-signer/pull/9) | `codex/r13-performance-evidence` → `main` | `6d4ccf0e8bfeee2d4bc22b06cccc4e1c9d2cd6ef` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39285180880/job/118168980153) |
| [R7: Enforce source and IPA download budgets during acquisition](https://github.com/dylldev/wax-signer/pull/10) | `codex/r7-download-budgets` → `main` | `023a29b67390575f1815b99c8526ccbbd5822880` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39285751184/job/118171077801) |
| [R12: Build the installation probe from source and retain CI evidence](https://github.com/dylldev/wax-signer/pull/11) | `codex/r12-probe-conformance` → `main` | `afb1ce598c4de957c9edaecc555cecdd77570a65` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39287037674/job/118176687596) |
| [R9: Keep credential imports responsive and retryable](https://github.com/dylldev/wax-signer/pull/12) | `codex/r9-responsive-import` → `codex/r3-durable-library` | `e60774128ce0d7b48c679af4583d5afb9356bb85` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310127468/job/118257236365) |
| [R8: Own loopback transfers across stop and republish](https://github.com/dylldev/wax-signer/pull/13) | `codex/r8-loopback-session-ownership` → `main` | `0a044e02d753c93d65b1200700a206532e50183c` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39305374860/job/118240929086) |
| [R14: Retain destination-bound bucket cleanup obligations](https://github.com/dylldev/wax-signer/pull/14) | `codex/r14-bucket-cleanup-ledger` → `codex/r3-durable-library` | `0760cf52adb02a47cfb5ae0dcb853a20a27f147a` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310132639/job/118257253470) |
| [R10: Report delivery and probe observations without installation claims](https://github.com/dylldev/wax-signer/pull/15) | `codex/r10-install-observation-language` → `main` | `73d3020f92781a3978e7ba7a857537fb48a04f91` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39306630462/job/118245275860) |
| [R16: Pause decorative signing animation when hidden or inactive](https://github.com/dylldev/wax-signer/pull/16) | `codex/r16-pause-hidden-animation` → `main` | `035c0ddc3e6c91667747644e9ff07ec07d074b99` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39306866626/job/118246083078) |
| [R8: Isolate background resources for concurrent operations](https://github.com/dylldev/wax-signer/pull/17) | `codex/r8-background-job-ownership` → `codex/r3-durable-library` | `731e5fc46d30e0c1520c7b561bce6687dc691932` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310132797/job/118257254509) |
| [R11: Prepare validated release candidates from tagged sources](https://github.com/dylldev/wax-signer/pull/18) | `codex/r11-release-candidate-gate` → `codex/r4-distribution-correctness` | `524ef773ab58784440347165bdde65fc106cefb0` | [SUCCESS](https://github.com/dylldev/wax-signer/actions/runs/39310041670/job/118256951748) |
| R4 distribution repair | `codex/r4-distribution-correctness` → `main` in dylldev/wax | `2bce8857accc063316f08854eec8afb887ca903a` | [PR #1](https://github.com/dylldev/wax/pull/1); offline stage validation passed; no deployed update/CI configured |
<!-- END GENERATED PR INVENTORY -->

## Physical-device verification matrix (all unexecuted here)

Record exact source/build SHA, iPhone model/iOS, credential kind and public fingerprints only. Never record private keys/passwords/UDIDs/install capability URLs. Use owner-authorized material outside Git.

| Journey | Required observations | Gate |
|---|---|---|
| Certificate/profile import | Modern/legacy P12, wrong-password retry, cancellation, Keychain error and responsiveness | R6/R7/R9/R14 |
| IPA import/library | Files/iCloud lease, duplicate vs distinct builds, low space, restart at transaction boundaries, previous artifact SHA retained | R3/R7/R8 |
| Normal signing | Final IPA codesign/CMS verification distinct from profile/trust acceptance | R6/R12/R15 |
| Nested app/extensions/frameworks | Independent final-byte verification, actual app and extension launch, entitlement/keychain behavior | R6/R12/R18 |
| App modifications/library injection | Planned vs actual changes, supported framework/library fixture, no unauthorized capability | R12/R15 |
| Save/export | Save failure retains report/output, retry without resign, real share sheet succeeds, VoiceOver tells actual outcome | R3/R10/R16 |
| Installation | Loopback/server/bucket separately: delivery, OS prompt, install observed, launch observed; expiration/retry/change host | R8/R10/R12/R19 |
| Termination/low storage | Kill/lock/background expiration at each stage, recover originals, compare previous IPA digests | R3/R7/R8/R20 |
| Accessibility | AX1–AX5 narrow phone, Dynamic Type, VoiceOver, Reduce Motion, light/dark | R16 |

No physical installation, launch, power-cut durability, phone performance or issuer-policy success is claimed. R19 requires a separately authorized domain/CA policy decision; no issuance or production DNS changes. R18 new formats/algorithms need independent conformance before support claims. R12/R19/R20 device-dependent acceptance remains open until real evidence exists.

## Implementation file inventory

Exact net PR file lists, retrieved from GitHub after the R3 dependency integrations. Tests and reports are included; unrelated untracked audit artifacts are excluded.

| PR / scope | Files |
|---|---|
| [#3](https://github.com/dylldev/wax-signer/pull/3) | `App/ContentView.swift`, `App/DocumentPicker.swift`, `App/LibraryModel.swift`, `App/SettingsView.swift`, `App/SignView.swift`, `App/SigningModel.swift`, `App/SourcesModel.swift`, `App/SourcesView.swift`, `Sources/InstallKit/IPALibrary.swift`, `Sources/InstallKit/LibraryFileIO.swift`, `Tests/AppModelTests/LibraryOutcomeTests.swift`, `Tests/AppModelTests/PickerCopyCleanupTests.swift`, `Tests/InstallKitTests/IPALibraryTests.swift`, `Tests/InstallKitTests/LibraryTransactionTests.swift`, `docs/audits/2026-10-19/R3-IMPLEMENTATION.md`, `project.yml` |
| [#5](https://github.com/dylldev/wax-signer/pull/5) | `Server/wax-ota/README.md`, `Server/wax-ota/test_wax_ota.py`, `Server/wax-ota/wax_ota.py`, `docs/audits/2026-10-19/R5-IMPLEMENTATION.md` |
| [#12](https://github.com/dylldev/wax-signer/pull/12) | `App/CredentialsModel.swift`, `App/CredentialsView.swift`, `Tests/AppModelTests/CredentialImportOutcomeTests.swift`, `docs/audits/2026-10-19/R9-IMPLEMENTATION.md` |
| [#13](https://github.com/dylldev/wax-signer/pull/13) | `Sources/InstallKit/LoopbackHost.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift`, `docs/audits/2026-10-19/R8-LOOPBACK-OWNERSHIP.md` |
| [#14](https://github.com/dylldev/wax-signer/pull/14) | `App/InstallSection.swift`, `App/OTAInstallModel.swift`, `Sources/InstallKit/BucketCleanupStore.swift`, `Sources/InstallKit/S3Host.swift`, `Tests/AppModelTests/BucketCleanupOutcomeTests.swift`, `Tests/InstallKitTests/BucketCleanupStoreTests.swift`, `Tests/InstallKitTests/S3HostTests.swift`, `docs/audits/2026-10-19/R14-BUCKET-CLEANUP.md` |
| [#15](https://github.com/dylldev/wax-signer/pull/15) | `App/IdentityReadiness.swift`, `Sources/InstallKit/IdentityStatus.swift`, `Sources/InstallKit/LoopbackHost.swift`, `Sources/InstallKit/SignScreenLogic.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift`, `Tests/InstallKitTests/SignScreenLogicTests.swift`, `docs/audits/2026-10-19/R10-OBSERVATION-LANGUAGE.md` |
| [#16](https://github.com/dylldev/wax-signer/pull/16) | `App/SignView.swift`, `App/WaxMelt.swift`, `docs/audits/2026-10-19/R16-ANIMATION-LIFETIME.md` |
| [#17](https://github.com/dylldev/wax-signer/pull/17) | `App/BackgroundJob.swift`, `App/SigningModel.swift`, `App/SourcesModel.swift`, `Tests/AppModelTests/BackgroundJobOutcomeTests.swift`, `docs/audits/2026-10-19/R8-BACKGROUND-OWNERSHIP.md` |
| [#18](https://github.com/dylldev/wax-signer/pull/18) | `Source/RELEASE-CANDIDATES.md`, `Source/prepare_release.py`, `Source/test_prepare_release.py`, `docs/audits/2026-10-19/R11-CANDIDATE-GATE.md` |

## Prior checkpoint continuation (superseded by the resumption below)

1. All listed final code heads are green as observed; re-fetch before resuming and inspect any newer actual failures. R3 cleanup follow-up2a045f9 was merged **only into its dependent development branches** (#12/#14/#17); no PR was merged into main. Those children have current combined CI, not only older green runs. Exact checks are in the inventory. Evidence collection for these frozen code heads is complete; don't add cosmetic commits that unnecessarily restart full CI.
2. Next implementation: finish original P1 R8 OTA ownership. `App/OTAInstallModel.upload` must own busy state before certificate/feed/cleanup awaits, retain a cancellable task, snapshot host/credentials/configuration, generation-check progress/completion, and bind finishPhoneTransfer to its original host/session rather than live settings. Serial admission must stop IdentityTester from replacing a live install; stop/cancel must never stop a newer host. Build on the bucket-ledger branch explicitly, preserving prepared/acknowledged cleanup records. Test delayed preparation, overlapping test/install, settings edits, cancellation before/after readiness, stale completion, host changes during delivery and retained signed-output recovery. Keep actual install/launch claims separate.
3. Finish remaining R7 budgets (InstallTransport/CertificateFeed responses and silent-body cancellation, extraction/worker/scratch budgets, source object/image pixels); retain R1/R2 checks. Current network milestone and credential read caps do not complete original R7.
4. Then implement R15 immutable read-only preflight/plan parity, R10 result/configuration and contextual observations, remaining R14 secret migrations, and R16 details/artwork/AX. R17 depends on real R15 plans; R18/R20 larger work is not done. R11 approved-tag live build/promotion and R12/R19 physical gates remain explicit. Unmerged branches can be stacked, but no new PR may be merged without later authorization/review.
5. Preserve untouched untracked original audit artifacts; all code worktrees should be clean and pushed. Record final-head CI summaries in this report/PR descriptions; do not label queued checks successful. End state remains PARTIALLY COMPLETE until outstanding original scope is implemented or evidence-backed resolved.

## End-of-batch repository state

Main remains `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`; no new PR merged. All implementation branches are committed/pushed and clean. Primary R3 workspace retains only the original untracked audit artifacts, deliberately untouched. Distribution main remains `d4d4ca79160e75f9dc119b9e6ab4bf8908f16123`; its repair is an open branch/PR, not a live deployment. This checkpoint and primary-source R19 research live on the documentation branch/PR #6. Its final documentation-only CI may run after this report update and must not be described as already successful before observed.


## Resumption: R8 ownership, remaining R7 budgets and R15 foundation

This resumption started from committed PR#6 checkpoint `ea1d3ebf980080f83aaff06d8f454693f639f2be`; source main was re-fetched and remains `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`. No previous implementation was repeated, no PR merged and no production deployment/release occurred. Original untracked audit artifacts remain untouched. Earlier documentation-head CI39312680325 also passed; it does not verify newly changed code.

### New focused PRs

| Scope | Branch / explicit base | Final source head | Actual final-head CI |
|---|---|---|---|
| R8 OTA owner/session coordination | `codex/r8-ota-session-ownership` → `codex/r8-session-prerequisites`; [#19](https://github.com/dylldev/wax-signer/pull/19) | `b7edd93e975cbdb48a90169f2aa6f159363d8634` | [39318615526](https://github.com/dylldev/wax-signer/actions/runs/39318615526): **SUCCESS**, package594/13 skips; Simulator296/11 skips;0 failures; unsigned iOS build passed |
| R7 install response/feed budgets | `codex/r7-install-response-budgets` → `codex/r14-bucket-cleanup-ledger`; [#20](https://github.com/dylldev/wax-signer/pull/20) | `de21fa573a27f19293a112c9db5d8465266c5230` | [39317651235](https://github.com/dylldev/wax-signer/actions/runs/39317651235): **SUCCESS**, package602/13 skips; Simulator268/11 skips;0 failures; unsigned iOS build passed |
| R15 immutable library signing plan | `codex/r15-read-only-signing-plan` → `codex/r6-app-id-prefix`; [#21](https://github.com/dylldev/wax-signer/pull/21) | `c8248a8f0385a460a59864e1c31e3224984bcee5` | [39317698285](https://github.com/dylldev/wax-signer/actions/runs/39317698285): **SUCCESS**, package564/13 skips; Simulator263/11 skips;0 failures; unsigned iOS build passed |
| R7 bounded custom-icon read/decode | `codex/r7-icon-input-budgets` → `main`; [#22](https://github.com/dylldev/wax-signer/pull/22) | `698b741c0d679a78b3b0fc29c20a6ad9df43ec0f` | [39318320934](https://github.com/dylldev/wax-signer/actions/runs/39318320934): **SUCCESS**, package548/13 skips; Simulator248/11 skips;0 failures; unsigned iOS build passed |

Composite development base `codex/r8-session-prerequisites` (`6b926e3`) ordinarily merges unchanged #14 + #17 + #13, including current R3. It exists to review only the new #19 delta while CI exercises those prerequisites together. It must not be merged as a shortcut around the prerequisite PR reviews. #20 explicitly includes R14's confirmed DELETE/ledger tests. #21 inherits R6 prefix behavior. All four new PRs remain open for independent review.

### Implemented behavior and exact scope

- **R8:** serial reservations before signing or host awaits; immutable feed/endpoint/token/bucket snapshots; retained cancellable publication/delivery tasks; generation-scoped progress/readiness/completion; original-host completion independent of live settings; immediate owner invalidation on cancellation/reset. Probe and real install cannot silently replace each other. Signed outputs survive canceled/failed tests; synthetic probes use unique app-owned backup-excluded storage. Setup checks/cleanup notes cannot overwrite a newer configuration or active installation. Signing result controls cancel only their own session; delayed notification activation cannot open over a new operation. R3 artifact journals and R14 preparation-before-PUT/expiry-before-link remain mandatory. Fully cooperative page/file-level signing-engine cancellation, durable job resumption and synthetic-probe retention management are still unfinished original scope.
- **R7 install responses:** chunk-enforced decoded-body caps, monotonic total deadlines including silent headers/body, once-only cancellation with underlying task invalidation, bounded cache reads, no cached success on cancellation.1MiB default control/reply cap,64KiB feed cap,20s control/30min upload total defaults. HTTPS/five redirects; authenticated origin restriction; DELETE never redirects. Custom trust delegates/background sessions are explicitly refused rather than silently discarded.
- **R15:** read-only plan accepts only public certificate bytes; exposes per-bundle profiles/rejections, original/final IDs, CMS status and requested/signed entitlement XML. Freezes caller containers/profile bytes; bounds report size; reuses actual planner and entitlement resolver; R2 manifest recheck before execution; once-only plan; exact certificate-chain and expiry recheck. Unknown profile pins refused. Adjacent confirmed defect fixed: trust cache keyed by attacker-controlled UUID could reuse another CMS's status; it now keys by exact raw bytes. Direct app signing policy/order remains compatible. Full app production-policy/UI/AppEditor preflight is not delivered by this milestone.
- **R7 icons:** FileRepresentation reads inside the provider lease, actual16MiB cap, metadata64MiPixel/32,768-dimension bounds before pixel decode,152px thumbnail for preview/editor. Retained generation-owned worker ignores late pick/reset/dismiss callbacks. No provider source is deleted. System-managed Photos acquisition is outside Wax's read budget. Actual codec/phone memory and provider behavior remain unmeasured.

Implementation reports: each new branch contains `R8-OTA-OWNERSHIP.md`, `R7-INSTALL-RESPONSE-BUDGETS.md`, `R15-SIGNING-PLAN.md` or `R7-ICON-BUDGETS.md` respectively under this audit directory. Their initial CI-pending text describes publication-time state; this checkpoint/PR body supplies observed final-head results.

### Verification evidence

- Original #19 head `ee2182d` passed CI39315787954:594 package tests/13 skips/0 failures; unsigned iOS build;292 Simulator tests/11 skips/0 failures (52 model,166 signing,74 credentials), including13 new OTA cases. This is **not** substituted for final `b7edd93` verification, which adds already-canceled caller, cleanup-note and result-control/notification tests (17 OTA model cases total).
- #20 initial runs39316253718/39316935167 each ran601 package tests/13 skips with one failure: an unfinished short synthetic URLProtocol response yielded a deadline rather than exposing headers early on Darwin. Header policy now has direct pre-body/overflow coverage plus an empty-completed-body integration test, where actual bytes cannot trip the size cap. Silent-response deadlines and actual chunk limits remain enabled. No production limit/rejection was weakened.13 new response/feed tests.
- #21 adds16 macOS plan cases (15 on iOS), including independent `/usr/bin/codesign --verify --deep --strict`, stale resource/executable/mode/link, wrong chain, once-only attempts, expiry, strict/dropped grants, CMS/duplicate UUID trust status and container isolation. #22 adds8 bounded-icon tests. Final CI summaries follow when observed.
- Local offline Swift6.2.3 frontend parsing passed for changed sources/tests. A temporary portable harness compiled the **actual** InstallTransport/tests with only FoundationNetworking imports; feed/Security cases are excluded only from that Linux harness and remain committed/enabled on macOS. Its final11 transport tests passed/0 failures; this is not full Apple verification. Logs: `/tmp/wax-response-portable-final.log`. No host Xcode/Apple SDK or iPhone exists here.
- Superseded queued/running workflow heads were canceled to conserve runners; final heads must each complete their own required CI. Earlier greens/canceled workflows are never reported as final verification.

### Non-destructive integration assessment

[OPEN-PR-INTEGRATION.md](OPEN-PR-INTEGRATION.md) contains every open source PR's frozen SHA/base, the distribution PR, exact recommended merge order, pairwise merge-tree evidence, explicit dependency chains and required combined regressions. Virtual non-published sequential merges combined #3/#4/#5/#7/#8/#9/#10/#12/#13/#14/#17 cleanly, then stopped at #15's loopback-test conflict. Other confirmed conflicts are #19 with #15/#11 in IdentityReadiness (and inherited loopback tests). No conflict was resolved by dropping tests or replacing an entire side; no published/main merge was performed. Clean text merges still need combined cache/download, credential UI, bucket/deadline/coordinator, R3/background/signing and probe/project tests. New individual CI greens are not a complete-integration green.

### Next exact action after this resumption

1. Final-head #19/#20/#21/#22 CI above is SUCCESS as observed at23:45UTC; logs were downloaded and actual suite/build summaries inspected. Keep PRs open and re-fetch changes before later continuation. All four ran server45/source3 Python tests and both shell assertion scripts successfully; earlier #5 server55 and #4/#18 source15/26 remain separately verified, not implicitly integrated here.
2. Continue original R7 extraction/scratch/worker/object budgets: IPAExtractor still validates declared totals/entry counts but lacks disk-reserve/deadline budgets during work; ZipArchive streams CRC/SHA-256 with declared size limits (keep those). Per-entry in-memory cap is already16MiB; don't falsely call it unbounded. ExternalFile/provider waits, Mach-O/DEB worker memory and source-artwork decode require their own budgets. R1 already caps **uncompressed** tar1GiB; don't reimplement a solved tar limit. R3 inspector rejects classic ZIP input over4GiB before picker copying; preserve that early rejection and recovery transaction.
3. Complete R15 app workflow on explicit dependencies: preview edits on owned scratch with deterministic randomization/injection snapshots; production policy rejects invalid CMS while distinguishing unknown trust; per-bundle override UI and strict entitlement mode; stale IPA/config detection; execution must use the confirmed plan and still pass R2's final packaged-byte gate. Current plan API only covers an **already edited unpacked tree**, not an IPA/settings preview.
4. Remaining original R8: cooperative cancellation at safe file/page boundaries without interrupting final publication, background-expiration propagation, explicit bounded synthetic-probe retention; then R10 contextual result/retry history, R14 secret/Keychain reconciliation and R16 details/artwork/AX. R17–R20 dependencies/physical/CA gates remain as originally inventoried. Do not rename partial foundations as completed original tasks.
5. Follow integration report only after independent approvals and current checks/protections. Never merge #19's composite base to bypass #3/#13/#14/#17 review; no current authorization to merge these new PRs. No Pages/server/release deployment or private credential access.


### Final observed verification and exact code anchors

All four runs used `swift test`, `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`, both `bash scripts/test_make_install_cert.sh`/`test_publish_prep.sh`, `python3 -m unittest discover -s Source -p 'test_*.py'`, XcodeGen generation, unsigned generic-iOS `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`, and the configured iPhone Simulator `xcodebuild test ... CODE_SIGNING_ALLOWED=NO`. Counts include skips (package13, Simulator11); skip causes remain those cataloged above, not new exclusions. R1/R2/regression suites and existing codesign/CMS controls remained enabled. #21's new planned-output independent Apple codesign test actually executed and passed. No physical-iPhone test, launch, issuer-policy experiment or phone benchmark ran.

| Verified change | Original anchor | New anchor / regression |
|---|---|---|
| R8 host readiness/publication/completion ownership | `0760cf5:App/OTAInstallModel.swift:218,236,275` (live-host completion, preparation before busy) | `b7edd93:App/OTAInstallModel.swift:284,310,333,386`;17 `OTASessionOutcomeTests` |
| R8 result controls/notification ownership | inherited SignView global reset and unretained delayed open | `b7edd93:App/SigningModel.swift:121,128,139`, `IdentityReadiness.swift:97,171`; canceled/overlap/poll/notification outcome tests |
| R7 full response allocation/silent body | `8ad4b2e:Sources/InstallKit/InstallTransport.swift:5,10`; feed deadline only advanced on byte arrival | `de21fa5:InstallTransport.swift:37,50,138`;13 `InstallResponseBudgetTests` |
| R15 shared immutable plan and exact CMS trust identity | `3ef32fe:BundleSigner.swift:102,192,265` (UUID cache/private plan) | `c8248a8:BundleSigner.swift:70,200,364,438`;16 macOS/15 iOS `SigningPlanTests` |
| R7 icon materialization/decode | `8ad4b2e:App/SigningOptionsView.swift:161`, `AppEditor.swift:106` | `698b741:Sources/SigningKit/BoundedIcon.swift:27,41,50,66`;8 `BoundedIconTests` |

Final source heads are frozen in the preceding table and match GitHub PR heads. Documentation PR#6 may acquire a later doc-only commit; its own starting checkpoint SHA in the integration inventory is historical, not a claim that the new documentation head already passed CI. No source branch was modified merely to update publication-time pending text; final results are maintained here and in each PR body.
