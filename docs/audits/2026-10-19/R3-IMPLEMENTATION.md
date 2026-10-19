# R3 — durable, non-destructive IPA library

Base: `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`, the authorized R2 squash merge. R1 and R2 production parsers, signing algorithms and artifact gates are unchanged. No credentials, releases, feeds or infrastructure are modified.

## Confirmed original defects

References are to the R2 merge base:

- `Sources/InstallKit/IPALibrary.swift:55–85`: kind/bundle ID/version/size deduplication removes previous index references and then deletes the older IPA despite not establishing byte identity.
- `Sources/InstallKit/IPALibrary.swift:26–34`: unreadable/malformed indexes silently become empty arrays, and missing files lose their in-memory references. `remove`/`clear` swallow file-deletion failures after the index commit.
- `App/LibraryModel.swift:26–45`: saves catch errors into nil; the unawaited `file` task exposes no completion outcome. Removal errors are suppressed.
- `App/SourcesModel.swift:116–129`: a temporary download is deleted regardless of insertion outcome, and Filed/success/announcement occur even after a nil save.
- `App/ContentView.swift:119–135`: import announces Added without checking insertion success.
- `App/SigningModel.swift:265–270,328–336`: the global signed-output directory is deleted at the next sign; unawaited filing races the result UI. `App/SignView.swift:361–432` unconditionally claims the signed output is on the shelf.

## Storage design

Library entries gain optional complete-IPA SHA-256, build number and public provenance (`fileImport`, `sourceDownload`, `waxSigned`, `recoveredUnknown`). Legacy IDs, names and filenames remain stable. A publisher signature marker never implies Wax-generated provenance: imports and downloads go to Unsigned unless explicitly produced by Wax's signing flow. No private signing metadata is stored.

Index v2 contains `version`, `entries`, and deletion tombstones. Existing bare JSON arrays decode without new fields and migrate only on a successful mutation. Missing hashes are filled lazily when a legacy candidate could be a duplicate. Matching size is just a prefilter; duplicates require actual SHA-256 equality and rechecking existing bytes. Signed and unsigned namespaces stay distinct. Already Saved reuses the stable existing ID; it does not delete older legacy duplicates or other metadata matches.

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

## Migration and conservative recovery

Malformed, unsupported, oversized, symlinked or invalid indexes block mutations, preserving index bytes and any already loaded references. A missing file is hidden from usable rows but its reference remains in subsequent index updates. Unknown files, directories and damaged journals are never swept away. Recoverable artifacts under the shelf, pending and app-owned incoming directories are listed separately from Saved entries.

Recover Library Index is an explicit user action. It first preserves a uniquely named copy of the damaged index, prefers valid existing/backup metadata, and indexes safe orphan files without moving/deleting them or guessing signing provenance. Repeated repair retains IDs/filenames. Legacy entries sharing a filename remain distinct references. Downgrading to an old writer that expects a bare JSON array is unsupported: export/backup the library before a downgrade. The old app's empty-on-decode-failure behavior is not a safe rollback mechanism.

## Application outcomes

- Awaited `LibraryModel` APIs expose Saving, Saved, Already Saved and Failed with an artifact URL/pending ID. Failures provide retry/export instructions.
- Manual imports retain a coordinated copy before releasing picker-owned data, route only on commit, and announce Added only on confirmed persistence. If no durable copy can be made (e.g. full storage), the picker copy is kept for retry in the current session; the original in Files must be kept.
- Downloads use app-owned durable incoming directories. Save failure does not mark Filed, notify success, route to Sign, or delete the download. Retry Save reuses the retained download rather than fetching again; restart recovery is available in the IPA tab.
- Signing uses a unique durable pending directory per result. The report/self-check and export/install target remain usable after shelf failure. Retry Save can complete the transaction; starting over/new signs do not delete prior pending outputs. Saved-on-shelf UI and success notification are conditional on confirmed persistence.
- Delete/Clear run off the main actor and surface index/cleanup errors instead of announcing false success.

## Regression coverage and verification

Implementation verification is in progress. Added transaction tests cover exact identity, same-size different bytes/configurations/builds, kind separation, concurrent instances, I/O faults, full storage, disappearing/changing inputs, staged corruption/truncation, index failures, cleanup failures, all transaction boundaries, legacy migration, missing references, damaged indexes/journals, shared filenames, orphans and containment. App-hosted model tests cover import/download/signing save failures, retry, export, truthful announcements, routing and restart recovery. The full macOS package/build/simulator checks will verify Apple-dependent behavior. Linux syntax checks are not substitutes for those checks.

## Resource costs and limitations

File operations use bounded 256 KiB buffers. An external save uses a staged copy and multiple streaming hash passes to prove copy/source consistency and the bytes actually indexed. Signed outputs are produced directly into retained storage, then moved on the same volume. Index and per-transaction JSON are bounded to 64 MiB and 64 KiB respectively. Metadata storage is proportional to entry count. No complete IPA is loaded into memory by library code. The generated 8 MiB fixture records save timing without a performance assertion; measurements will be added after CI. No iPhone speed, battery or thermal claim is made.

Recovery is tested using deterministic checkpoints at transaction boundaries, not physical power-cut tests. Same-UID malicious concurrent filesystem writers, hardware corruption, power-loss/fsync durability of directory/index metadata and multiple app processes are outside the claimed guarantees. Process death can leave recoverable staging files; unknown artifacts are deliberately retained for user-directed recovery rather than guessed cleanup. Real-device storage pressure, background termination, file protection, picker/provider lifetimes and install/launch remain separate verification gates.
