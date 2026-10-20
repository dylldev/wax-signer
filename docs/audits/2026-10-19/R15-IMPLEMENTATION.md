# R15 — Prepared IPA preview and confirmation

Baseline: R7 squash merge `b4214fe592f4d391a3851cd19d2c0ea21a94c4d2` (PR #28), reviewed head `11aada4954cf8cab17a807b2fc08e08f3f2b09fe`, CI [39495578350](https://github.com/dylldev/wax-signer/actions/runs/39495578350) passed 713 package tests (13 environment skips) and 366 Simulator tests (11 skips), unsigned iOS build, Python/shell and independent codesign/CMS controls. No review blockers or protection exceptions.

## Architecture

Previously `IPASigner.sign` (baseline lines 33–85) extracted, edited and resolved while signing; `BundleSigner.plan` (lines 75–150) only accepted a caller-owned unpacked tree. `SigningModel.sign` (lines 302–440) directly invoked the former, with no confirmation gate.

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
