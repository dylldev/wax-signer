# R3 — durable, non-destructive IPA library

Base: `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`, the authorized R2 squash merge. R1 and R2 production parsers, signing algorithms and artifact gates are unchanged. No credentials, releases, feeds or infrastructure are modified.

## Confirmed original defects

References are to the R2 merge base:

- `Sources/InstallKit/IPALibrary.swift:55–85`: kind/bundle ID/version/size deduplication removes previous index references and then deletes the older IPA despite not establishing byte identity.
- `Sources/InstallKit/IPALibrary.swift:50–51`: unchecked summation can trap for damaged legacy indexes containing multiple `Int.max` sizes. Accounting now saturates safely, with the same helper used by the UI; a regression retains both files and checks the sum.
- `Sources/InstallKit/IPALibrary.swift:26–34`: unreadable/malformed indexes silently become empty arrays, and missing files lose their in-memory references. `remove`/`clear` swallow file-deletion failures after the index commit.
- `App/LibraryModel.swift:26–45`: saves catch errors into nil; the unawaited `file` task exposes no completion outcome. Removal errors are suppressed.
- `App/SourcesModel.swift:116–129`: a temporary download is deleted regardless of insertion outcome, and Filed/success/announcement occur even after a nil save.
- `App/ContentView.swift:119–135`: import announces Added without checking insertion success.
- `App/SigningModel.swift:279–284,328–336`: the global signed-output directory is deleted at the next sign; unawaited filing races the result UI. `App/SignView.swift:361–432` unconditionally claims the signed output is on the shelf.

## Storage design

Library entries gain optional complete-IPA SHA-256, build number and public provenance (`fileImport`, `sourceDownload`, `waxSigned`, `recoveredUnknown`). Legacy IDs, names and filenames remain stable. A publisher signature marker never implies Wax-generated provenance: imports and downloads go to Unsigned unless explicitly produced by Wax's signing flow. No private signing metadata is stored.

Index v2 contains `version`, `entries`, and deletion tombstones. Existing bare JSON arrays decode without new fields and migrate only on a successful mutation. Missing hashes are filled lazily when a legacy candidate could be a duplicate. Shelf byte accounting uses checked, saturating addition so oversized damaged legacy metadata cannot trap the app. Matching size is just a prefilter; duplicates require actual SHA-256 equality and rechecking existing bytes. Signed and unsigned namespaces stay distinct. Already Saved reuses the stable existing ID; it does not delete older legacy duplicates or other metadata matches. Legacy filename aliases are compared conservatively across case and Unicode normalization before deletion, so APFS aliases cannot delete another entry's file.

All library instances for one canonical root share a process lock, and transactions reload the index under that lock. Wax currently has one process writing its shelf. Cross-process writers/extensions are not supported. Expensive copy/hash/recovery operations run off the app's main actor; the UI uses published snapshots and cached URLs.

Each operation owns `pending/<UUID>/record.json` and `artifact.ipa` (or an unfinished `artifact.part`). The record progresses through Preparing, Ready and Committing:

1. Reserve a unique pending directory; atomically write its record.
2. For external input, stream-copy with SHA-256, independently hash the staged copy, and compare the source again. The original is never moved/deleted by the library. A failure retains staged bytes and the source.
3. Mark Ready with the digest, size and inspected metadata. Signed output is generated directly into its own durable pending directory, avoiding an extra IPA copy. R2 still verifies the actual packaged output before publication to this path.
4. Before a new shelf publication, atomically mark Committing. Move to a unique per-kind final filename; verify the actual published file against the expected hash/size.
5. Atomically replace the JSON index (keeping a previous valid snapshot). Only then return Saved. A duplicate is checked before its pending copy is cleaned up.
6. Remove the known transaction directory. Cleanup failure after a committed save is a warning, not a claim that the index did not commit.

This is a recoverable multi-file transaction, not a claim that two renames form a single atomic transaction. A file/JSON failure before step 5 cannot overwrite an older IPA. A later launch reconciles Committing records against either their staged or published artifact. A committed index entry plus a remaining journal is recognized without another insertion. Ready/Preparing producers and unrecognized files are never auto-accepted or auto-deleted; the IPA tab exposes recovery/retry/export.

