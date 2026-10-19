# R8 cooperative signing cancellation bridge

Status: implementation prepared; macOS CI pending. Composite development base combines unchanged #19 OTA ownership and #23 extraction budgets. The new PR targets `codex/r8-signing-cancellation-base`; neither prerequisite PR was merged into main.

## Why this follows the earlier ownership milestone

#19 invalidates owners/stops hosts/suppresses stale completion and retains completed artifacts, but synchronous IPASigner work could continue through an entire extraction after cancellation. Dispatch workers do not inherit the originating Swift task; checking Task.isCancelled inside those workers alone cannot establish parent ownership. #23 provides an explicit cancellation checkpoint during reads/decoded chunks.

`SigningCancellation` is a small thread-safe, one-operation token. A session's release callbacks cancel only its worker token, once. SigningModel forwards retained task cancellation and session release; IdentityTester forwards both worker/parent cancellation and reservation release. Late registration against a closed owner cancels that token immediately, never a replacement session. R3's persistence and R14's bucket ledger are unchanged.

IPASigner passes the owner token to extraction; checks it at stage boundaries; BundleSigner checks between discovered/planned bundles, resource sealing, code hashing, key calls and executable writes. A key operation or single synchronous file/hash call already in progress settles safely. No unsafe thread interruption, key deletion, signature-algorithm change or verification bypass.

## Publication contract

Cancellation is honored before the final staged archive enters R2's byte/tree verification and atomic promotion. Once that publication phase starts, later cancellation is ignored by the signing token: verification/promotion must settle and any completed signed result is returned to the existing R3 report/save path. OTA ownership still prevents canceled installation from uploading it. This avoids losing the only useful signed output because cancellation raced a commit. Both R2 manifest verification calls and promotion remain unchanged and mandatory.

A token cannot be reused for another IPA operation. Direct BundleSigner in-place callers can opt into checkpoints but still own their tree: cancellation does not make an in-place API transactional. IPASigner uses isolated scratch and removes its owned partial tree on failure; prior output remains intact.

## Tests / remaining scope

8 SigningCancellationTests: cancel-before-start; extraction/sign/verification-stage refusal; cancellation during staged packing; pre/post-publication barrier; completed output retention and token reuse refusal; synchronous key operation settles then cancels before next write; explicit token observed by a Dispatch worker. Two more app-model cases prove release callbacks don't cancel a newer worker and probe cancellation reaches a suspended signing token. All existing R3/R8/R14/R1/R2 tests stay enabled. Offline frontend parsing passed; final macOS package/build/Simulator results will be recorded in the master checkpoint/PR.

Not every CPU loop has page-level interruption: CodeResources/CodeDirectory/Mach-O thinning and blocking filesystem calls can delay the next checkpoint. Background-expiration-to-job cancellation, bounded retained synthetic probes and durable pipeline resume remain incomplete original R8/R20 scope. No iPhone lock/background/installation/launch evidence. Performance cost is a small locked token check per ZIP chunk/file/stage; no phone throughput/battery claim.
