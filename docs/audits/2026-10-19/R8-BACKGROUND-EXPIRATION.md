# R8: propagate background expiration to owned work

Implementation prepared for independent review; final-head macOS CI pending at publication. Stacks only on PR #24 (`11150a48c393f7ab20b4b6add6c6540a65db2531`), which includes the reviewed-by-CI R3/loopback/ledger/OTA/extraction foundations through explicit development bases. No prerequisite PR has been merged into main.

## Confirmed gap

At `d8dd695:App/BackgroundJob.swift:79–83,93,124`, continued expiration completed the system task and grace expiration ended a UIKit resource, but neither asked the associated work to stop. SigningModel's standalone and installation jobs (`:160,301`) supplied no cancellation handler; SourcesModel (`:126–131`) did not retain its returned task for expiration; IdentityTester owned its OTA session but no background job (`IdentityReadiness.swift:118`). A stalled transfer or worker could therefore outlive the resource expiration without receiving cancellation.

## Design

BackgroundJob records one expiration request per operation and delivers an operation-owned MainActor callback once. Late task registration receives an already-issued expiration, closing synchronous admission races. Continued-task expiration snapshots existing IDs, releases their grace handles and requests cancellation even if the app has become active (the continued task can be canceled by the user). Ordinary grace expiry cancels only its owner, only when Wax is not active and no continued-processing task currently covers it. Stale callbacks cannot act on replacement IDs. System-task completion and resource release remain once-only; workers stay registered until their work actually settles.

SigningModel forwards expiration to its SigningCancellation; installation additionally cancels the exact OTA session, which closes its host and cancels publication/delivery. Completed R2 publication is never interrupted and its output still reaches R3 report/save. IdentityTester owns a background job for signing, host preparation, transfer and observation; expiry cancels only its test generation and token. Synthetic signed probes remain retained. SourcesModel registers its exact Task and generation-checks queued progress. A noncooperative download that completes after expiration is retained for retry; no save/routing/success announcement starts for that canceled operation. A library transaction already begun settles under R3 rather than being interrupted mid-commit.

The System seam adds foreground-state observation for deterministic tests; production uses UIApplication state. No thread interruption, credential change, destructive cleanup, signature or artifact-gate change.

## Changed files and regressions

- App/BackgroundJob.swift: ownership/delivery helpers and resource-expiry policy.
- App/SigningModel.swift: standalone and install expiration callbacks, cancellation checks before credential work/reserving output.
- App/IdentityReadiness.swift: probe lifetime owns a background job.
- App/SourcesModel.swift: per-download generation, expiration Task registration, retained late completion and truthful cancellation/retry message.
- Tests/AppModelTests/BackgroundJobOutcomeTests.swift: seven new cases for once-only per-worker cancellation, foreground/continued exemption, aggregate cancellation, synchronous late registration, stale callbacks, reentrant replacement and new admission while canceled workers settle.
- Tests/AppModelTests/OTASessionOutcomeTests.swift: two cases for expiration during suspended signing and delayed host readiness, preserving replacement owners and completed signed artifacts.
- Tests/AppModelTests/LibraryOutcomeTests.swift: two cases for immediate cancellation before download and noncooperative completed download retained/retried without redownload or false announcement.

11 new deterministic app-model tests; existing R1/R2/R3/R8/R14 tests remain enabled. Offline Swift6.2.3 syntax parsing and diff checks passed, not a substitute for Apple compilation. Final package/iOS build/Simulator results belong in PR/checkpoint after actual CI completion.

## Limits / device protocol

Expiration is cooperative, not an extension of Apple's granted time. A blocked filesystem/key/hash operation may settle after expiration; the OS may suspend or terminate Wax first. R3 recovery and R2 previous-output preservation remain the recovery mechanisms. Pending continued-task adoption still represents the aggregate rather than a durable OS-to-job identifier; durable job restart/resume is R20, unfinished. No automatic deletion/retention policy for synthetic probes is added.

On a physical phone, test foreground and background standalone signing, signing+phone/server/bucket delivery, concurrent download+sign and probe preparation/polling. Expire/cancel each resource, verify only its owned work stops at a safe boundary, links are not handed off by stale callbacks, prior IPAs and completed signed reports survive and Retry Save/Export remain usable. Repeat across lock/unlock, permission refusal, low storage and process termination; use R3 restart recovery. Real installation, launch, notification delivery and OS scheduling have not been observed in this cloud environment.

Cost: constant-size per-job state and O(active jobs) aggregate expiration; no new full-file pass, buffer or temporary IPA. No iPhone timing/battery claim.