Deletion is user-directed: first atomically remove the entry and record a deletion tombstone; then clean the exact file only if no remaining entry references it. Cleanup failures are surfaced and retained in the index for retry. Shared legacy filenames are not removed while referenced. Failed index writes leave previous entries/files in place.

### Interruption boundaries

| Last completed action | Durable evidence / restart behavior |
|---|---|
| Reserve only | Preparing record; no Saved entry. Producer can retry; unknown files remain untouched. |
| Copy in progress | `artifact.part` is retained and listed as an interrupted candidate; it is never automatically treated as a committed original. |
| Copy complete, Ready record | Retained artifact and expected digest; explicit Retry Save can complete the save. |
| Committing record, before move | Recovery verifies the staged artifact and publishes it. |
| Move complete, index not committed | The same journal identifies the exact published file; recovery verifies its SHA-256/size before appending its stable ID. |
| Index committed, journal remains | Recovery verifies the existing entry and cleans the known journal; no duplicate insertion. A caller retry after cleanup still verifies the indexed bytes and returns Already Saved. |
| Cleanup failed | The index's Saved result is real, with a cleanup warning; retry reconciles the known transaction. |
| Delete index/tombstone committed | Cleanup checks all remaining references before deleting; failure leaves a retryable tombstone. |

Fault checkpoints test these orderings using fresh library instances. They do not simulate hardware power loss. Partial/unrecognized candidates have no claim to prior code-signature verification; export/reinspection is distinct from a successful signing result.

## Migration and conservative recovery

Malformed, unsupported, oversized, symlinked or invalid indexes block mutations, preserving index bytes and any already loaded references. A missing file is hidden from usable rows but its reference remains in subsequent index updates. Unknown files, directories and damaged journals are never swept away. Recoverable artifacts under the shelf, pending and app-owned incoming directories are listed separately from Saved entries. Canonical orphans can be explicitly adopted in place, preserving filenames without another full IPA copy. A pending/canonical file is listed only once, even when its index write failed after publication. Hidden R2 staging candidates and artifacts with missing/broken journals remain available as unrecognized files, not claimed signing successes.

Recover Library Index is an explicit user action. It first preserves a uniquely named copy of the damaged index, prefers valid existing/backup metadata, and indexes safe orphan files without moving/deleting them or guessing signing provenance. Repeated repair retains IDs/filenames. Legacy entries sharing a filename remain distinct references. Downgrading to an old writer that expects a bare JSON array is unsupported: export/backup the library before a downgrade. The old app's empty-on-decode-failure behavior is not a safe rollback mechanism.

## Application outcomes

- Awaited `LibraryModel` APIs expose Saving, Saved, Already Saved and Failed with an artifact URL/pending ID. Failures provide retry/export instructions.
- Manual imports retain a coordinated copy before releasing picker-owned data, route only on commit, and announce Added only on confirmed persistence. If no durable copy can be made (e.g. full storage), the picker copy is kept for retry in the current session; the original in Files must be kept.
- Downloads use app-owned durable incoming directories. Save failure does not mark Filed, notify success, route to Sign, or delete the download. Retry Save reuses both the retained download and any already-created save transaction rather than fetching or copying again; restart recovery is available in the IPA tab. In-flight/retained/saved state is keyed by source plus the complete download request, never just a shared bundle/version app ID. The saved indicator checks the actual indexed entry still exists and represents a previous committed download; it can request a fresh download instead of treating metadata/URL equality as content proof.
- Signing uses a unique durable pending directory per result. The report/self-check and export/install target remain usable after shelf failure. Retry Save can complete the transaction; starting over/new signs do not delete prior pending outputs. Saved-on-shelf UI and success notification are conditional on confirmed persistence.
- Delete/Clear run off the main actor and surface index/cleanup errors instead of announcing false success.

## Regression coverage and verification

