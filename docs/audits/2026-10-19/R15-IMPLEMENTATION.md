# R15 — Prepared IPA preview and confirmation

Baseline: R7 squash merge `b4214fe592f4d391a3851cd19d2c0ea21a94c4d2` (PR #28), reviewed head `11aada4954cf8cab17a807b2fc08e08f3f2b09fe`, CI [39495578350](https://github.com/dylldev/wax-signer/actions/runs/39495578350) passed 713 package tests (13 environment skips) and 366 Simulator tests (11 skips), unsigned iOS build, Python/shell and independent codesign/CMS controls. No review blockers or protection exceptions.

## Architecture

Previously `IPASigner.sign` (baseline lines 28–85) extracted, edited and resolved while signing; `BundleSigner.plan` (baseline lines 73–149) only accepted a caller-owned unpacked tree. `SigningModel.sign` (baseline lines 292–432) directly invoked the former, with no confirmation gate.

`PreparedIPA` owns exclusive mkdtemp scratch, one extraction inventory, edits and generated identifiers, immutable resolver decisions, whole-source SHA-256 and a whole-Payload manifest. Public preview values expose no scratch URLs, private keys or execution capability. Confirmation consumes the lease once, rejects changed source/tree/identity and expired credentials, then executes the existing real resolver's frozen decisions. The original direct API remains compatible; the application now exclusively uses preparation plus confirmation.

Preparation and hashing run on workers. R7 extraction/packaging limits and bounded worker queues remain active. Prepared bytes, code sizes, input library count and monotonic lifetime are additionally bounded. Preview expires after at most 15 minutes by default; leaving/canceling invalidates ownership and disposes only its scratch. Cancellation cannot remove scratch underneath execution. No cancellation is observed after the existing publication seal; R2's actual staged ZIP verification and atomic promotion remain mandatory.

The app invalidates previews on edits, profile choices, certificate changes or entitlement policy changes. Raw credential profile bytes are compared again before execution, and the identity chain/validity is checked by the plan. Installation reserves an R8 session only after confirmation. R3's durable signed pending output remains outside scratch and survives shelf failure, retry, export and starting over.

## Explicit production policy

The new app path requires cryptographically valid CMS for each selected profile. Invalid CMS is refused before signing. Valid-but-untrusted profiles remain usable with an explicit unknown-Apple-trust warning; Apple-chain verification is separately labeled. Neither state proves revocation, eligibility, installation or launch. Synthetic tests may explicitly request the pre-existing fixture policy, never via UI. Legacy direct `IPASigner.sign` semantics are preserved for existing library clients.

Strict-entitlement mode and per-bundle profile overrides use the existing resolver. Unknown paths and incompatible choices fail. Changing an override discards the old preview; users prepare again rather than confirming stale decisions. Requested versus signed XML values and dropped/rewritten keys are shown before confirmation, along with code inventory, app/version/build changes, profile rejection reasons and prefix/keychain implications.

## Verification (in progress)

New `PreparedIPATests` exercise actual prepared/sign/repacked bytes, source/tree tampering, one-shot confirmation, strict capabilities, profile overrides, CMS policy, cancellation, scratch/code/extraction/packaging budgets, output preservation and independent re-extracted Apple codesign. `PreparedSigningOutcomeTests` exercise the actual app model, configuration invalidation, overlapping requests, credential removal, save failure, export and retry. Existing R1–R8 regressions remain enabled.

Linux syntax checks and non-Apple suites are recorded at the final checkpoint. macOS CI must verify the exact final head before calling this milestone verified. No physical installation or launch has been performed.

## Costs and limitations

Preparation retains one extracted tree rather than extracting again on confirmation. SHA-256 uses 256 KiB chunks, with full-source reads before/after preparation, at confirmation and before publication. These reads deliberately detect raw source changes, including bytes not represented by ZIP entries. R2 entry inventories still avoid another decompression pass for unchanged compressed entries. Two tree identities cover the main bundle and whole Payload; integrity costs are retained.

Disk caps are not filesystem reservations; live free-space checks and actual I/O failures remain authoritative. Existing signer and Debian decoding allocate individual bounded code/archive buffers; this is not an OS process-memory hard limit. Force-kill scratch recovery is not crash-durability: preparation scratch is disposable, user inputs and completed pending artifacts are not. UI/accessibility and low-storage behavior still need physical-device confirmation. No iPhone performance or installation claims.

## CI-driven corrections

- Run 39504675083 exposed Darwin `/var` versus `/private/var` URL spelling in preview code paths. Preparation now canonicalizes its owned root and calculates paths against the same canonical app boundary; all app/framework/extension/import paths are asserted. This was a production preview bug, not a relaxed assertion.
- Run 39504367337 compiled the app and passed engine tests, but its new model fixtures attempted persistent Keychain writes from the unsigned Simulator host (`-34018`). Model tests now inject the existing `IdentityKeychain` custody interface with a locked in-memory map of real fixture `SecIdentity` references. PKCS#12 parsing, real RSA signing, self-check, packaging and persistence still execute. No production Keychain code or CI entitlements are changed; no new skips are introduced. Physical custody remains a separate gate.
- Universal thinning now uses the preparation lease's scratch and cooperative checkpoints; editor library staging is also owned, checked and charged before writes. Public editor/random-suffix and manifest no-argument APIs remain intact.
- Entitlement-picker reads stop at 256 KiB, matching the existing plan's bounded XML policy. Oversized files cannot become unbounded preview configuration.

The production policy also covers the explicit source-built installation probe. It uses the same prepared transaction; Test consent authorizes signing that fixed probe, not an editable user-IPA preview. No invalid-CMS legacy bypass remains in App. Legacy library clients retain their existing direct API.

ProfileTrust's baseline lines 44–53 used the trusted root's display name to classify an Apple chain. This cannot authenticate issuer identity. It now requires both successful system chain validation and SHA-256 equality with one of Apple's three public roots. Embedded roots were compared byte-for-byte with Apple's public HTTPS DER endpoints on 2026-10-20. A regression uses a trusted non-Apple fixture certificate with a spoofed Apple root display name, checks all three actual public pins and verifies pins cannot override failed chain validation. Basic X.509 chain trust still does not evaluate Apple's private provisioning policy or revocation; the UI states that limitation explicitly.


## Review map and compatibility

| Path | Changed responsibility |
|---|---|
| `Sources/SigningKit/PreparedIPA.swift:77` | Exclusive preparation, immutable public preview, frozen internal plan; cancellation-aware source SHA-256, one-shot execution and cleanup. |
| `Sources/SigningKit/PreparedIPA.swift:173` | Confirmation identity checks, signature self-check, unchanged R2 staged-byte verification and atomic publication. |
| `Sources/SigningKit/BundleSigner.swift:77` | Existing real resolver with preparation deadlines and owned thinning scratch; entitlement/signing algorithms unchanged. |
| `Sources/IPAKit/ArchiveIntegrity.swift:162` | Optional cancellation/deadline checkpoint for manifest tree recapture; existing no-argument API retained. |
| `Sources/SigningKit/AppEditor.swift:141`, `LibraryInjector.swift`, `DebExtractor.swift`, `FatMachO.swift:63` | Internal resource hooks for owned edits/thinning/import stages; existing public editor API retained. |
| `Sources/CredentialKit/ProfileTrust.swift` | Exact public-root identity for Apple trust labels, distinct from CMS integrity and private iOS policy. |
| `App/SigningModel.swift:326` | Worker-owned preparation, generation filtering, expiry, configuration invalidation and raw-profile snapshot recheck. Confirmation cannot substitute cancellation owners. |
| `App/SignView.swift:299`, `SigningOptionsView.swift:47` | Real preview/confirm/cancel, requested versus signed capability values, nested profile overrides and strict policy control. |
| `App/IdentityReadiness.swift:96` | Fixed-probe production policy uses the same prepared transaction; no invalid-CMS app bypass. |
| `Tests/SigningKitTests/PreparedIPATests.swift`, `FatMachOTests.swift`, `SigningPlanTests.swift` | Prepared byte/decision parity, malformed/stale/cancel/budget/trust controls and independently verified repack. |
| `Tests/AppModelTests/PreparedSigningOutcomeTests.swift`, `project.yml` | Actual app-model engine/persistence tests with real fixture cryptography; injectable fixture custody only. |
| `MASTER-ROADMAP-EXECUTION.md`, `OPEN-PR-INTEGRATION.md` | R7 merge proof, R15 open-PR dependency and continuation state. |

The app deliberately no longer signs a user IPA immediately on the first tap: that tap prepares and displays the actual plan. Confirmation is mandatory. Edits, profile pins, strict mode and certificate changes invalidate the old preview. Unknown or incompatible overrides and invalid selected CMS produce actionable refusal. Valid unknown-trust CMS remains allowed with explicit qualification. Metadata and code-file budgets may reject unusually large inputs earlier; defaults are documented in `PreparedIPA.Limits`. Existing direct library APIs remain source compatible and keep historical behavior.

## Commands and evidence

Local Linux:

- Cached offline `swift:6.2.3-jammy`: `swiftc -frontend -parse` on all changed/new Swift production and test files (syntax only).
- Same container: `python3 scripts/test_parser_safety.py`: **33 isolated real Swift parser cases passed**, zero failures; not Apple-framework integration.
- `swift test --scratch-path /workspace/shared/r15-linux-spm --filter PreparedIPATests` attempted: **unavailable**, existing Apple-only package imports fail on Linux (`CryptoKit`, plus Foundation networking differences). No Swift package success claimed locally.
- `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`: **55 passed**.
- `python3 -m unittest discover -s Source -p 'test_*.py'`: **26 passed**.
- `python3 -m unittest discover -s scripts -p test_package_probe.py`: **6 passed**.
- `bash scripts/test_publish_prep.sh`: passed all assertions.
- `bash scripts/test_make_install_cert.sh`: host initially failed its fake account-registration assertion because `uuidgen` is absent. Unmodified test rerun with a local Python-stdlib UUID utility shim passed all assertions. Native macOS shell execution remains mandatory in CI.

R7 merged main [39503390099](https://github.com/dylldev/wax-signer/actions/runs/39503390099), exact merge SHA `b4214fe592f4d391a3851cd19d2c0ea21a94c4d2`: **713 package tests / 13 skips / zero failures; 366 Simulator tests / 11 skips / zero failures**. Unsigned iOS build, 55/26/6 Python tests, both shell suites, independent codesign/CMS controls passed.

R15 live exact-head package/build/Simulator verification is attached to [PR #29](https://github.com/dylldev/wax-signer/pull/29). No previous green source head verifies a later one. Final run/head/counts are recorded in the PR after completion, without claiming an unexecuted documentation commit has passed. Superseded runs were canceled only after their replacements were running; canceled or failing heads are never counted as successful.

The small committed fixture's execute+self-check+pack+R2-gate samples in superseded macOS runs were 0.173 s (39504675083) and 0.138 s (39504847920); both runs failed the subsequently fixed preview-path assertion. These are diagnostic single warm-cache samples, **not** a performance comparison, completion evidence, or an iPhone benchmark. Representative large IPA wall time/RSS/CPU/thermal and storage measurements remain unperformed. Preparation retains one extracted tree; hashing adds four bounded whole-source reads. No extra extracted copy is required by final archive verification.

## Required physical-device protocol — not executed

| Journey | Required evidence |
|---|---|
| Development and Ad Hoc identities, including independent Team ID/App ID prefixes | Preview grants/groups match exported signed XML/DER; Keychain access and real provisioning remain separate checks. |
| Normal app and apps with nested frameworks/extensions | Confirmed identifiers/profile bytes equal the final exported IPA; independent codesign, install observation and launch are recorded separately. |
| Random IDs, custom edits and injected code | Preview stays fixed through confirmation; changed inputs/settings require a new preview; code loads only where legitimately supported. |
| Background/locked/cancel/expiry | Cancellation stops before publication or returns the completed artifact; earlier library files and retry/export remain intact. |
| Low storage and failed shelf save | Original and signed pending files survive; no false Saved/Installed message; retry/export works after storage recovers. |
| VoiceOver, large Dynamic Type, Reduce Motion | Review and confirmation are discoverable; long capability values and error recovery remain reachable. |

Pin classification does not install trust roots or bypass any iOS provisioning decision. No release, deployment, distribution update, production credential modification, physical installation or launch was performed.


Run 39506848402 passed the full package suite, unsigned iOS build and 239 Signing Simulator tests. Its model suite found one fixture mistake: flipping the final byte of a BER CMS altered an end marker and caused `profileNotCMS` during import rather than testing cryptographic rejection. The fixture now locates the parsed SignerInfo signature bytes, asserts the target is unique, mutates a signature byte and reparses to assert the embedded profile content/framing stayed unchanged. This strengthens the intended invalid-signature production-policy regression; no production check or skip changed. The earlier custody-corrected run 39505985755 passed its then-current complete workflow, but neither that nor any earlier head substitutes for final-head CI.
