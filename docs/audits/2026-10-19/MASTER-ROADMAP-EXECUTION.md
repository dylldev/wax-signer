# Wax master roadmap execution checkpoint

Baseline source: `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379` (R2 merge); R1 ancestor `ff50f001f8ee768b5fe3cbd5835377bc563fd2b9`. Distribution baseline: `d4d4ca79160e75f9dc119b9e6ab4bf8908f16123`.

Original definitions recovered from the existing, untracked `ROADMAP.md` and `WAX-ENGINEERING-AUDIT.md` under `/workspace/wax-signer/docs/audits/2026-10-19/`. Those source artifacts are read-only and are not added by this program. Inventory below transcribes their actual descriptions, dependencies, scope and acceptance criteria; it does not invent replacement R identifiers.

No newly implemented PR may be merged automatically. No releases, deployments, credential changes or user-IPA uploads are authorized. This is a continuation checkpoint, not a claim that every item is complete.

## Priority and dependency order

First finish R3 verification, without waiting indefinitely for its independent review. Independent P0 R4 and P1 R5 proceed from main. Next prioritize P1 R6/R7/R8/R9 and the R12 release gate. R10 depends on R3/R8; R14 depends on R3/R6/R8. R11 follows R4; R13 measurement precedes R18 optimization. R15 precedes R17, while R19 requires issuer-policy/domain/device evidence. R20 consists of three separate milestones and cannot be called complete from the R3 artifact journal alone.

## Status ledger

