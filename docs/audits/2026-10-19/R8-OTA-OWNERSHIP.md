# R8 OTA ownership and cancellation

Status: implemented; Apple CI pending. No physical installation or launch evidence.

## Baseline and dependency chain

Composite base `codex/r8-session-prerequisites` combines existing PR #14 (bucket journal, including current R3), #17 (background operation IDs) and #13 (loopback generations/connections). These are ordinary development-branch merges, not merges into main. The new PR targets this explicit base so its review diff contains only OTA coordination. All prerequisite PRs remain independently reviewable. After their reviewed integration, retarget and validate the combined main baseline without rewriting published history.

Original anchors at bucket head `0760cf52adb02a47cfb5ae0dcb853a20a27f147a`: `App/OTAInstallModel.swift` upload became busy only after certificate readiness/cleanup; progress assigned shared state without an owner; finishPhoneTransfer read live hostKind/phoneHost. `App/IdentityReadiness.swift` detached probe signing, shared OTA state subscription and unowned polling could overlap a real install. `App/SigningModel.swift` (background head `731e5fc`) reserved only its own installing Boolean and read live host selection after awaits.

## Implementation

- MainActor serial reservations capture immutable phone feed, server endpoint/token or bucket credentials/name before the first await, including before signing a probe or normal app. Settings changes apply only to future reservations. Admission failure does not change the active owner's state.
- Each reservation owns its preparation/upload and delivery tasks plus its exact prepared host. Reset/cancel invalidates admission first, cancels tasks, closes only that host. A delayed noncooperative preparation disposes its own late host. All progress, readiness and completion checks reject stale generations.
- Upload and delivery forward parent cancellation to retained child tasks and schedule owner-scoped cancellation immediately. Session-bound completion never consults live Settings and cannot stop a replacement listener. Duplicate upload/completion calls are refused.
- Signing and probe operations reserve the same coordinator before signing. Background progress remains bound to its existing R8 job UUID. Cancellation during synchronous cryptographic work prevents subsequent upload but allows an already-started signing/R2 commit to settle safely. Signed library/pending artifacts are not deleted. This does **not** add page-level cancellation throughout the signing engine.
- Probe workers are retained through completion, polling is cancellation-aware, late observations cannot write another test's result. Synthetic signed probes use unique app-owned, backup-excluded Application Support directories and survive canceled/failed tests instead of being removed while delivery might read them. Explicit retention cleanup/UI for these synthetic probes remains future resource-budget work; no user IPA is moved/deleted by this change.
- Token/bucket setup checks have independent generations and snapshot checks; they report setup notes without overwriting active installation state. Cancellation controls are available in Sign, install settings and the active certificate test row.
- R14 journal semantics remain unchanged: preparation commits before remote writes; expiry commits before returning a link; cancellation leaves destination-bound cleanup records, and active records are excluded from sweeping until their publishing task actually settles. Old source/signed files remain available to R3 retry/export paths.

## Regression coverage and verification

`Tests/AppModelTests/OTASessionOutcomeTests.swift`: deterministic async gates exercise already-canceled admission/completion; busy-before-await; probe-versus-install admission; late readiness disposal; parent cancellation; immutable endpoint/token; host changes during delivery; stale delivery/upload/progress; once-only publication/completion; canceled signing/polling; failed upload retaining output; identity-bound observations. Synthetic publishers deliberately ignore cancellation so stale callback safety is tested independently of URLSession cooperation.

Swift frontend parsing of changed Swift sources/tests succeeds in the offline Swift 6.2.3 Linux container. This is syntax verification, not Apple framework typechecking. Full package, unsigned iOS build and Simulator outcome tests are required on macOS CI; results will be recorded after execution. Existing bucket, background, loopback, R1/R2 and signing suites remain enabled.

## Limits and device protocol

Physical checks still required: cancel before/after TLS readiness, during real range transfer, after handing off; edit host settings mid-transfer; attempt probe during signing/install; background/lock/grace expiration; verify prior IPA hashes and export after cancellation. Distinguish delivered bytes, detected scheme, OS installation and actual app launch. Shared loopback certificate trust remains R19. Cross-process/durable pipeline resumption and fully cooperative engine cancellation remain incomplete original R8/R20 scope. No deployment or security bypass is introduced.

UI ownership follow-up: Sign's Start over/cancel actions now target only SigningModel's own reservation; they cannot stop a probe that started after an older installation was canceled. Reopening a retained link is disabled over another owner. Notification foreground waits retain/cancel a task and recheck the captured session after the delay, so an old notification cannot open over a newer operation. Two additional model tests cover both cases.
