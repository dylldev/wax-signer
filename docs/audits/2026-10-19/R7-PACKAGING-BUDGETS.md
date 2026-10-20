# R7 milestone: owned, bounded IPA packaging

Status: implemented on a focused branch;18 new XCTest regressions, exact-head macOS CI pending. This milestone does not complete all original R7 resource/memory budgets or R8 cancellation work.

## Confirmed baseline and root causes

Branch base `9243a9d97a54bc27fb963b0b8a10322bcc4cc52a`; [final integrated-main CI39493120425](https://github.com/dylldev/wax-signer/actions/runs/39493120425) SUCCESS. Production source equals48b6e2a56959ca1fb176abd5bd0ce07127190832, after all24 original focused PRs were integrated. R1/R2/R3/R8/R14/R15 protections are dependencies, not replaced implementations.

- `Sources/IPAKit/IPAArchiver.swift:49` creates compression scratch under the process temporary directory, while staged output lives on the destination volume. One destination free-space observation cannot account for both locations.
- `IPAArchiver.swift:57` uses concurrentPerform(bigList.count) without an operation worker cap. Dispatch controls actual scheduling, so this is an absence of an explicit policy, not evidence that every file starts simultaneously.
- `IPAArchiver.swift:79` checks classic-ZIP geometry but not cumulative temporary writes/free-space/deadline/cancellation during packing. Precompression and initial manifest/source fingerprint reads also lack cancellation checkpoints.
- `Sources/SigningKit/IPASigner.swift:74,82` checks its owner before packing and at final publication, but originally did not pass it into compression/reuse loops. This can delay cancellation until packing finishes; no claim of final-byte corruption is made (R2 already protects those bytes).

## Design

Add IPAArchiver.Limits: maximumConcurrentFiles4, maximumTemporaryBytes8GiB, minimumFreeBytes16MiB and monotonic deadline1800s, configurable for library callers. Reject invalid ranges, nonfinite/subnanosecond deadlines and arithmetic overflow through localized typed errors.

Largest-first worker queue has at most the configured concurrent compression workers. Workers stop claiming new jobs after the first failure; in-flight workers finish/unwind before owned scratch is removed. Streams remain256KiB, with no added full-file buffering or hashing pass.

Cumulative attempted temporary writes include compression scratch plus staged ZIP bytes. This is deliberately conservative, not a measurement of peak live scratch. Free space is observed initially, at file boundaries and periodically during writes; it is not a reservation against other apps or the OS. Actual I/O errors still propagate. The byte counter is shared/locked; user callbacks execute outside its lock.

Compression scratch lives under the staged output parent. mkdtemp establishes exclusive directory ownership (0700). O_CREAT|O_EXCL establishes temporary file ownership (0600) before cleanup registration, preventing existing-file truncation. Normal failures remove only these owned paths. Existing destination and source artifacts survive. Abrupt process termination or filesystem cleanup failure can leave owned orphans; no automatic deletion of unknown files or crash-durability guarantee is introduced. R20 recovery remains separate.

Active checkpoints cover initial manifest enumeration/hash reads, original-entry fingerprinting, compression input/drain, raw reuse, stored/precompressed output and ZIP metadata writes. IPASigner explicitly supplies its thread-safe SigningCancellation owner across GCD workers. Standalone callers can supply their own operation-bound callback; default Task cancellation observations depend on execution context. R8 deeper cancellation remains partial.

The last cancellation/deadline/budget check precedes validateArchive. Once that callback seals IPASigner's publication phase, mandatory R2 actual staged-byte and working-tree comparisons and atomic output promotion finish without post-barrier cancellation discarding a completed artifact. Validation/integrity/I/O errors still fail and preserve the prior output.

R2 SHA-256 reuse, source-session binding, CRC/size checks, classic-ZIP sentinels, path/symlink/permissions validation and unconditional final artifact gate remain intact. No signing algorithm, credential custody, library index or bucket ledger change.

## Files

- Sources/IPAKit/ArchivingBudget.swift: locked cumulative-write budget, monotonic deadline, observed free storage and internal clock/free-space seams.
- Sources/IPAKit/IPAArchiver.swift: limits/errors, bounded queue, same-volume exclusive scratch, active checkpoints and pre-publication boundary.
- Sources/IPAKit/ArchiveIntegrity.swift: optional checkpoint through enumeration and existing streaming hash; stop enumeration at the existing classic entry cap.
- Sources/IPAKit/ZipArchive.swift: optional fingerprint checkpoint, preserving cached extraction identities and existing reader checks.
- Sources/SigningKit/IPASigner.swift: propagate the actual signing cancellation owner into packaging.
- Tests/IPAKitTests/ArchivingBudgetTests.swift:18 deterministic regressions.
- This report and the master checkpoint: exact verification and remaining scope.

## Regression coverage

Invalid configuration; exact counter and hostile Int bounds; reserve arithmetic overflow; monotonic deadline/reversal; initial and mid-write storage loss; storage observation I/O failure; compression scratch exhaustion; combined scratch+staged accounting; cancellation during compression/raw reuse/manifest hashing; deadline during streaming; one/two-worker output equivalence including executable permissions; exact compressed-byte reuse without compression scratch; cancellation before/after publication; final staged corruption refusal; old output/source/unknown-file preservation; exclusive file creation/no truncation and0600 permissions.

## Verification and performance

Pending real branch/macOS results. Locally executed on Linux in offline Swift6.2.3 Docker:

- Frontend parse of all6 changed Swift source/test files succeeded (syntax only).
- Actual ArchivingBudget helper compiled/run against copied limit/error declarations:9 invalid limit variants;1000 concurrent byte claims (128 admitted,872 rejected); hostile counts; reserve overflow; monotonic deadline/reversal; disk observation; cancellation.
- Actual exclusive temporary-file helper compiled/run: existing bytes preserved and mode0600 verified on Linux.

A harness-only Int/Int64 literal inference error was corrected before the successful portable run. No full Swift package, Xcode, Apple Compression, Simulator, codesign or device result is inferred from those portable checks. The final feature head needs GitHub macOS CI before independent review.

The one/two-worker test emits WAX_ARCHIVE_OBSERVATION for the same seeded8MiB corpus. These are single warm-cache runner observations, not an old-engine baseline, statistical performance result or iPhone speedup. Peak RSS/CPU/read-write volume/thermal cost and representative small/medium/large IPA benchmarks are not measured here. Expected overhead is per-chunk clock/cancellation/locked counter plus bounded free-space probes, without additional content reads. Compression state scales with the configured worker cap. Cumulative writes are capped; external storage pressure can still make writes fail. Successful final ZIP size remains subject to R2 classic limits.

## Remaining verification/scope

Physical-device large signing, low-storage/restart/lock/background cancellation, save/export retention and installation/launch remain separate gates. Archive post-publication integrity work intentionally ignores cancellation; deeper verification CPU checkpoints and prepared-IPA preview are not implemented here. Remaining R7 provider/cache/artwork/whole-engine memory controls remain in the original master inventory. No release, deployment, distribution mutation or real signing material is part of this milestone.
