# R8 milestone — Loopback transfer ownership

Baseline `8ad4b2e` (main/R2). This is the loopback lifetime portion of original R8, **not completion of job/background/signing/install-coordinator work**. Independent from unmerged R3/R7/R9 branches.

## Confirmed mechanisms

Original `Sources/InstallKit/LoopbackHost.swift:172–176` cancels only the listener; accepted NWConnections and their open FileHandles are untracked (`:180–255`). An old contentProcessed callback can add its range into a later publication's shared `sent` array. The pending listener is not stored until after the ready await (`:114–139`), so stop during preparation cannot own it. `waitForTransfer` (`:48–57`) follows mutable current state and ignores sleep cancellation, allowing a canceled waiter to busy-loop or observe a replacement publication.

## Implementation

`LoopbackHost.swift` owns pending listeners, accepted connections and file handles on its existing serial queue. Each publish/stop changes a generation; every receive/send/timer callback checks generation/connection ownership before reading or crediting ranges. Stop/expiry/republication invalidates callbacks, cancels all connections and closes all handles, including clients waiting for headers. Failure/read EOF never counts as complete delivery. Seek errors are no longer swallowed. Deinitialization closes resources, with a queue-specific guard against sync deadlock. Cancellation during preparation tears down only its own generation; a superseded publish cannot stop the newer one. Readiness continuations resume once.

Waiters bind to the observed generation, use monotonic elapsed time, and return false promptly on cancellation. Empty/nonregular/missing input fails before publishing a link; HEAD/GET/range and TLS/DNS-loopback behavior remain. No TLS validation bypass or certificate architecture change is introduced.

## Tests and evidence

Five new tests in `Tests/InstallKitTests/LoopbackHostTests.swift`: real synthetic TLS client awaiting headers is remotely closed by stop; runtime sparse64MiB file produces backpressure so stop/republication must close its active handle and old callbacks cannot credit the new range; canceled waiter returns false; canceled publish leaves no resources; empty input fails before publication. Existing GET/HEAD/range/TLS/lifetime tests stay enabled. Test client's self-signed trust acceptance exists only in tests and is not production trust.

Local offline Swift6 syntax parse and `git diff --check` passed. Linux has no Network/Security Apple frameworks or Xcode, so actual lifecycle execution requires final macOS CI; results pending. No phone installation/launch claim.

## Remaining original R8 / limitations

BackgroundJob singleton ownership, OTA preparation busy/snapshots, IdentityTester/install serialization, cooperative sign/extract cancellation and per-stage UI state remain unfinished. This PR prevents stale callbacks **inside one LoopbackHost instance**, not replacement across independent host/coordinator objects. Blocking DNS lookup is not made cancellable. File handles are closed on stop, but arbitrary external mutation of an already published IPA is outside this milestone; R2 validates final IPA, and R3 manages retained artifact storage separately. A network send completion is delivery bookkeeping, never evidence of install/launch. Physical iPhone background expiration/lock/OS install handoff remains unexecuted. No performance improvement is claimed; buffers remain256KiB per active stream.