| ID | Original task | State / disposition | Branch / PR / verification |
|---|---|---|---|
| R3 | P1: Durable non-destructive library | Ready for review — implemented with device/durability limitations | `codex/r3-durable-library`, [PR #3](https://github.com/dylldev/wax-signer/pull/3), `469a10e`, [green CI 39284426692](https://github.com/dylldev/wax-signer/actions/runs/39284426692) |
| R4 | P0: Cohesive distribution update | Ready for review — staged repair; no publication | `codex/r4-distribution-correctness`, [PR #4](https://github.com/dylldev/wax-signer/pull/4), `4534231`, [green CI 39286293647](https://github.com/dylldev/wax-signer/actions/runs/39286293647) |
| R5 | P1: Isolate uploads/session mutation | Testing follow-up — initial implementation green; actual hash-hit verification uncommitted | `codex/r5-ota-upload-reliability`, [PR #5](https://github.com/dylldev/wax-signer/pull/5), `61b21ca`, [green CI 39282982588](https://github.com/dylldev/wax-signer/actions/runs/39282982588) |
| R6 | P1: Independent App ID prefixes | Ready for review — implemented; real-profile/keychain device gate open | `codex/r6-app-id-prefix`, [PR #7](https://github.com/dylldev/wax-signer/pull/7), `3ef32fe`, [green CI 39283732825](https://github.com/dylldev/wax-signer/actions/runs/39283732825) |
| R7 | P1: Input/scratch budgets | Partial milestone ready for review — network budgets; remaining local/extraction/image budgets not completed | `codex/r7-download-budgets`, [PR #10](https://github.com/dylldev/wax-signer/pull/10), `023a29b`, [green CI 39285751184](https://github.com/dylldev/wax-signer/actions/runs/39285751184) |
| R8 | P1: Job/cancellation/session ownership | Investigated — not completed | See revalidation and continuation below |
| R9 | P1: Responsive retryable imports | Implementing — two uncommitted app files; stacked on R3; tests pending | See revalidation and continuation below |
| R10 | P2: Truthful result/retry state | Partial groundwork in R3; result snapshots/probe observations/delivery semantics not completed | See revalidation and continuation below |
| R11 | P2 release gate: Artifact/feed consistency | Partial groundwork in R4; immutable-tag provenance/promotion automation not completed | See revalidation and continuation below |
| R12 | P1 release gate: Independent/device conformance | Partial milestone ready for review — source-built probe/CI evidence; physical controls not run | `codex/r12-probe-conformance`, [PR #11](https://github.com/dylldev/wax-signer/pull/11), `afb1ce5`, [green CI 39287037674](https://github.com/dylldev/wax-signer/actions/runs/39287037674) |
| R13 | P2: Trustworthy performance measurements | Partial milestone ready for review — synchronized timing/output isolation; corpus/metrics/phone budgets not completed | `codex/r13-performance-evidence`, [PR #9](https://github.com/dylldev/wax-signer/pull/9), `6d4ccf0`, [green CI 39285180880](https://github.com/dylldev/wax-signer/actions/runs/39285180880) |
| R14 | P2: Persistence/secrets/host cleanup | Partial milestone ready for review — source-cache transactions; secret/bucket migrations not completed | `codex/r14-source-cache-transactions`, [PR #8](https://github.com/dylldev/wax-signer/pull/8), `be5c53c`, [green CI 39284307056](https://github.com/dylldev/wax-signer/actions/runs/39284307056) |
| R15 | P2: Read-only preflight/change preview | Investigated — not completed | See revalidation and continuation below |
| R16 | P2: Source browsing/accessibility | R3 source-scoped download state resolved; other scope not completed | See revalidation and continuation below |
| R17 | P3: Signing graph/integrity history | Investigated — not completed | See revalidation and continuation below |
| R18 | P3: Measured engine/new formats | Investigated — not completed; R12/R13/R17 gates remain | See revalidation and continuation below |
| R19 | P3 research: User-owned loopback TLS | Not implemented; authorized domain/issuer-policy and physical device dependencies | See revalidation and continuation below |
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

Latest branch heads and green checks above were queried from GitHub on 2026-10-19. Each is an independent branch from R2/main, except R9, which intentionally stacks on R3. Green individual branches do not establish a combined R3–R14 integration result. All PRs remain open/unmerged.

R3 implementation `28b865d` CI39279219282: **576 package / 13 skips / 0 failures**, unsigned iOS build passed, **253 simulator / 11 skips / 0 failures** (13 app-model, 166 SigningKit, 74 CredentialKit), server45/source3; shell19 assertions. Documentation-only head469a10e also green. R5 initial61b21ca CI39282982588: **540 package / 13 skips / 0 failures**, **240 simulator / 11 skips / 0 failures**, unsigned build passed, server53/source3. Later green-run logs are being collected for exact counts rather than extrapolating.

Local executed milestones: R4 source tooling15 Python tests; strict offline actual legacy distribution stage validation; R5 strengthened server55 tests; R6 seven isolated actual Foundation-only profile checks; R7 37 actual SourcesKit tests with a temporary Linux FoundationNetworking adapter (committed redirect test runs in macOS CI); R12 six Python probe packaging tests; R13 three actual recorder checks; R14 six actual source transaction/parser checks. Earlier unchanged R1 portable suite33 tests and shell19 assertions passed. None substitutes for Apple integration/device testing. Linux host has no Xcode/Apple SDK; existing offline Swift6.2.3 Docker image provides portable checks only.

Distribution metadata repair is [dylldev/wax PR #1](https://github.com/dylldev/wax/pull/1), staged only. Actual historical IPA0.3.2/build7 IDdev.localsigner.app, 1,254,084 bytes, SHA256 `f2afa54a7e2dbf50a72307a4ae394fa41e15ded71a67be5b71ed61174e3f9fbd`; IPA bytes unchanged. Do not describe this old inspector binary as current signer0.14.1. Deployment and postdeploy ingestion remain owner gates.

### Revalidation of outstanding scope

- R8: BackgroundJob singleton begin can overwrite grace/task state; LoopbackHost.stopLocked does not own accepted connections; OTA preparation can await before busy. These remain beyond downloader cancellation fixes.
- R9: MainActor credential crypto/persistence and lost password retry reproduced structurally; worker/read-bound/state implementation in `/workspace/wax-r9` needs tests/commit/stacked PR.
- R10: R3 addresses shelf truth/provenance; certificate-only InstallTestStore, old result/config binding and delivery-versus-install wording remain.
- R11: Current release scripts lack immutable-tag/toolchain provenance and separated reviewed promotion. Do not run history-rewriting publish scripts.
- R12: Source-built versioned probe replaces opaque resource in its PR; scheme availability is not launch/capability proof. All physical matrix rows remain NOT RUN.
- R13: Parallel timing mutation/shared output fixed in milestone; no measured engine speedup, corpus or phone budget claimed.
- R14: Source ETag/cache generation races fixed in milestone; Keychain partial outcomes/backup policy and bucket cleanup records bound to original host remain.
- R15: No immutable SigningPlan/preview parity contract; decisions remain inside signing.
- R16: R3 isolates same-app downloads across repositories. Details/artwork limits/AX/localization still outstanding. Existing Reduce Motion support must be preserved, not reported absent.
- R17: No SigningGraph/IntegrityReport feature; hashes/CDHashes are groundwork only.
- R18: Whole executable Data/classic-ZIP restrictions remain intentionally unchanged. New formats require conformance and measurement gates.
- R19: SECURITY.md public shared-key architectural risks remain; no authorized domain, issuer-policy or physical OTA acceptance evidence; no issuance/DNS changes made.
- R20: No pipeline JobJournal/JobCoordinator or bounded diagnostic recipe feature. R3 library transactions are not pipeline resume; probe v1 has no nonce/capability execution.

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

## Next exact action

1. Commit/push the tested R5 actual-SHA cache-hit verification (four dirty files in `/workspace/wax-r5`; local55 tests green), update PR #5, inspect final CI.
2. Finish R9 `/workspace/wax-r9`: add model tests for off-main slow import, repeated password retry/cancel/redaction/read caps; review guards and view actions; target PR at `codex/r3-durable-library`. Do not merge its dependency.
3. Collect exact green logs/counts for R4/R6/R7/R12/R13/R14 and update PR descriptions. Continue next independent P1 R8 ownership milestone, then remaining original scope. Do not mistake partial milestones for completed roadmap tasks.
4. Update this checkpoint after each tested/pushed milestone. Preserve untracked original audit files. All new PRs remain unmerged. No releases/deployments/device success claims.
