# R7 extraction resource budgets

Status: partial original R7 milestone; implementation prepared, macOS CI pending. Independent from R2/main; preserves R1/R2 ZIP geometry, CRC/SHA-256 reads, reuse identity and final output gate.

## Confirmed gap / change

At `8ad4b2e`, `IPAExtractor.swift:40–44` only checks declared total/count, and `:143–176` schedules one concurrentPerform iteration per file without an explicit worker, space or total-time budget. Symlink targets are length-checked after the general in-memory entry read (already capped16MiB; not unbounded). That cap and the existing1GiB uncompressed TAR cap are not misreported as missing.

Extraction now has an explicit4-worker default (configurable1…64),16MiB free-space reserve and30-minute monotonic deadline. Initial free-space check covers the declared expansion plus reserve; per-entry/8MiB write probes detect storage pressure during work. Deadline/cancellation checks run around reads/decoded chunks, with bounded decoder/file-handle concurrency. The largest-entry-first queue is retained for load balancing. Declared-total addition and reserve arithmetic reject overflow before writes. Symlink target declarations>=4096 are refused before decoding.

Typed `IPAExtractor.BudgetError` distinguishes invalid configuration, time limit and insufficient storage. Actual storage-observation/read/write errors propagate. The optional Sendable cancellation checkpoint lets an owning async coordinator supply its own thread-safe cancellation token; default Task cancellation is also checked at the caller boundaries. Dispatch workers do not inherit the parent Swift task, so this API **does not** claim automatic prompt parent-task cancellation throughout the current signing pipeline; wiring an owner token there remains original R8 work.

New destinations are removed on failure only after all workers settle and close their streams. Existing destinations/unknown files are not removed wholesale. This does not turn extraction into an atomic merge of an existing directory: callers must use an exclusively owned fresh scratch tree (as IPASigner already does) for non-destructive aborts. Cleanup can still fail if the filesystem refuses removal; the original error remains a failure, never a published output. No user source IPA/library artifact is removed.

## Regression coverage

10 deterministic tests: invalid budgets; initial low storage/source preservation; existing destination sentinel preservation; monotonic expiry; storage drop during one8MiB streaming entry; cancellation between entries/owned partial cleanup; observation I/O errors; reserve overflow; oversized link rejected before CRC; exact files under1/2-worker configurations. Existing R1/R2 round-trip, adversarial ZIP, output-preservation, system-unzip, signing and independent codesign suites remain enabled.

Offline Swift frontend parsing passed. Actual macOS package/build/Simulator results will be recorded in the master checkpoint/PR after execution. No iPhone extraction benchmark, installation or launch evidence.

## Performance and remaining scope

A constant number of decoder contexts/file handles replaces CPU-count-dependent parallelism. Each ZIP stream still uses bounded256KiB input/output chunks; this is not a bound on total process memory, CodeResources or the signing engine. Four workers may trade throughput for memory on machines with many cores; existing synthetic R2 timing is retained for observation, not a cross-runner gain claim. Filesystem probes occur at entry boundaries/8MiB, not every byte.

Free-space checks are observations, not atomic reservations against other apps consuming storage; real ENOSPC still propagates. Deadline checks cannot interrupt a blocked kernel read. Output compression/scratch amplification, provider acquisition, source object/artwork budgets and whole Mach-O/DEB worker memory remain unfinished original R7/R18 scope. Final R2 staged-archive validation/promotion remains mandatory and unchanged. No deployment/release or credential changes.