The first complete macOS integration run passed: [39274372486](https://github.com/dylldev/wax-signer/actions/runs/39274372486), commit `d9aaff18bba2de09f70e7d3094376a31201276d5`. It executed 572 package tests (13 skips, zero failures), passed the unsigned iOS build, and actually ran the new app-hosted `LibraryOutcomeTests` suite successfully on the simulator. Subsequent commits extend the regressions to 36 transaction tests and 13 app-model tests; the final head's actual results and CI link are recorded in [PR #3](https://github.com/dylldev/wax-signer/pull/3), rather than inferring them from this earlier run.

Added transaction tests cover exact identity, same-size different bytes/configurations/builds, kind separation, concurrent instances, I/O faults, full storage, disappearing/changing inputs, staged corruption/truncation, index failures, cleanup failures, all transaction boundaries, legacy migration, missing references, damaged indexes/journals, shared filenames, orphans and containment. App-hosted model tests cover import/download/signing save failures, retry, export, truthful announcements, routing and restart recovery. The macOS package/build/simulator checks verify Apple-dependent behavior. Linux syntax checks are not substitutes for those checks. One additional root-case-alias test explicitly skips on a case-sensitive filesystem where that alias does not exist; on an APFS case-insensitive root it exercises concurrent writers through both spellings.

## Resource costs and limitations

File operations use bounded 256 KiB buffers. An external save uses a staged copy and multiple streaming hash passes to prove copy/source consistency and the bytes actually indexed. Signed outputs are produced directly into retained storage, then moved on the same volume. Index and per-transaction JSON are bounded to 64 MiB and 64 KiB respectively. Metadata storage is proportional to entry count. No complete IPA is loaded into memory by library code. The generated 8 MiB fixture measured **0.0528 seconds** for a new streaming save in the first complete macOS run above (one warm-cache observation, no performance assertion). External saves normally hash four full-file reads: copy/source, staged verification, source recheck and final published verification. A generated signed output uses two hash passes and a rename, with no additional full IPA copy. Exact duplicates verify the existing and retained bytes; metadata writes are avoided when their digest is already recorded. Peak RSS, disk energy and cold-cache/large-real-IPA latency were not measured. Scratch cost is one complete retained copy for external saves, plus the caller's original; signed outputs use their final IPA-sized pending file. Failed committed transactions and user data are retained deliberately; repeat retries reuse the same transaction instead of adding another full file. No iPhone speed, battery or thermal claim is made.

Recovery is tested using deterministic checkpoints at transaction boundaries, not physical power-cut tests. Same-UID malicious concurrent filesystem writers, hardware corruption, power-loss/fsync durability of directory/index metadata and multiple app processes are outside the claimed guarantees. Process death can leave recoverable staging files; unknown artifacts are deliberately retained for user-directed recovery rather than guessed cleanup. Real-device storage pressure, background termination, file protection, picker/provider lifetimes and install/launch remain separate verification gates.

## Changed files and important implementation locations

| File | Role / relevant lines |
|---|---|
| `Sources/InstallKit/IPALibrary.swift` | Optional backward-compatible entry fields (19), shared-root serialization (61), checked byte accounting (104), transaction APIs (117–227), deletion/tombstones (229–246), recovery/orphans (248–353), non-destructive repair (355), bounded versioned index (417) and cleanup (473). |
| `Sources/InstallKit/LibraryFileIO.swift` | Streaming copy/source/staged verification (13), checked non-symlink reads and file-stability validation (32). |
| `App/LibraryModel.swift` | Awaited save states and cached UI snapshots (15–51), coordinated imports (56–89), actual commit/error recovery paths (109), retry/export support and surfaced deletion failures (139–178). |
| `App/SourcesModel.swift` | Durable incoming download, separate Saving state, retained transaction reuse and commit-dependent Filed/announcement/routing (100–155). |
| `App/SigningModel.swift` | Durable per-result reservation (304), report/save separation and retry (228–252), operation ownership/generation guards and confirmed completion (351–371). |
| `App/ContentView.swift` | IPA-tab recovery/repair/retry/export, conditional import routing, awaited removal, build/hash/origin details. |
| `App/SignView.swift` | Confirmed-save accessibility announcements (106), conditional shelf-success/failure/retry and export stability while saving (365–390). |
| `App/SourcesView.swift` | Saving and Retry Save controls use actual model state. |
| `App/SettingsView.swift` | Awaited Clear and visible persistence/cleanup errors. |
| `Tests/InstallKitTests/IPALibraryTests.swift` | Replace unsafe replacement expectation with exact-duplicate reuse, retain coverage of removal/index failures. |
| `Tests/InstallKitTests/LibraryTransactionTests.swift` | 36 deterministic identity, concurrency, failure, migration/recovery, containment and timing tests. |
| `Tests/AppModelTests/LibraryOutcomeTests.swift` | 13 app-hosted import/download/signing outcome, retry, export, restart, provenance and announcement tests. Post-engine signing outcomes are simulated here; existing SigningKit suites test real signatures. |
| `project.yml` | Add `WaxModelTests` to exercise actual app models on the iOS Simulator with an existing public IPA fixture. |
| `docs/audits/2026-10-19/R3-IMPLEMENTATION.md` | Engineering evidence, migration/recovery contract and results. |

R1/R2 files under `Sources/IPAKit`, `Sources/SigningKit`, `Tests/IPAKitTests` and `Tests/SigningKitTests` remain byte-for-byte unchanged from the R2 merge base.

### Local commands actually executed

- Offline `swift:6.2.3-jammy` container: `python3 scripts/test_parser_safety.py` — **33 isolated R1 cases passed, zero failed**. Swift frontend syntax parsing of changed source/tests passed. The Linux host has no Xcode, Apple SDK or iOS Simulator and cannot execute the Apple-framework package; macOS CI provides that evidence.
- `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'` — **45 passed**.
- `python3 -m unittest discover -s Source -p 'test_*.py'` — **3 passed**.
- `bash scripts/test_make_install_cert.sh` — **11 assertions passed**. This Linux image lacks `uuidgen`, so the test environment exported the equivalent `uuidgen() { python3 -c 'import uuid; print(uuid.uuid4())'; }` utility; no repository test was modified. macOS uses its native tool. The script uses fake ACME and temporary test certificates only.
- `bash scripts/test_publish_prep.sh` — **8 assertions passed**.
- `git diff --check` — passed.

Mac CI uses the existing commands `swift test`, the Python/shell commands above, `xcodegen generate`, unsigned `xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`, and `xcodebuild test ... -destination 'id=<available iPhone simulator>' CODE_SIGNING_ALLOWED=NO`. Existing system ZIP and independent Apple codesign checks remain enabled in the signing/package suites. App exportability tests copy retained files successfully; actual share-sheet/VoiceOver UX on a physical iPhone is not claimed.

### CI corrections

- Run `39273296031` found an escaping-checkpoint annotation error in the new streaming helper; corrected without changing fault semantics.
- Run `39273661324` executed 571 tests and found one duplicate recovery-list row for a published-but-unindexed IPA. Recovery now canonicalizes/deduplicates paths while retaining the transaction and file. The test remains enabled and the subsequent full integration run passed.

No checks, existing regression suites or signature verification were disabled. Unknown artifacts remain preserved; completion of library saving never implies iPhone installation or launch.

### Expanded full integration evidence

[Run 39275358491](https://github.com/dylldev/wax-signer/actions/runs/39275358491), implementation commit `b2e521803d878170782cd0d6a18b77650432b647`, passed **573 package tests / 13 skips / zero failures**, all server/source/script checks, the unsigned iOS build and all simulator bundles. The simulator actually ran **12 `LibraryOutcomeTests` with zero failures**, plus the existing 166 signing tests (3 skips) and 74 app/credential tests (8 skips). Its 8 MiB save observation was **0.0413 seconds**. The later library URL/root-alias/size-boundary tests increase package coverage to 576 cases; their final-head result is linked from PR #3 and must be checked separately, not inferred from the earlier green run.

Package's 13 historical skips concern eight Keychain cases requiring unavailable host entitlements, two optional real-profile inputs, one optional real IPA, one configured live OTA server and one optional real-IPA performance fixture. Simulator's 11 historical skips cover the corresponding Keychain/optional profile/performance cases. No app-model outcome test was skipped. The root-case-alias test is additionally conditional only on whether the actual filesystem supports that alias.

A final call-site regression covers two repositories advertising the same app ID/version with different IPA builds: their failed-save retries must remain separate, each committed file must retain its actual build, and deleting one shelf entry must clear only its saved-history indicator. This addresses the otherwise unsafe reuse of another source's pending transaction; `SourceParser` IDs contain bundle/version, not repository identity.
