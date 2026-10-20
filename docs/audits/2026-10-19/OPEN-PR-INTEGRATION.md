# Non-destructive open-PR integration assessment

Snapshot refreshed: 2026-10-20; main remains `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`. No PR was merged and no main/distribution history was changed. Commands: `git fetch origin`, GitHub open-PR/status/review-thread APIs, `git diff --name-only <declared-base>...<head>`, then `git merge-tree --write-tree --name-only <head-A> <head-B>` for pairs with overlapping net files. Merge-tree only writes temporary Git objects, not a checkout, index, branch tip or published merge. This is a textual/dependency assessment, not a full combined build or authorization to merge.

All returned open review-thread lists had zero unresolved threads. All older heads (#3–#18) retained their previously green CI, including documentation #6 run39312680325; new heads #19–#22 now each have final-head SUCCESS (details in the master checkpoint). The refreshed API returned24 open source PRs, no additional pages, zero unresolved threads and MERGEABLE against each declared base. No `reviewDecision` was APPROVED: absence of a blocker is not independent approval. Main's branch API returned protected=false and the applicable rulesets API returned[]; recheck protections/checks/reviews immediately before any later authorized merge. User instructions still require independent review.

## Explicit dependencies

- #3 → #12 (credential imports), #14 (bucket ledger), #17 (background ownership).
- #13 + #14 + #17 → composite base `codex/r8-session-prerequisites` at `6b926e3` → #19. This base is a reproducible development-only combination, not a substitute for reviewing/merging the three prerequisite PRs. #14/#17 include current R3 `2a045f9`.
- #14 → #20 (bounded install replies/confirmed cleanup).
- #19 + #23 → composite `codex/r8-signing-cancellation-base` at `4554d4a` → #24 → #25 (background expiration). Review/integrate actual prerequisite PRs individually; the composite is a development/test base only.
- #26 (source JSON complexity) is independent of #8/#10, but they require combined source fetch/cache/budget regressions.
- #7 → #21 (R15 plan with correct independent App ID prefix).
- #4 → #18; **executing** R11 candidate generation also requires #11's source-built probe integration. Stacking base #4 alone does not establish that runtime prerequisite.
- Distribution `dylldev/wax` PR#1 is a separate staged repair, head `2bce8857accc063316f08854eec8afb887ca903a`, with no CI workflow. It can receive independent review alongside #4; it does not publish a new signer. No Pages deployment/release is authorized.

## Exact recommended merge order

Only after independent approval of each change, current required checks/protections and conflict resolution. This sequence is a recommendation, not an action taken. Following squash merges, dependent PRs must be retargeted/synchronized against main with ordinary forward integration and checked again; do not blindly merge composite bases, duplicate parent changes, force-push or infer ancestry from the old SHA.

| Order | PR / task | Declared base | Frozen head |
|---|---|---|---|
| 1 | [#3](https://github.com/dylldev/wax-signer/pull/3) R3: Make IPA library storage durable and non-destructive | `main` | `2a045f98c18ae2d09fc881c192c13b3828f9f610` |
| 2 | [#4](https://github.com/dylldev/wax-signer/pull/4) R4: Generate coherent distribution metadata from verified IPA artifacts | `main` | `45342312868f6e31af28f1b7402edcdc55631b2e` |
| 3 | [#5](https://github.com/dylldev/wax-signer/pull/5) R5: Isolate OTA uploads and protect active session publication | `main` | `3e30326629fa1db3536b0e03dd994122b502fa47` |
| 4 | [#7](https://github.com/dylldev/wax-signer/pull/7) R6: Preserve App ID prefixes independently of Team IDs | `main` | `3ef32fec540cc7af3ea979ce9cb2b17a42786d8a` |
| 5 | [#8](https://github.com/dylldev/wax-signer/pull/8) R14: Serialize source cache commits and invalidate obsolete ETags | `main` | `be5c53c6a63c0f8d5dd2a86e41f1f0b90a74d249` |
| 6 | [#9](https://github.com/dylldev/wax-signer/pull/9) R13: Make benchmark timing collection deterministic and race-free | `main` | `6d4ccf0e8bfeee2d4bc22b06cccc4e1c9d2cd6ef` |
| 7 | [#10](https://github.com/dylldev/wax-signer/pull/10) R7: Enforce source and IPA download budgets during acquisition | `main` | `023a29b67390575f1815b99c8526ccbbd5822880` |
| 8 | [#26](https://github.com/dylldev/wax-signer/pull/26) R7: Bound source JSON complexity before decoding | `main` | `a3774382c5b1465493d65efe08c243104fa27db6` |
| 9 | [#12](https://github.com/dylldev/wax-signer/pull/12) R9: Keep credential imports responsive and retryable | `codex/r3-durable-library` | `e60774128ce0d7b48c679af4583d5afb9356bb85` |
| 10 | [#13](https://github.com/dylldev/wax-signer/pull/13) R8: Own loopback transfers across stop and republish | `main` | `0a044e02d753c93d65b1200700a206532e50183c` |
| 11 | [#14](https://github.com/dylldev/wax-signer/pull/14) R14: Retain destination-bound bucket cleanup obligations | `codex/r3-durable-library` | `0760cf52adb02a47cfb5ae0dcb853a20a27f147a` |
| 12 | [#17](https://github.com/dylldev/wax-signer/pull/17) R8: Isolate background resources for concurrent operations | `codex/r3-durable-library` | `731e5fc46d30e0c1520c7b561bce6687dc691932` |
| 13 | [#15](https://github.com/dylldev/wax-signer/pull/15) R10: Report delivery and probe observations without installation claims | `main` | `73d3020f92781a3978e7ba7a857537fb48a04f91` |
| 14 | [#11](https://github.com/dylldev/wax-signer/pull/11) R12: Build the installation probe from source and retain CI evidence | `main` | `afb1ce598c4de957c9edaecc555cecdd77570a65` |
| 15 | [#19](https://github.com/dylldev/wax-signer/pull/19) R8: Bind OTA preparation, cancellation and delivery to owned sessions | `codex/r8-session-prerequisites` | `b7edd93e975cbdb48a90169f2aa6f159363d8634` |
| 16 | [#20](https://github.com/dylldev/wax-signer/pull/20) R7: Bound install responses and cancel silent certificate downloads | `codex/r14-bucket-cleanup-ledger` | `de21fa573a27f19293a112c9db5d8465266c5230` |
| 17 | [#23](https://github.com/dylldev/wax-signer/pull/23) R7: Enforce extraction storage, deadline and worker budgets | `main` | `1d6f207f0cdb08ab0424d990fd2daebf074a064d` |
| 18 | [#24](https://github.com/dylldev/wax-signer/pull/24) R8: Cancel owned signing work before the final publication barrier | `codex/r8-signing-cancellation-base` | `11150a48c393f7ab20b4b6add6c6540a65db2531` |
| 19 | [#25](https://github.com/dylldev/wax-signer/pull/25) R8: Cancel operation-owned work on background expiration | `codex/r8-signing-cancellation` | `a33156f230cece7d07db0704c127c73992213f50` |
| 20 | [#22](https://github.com/dylldev/wax-signer/pull/22) R7: Bound custom icon reads and decode only thumbnails | `main` | `698b741c0d679a78b3b0fc29c20a6ad9df43ec0f` |
| 21 | [#21](https://github.com/dylldev/wax-signer/pull/21) R15: Expose immutable read-only signing plans and reject stale execution | `codex/r6-app-id-prefix` | `c8248a8f0385a460a59864e1c31e3224984bcee5` |
| 22 | [#16](https://github.com/dylldev/wax-signer/pull/16) R16: Pause decorative signing animation when hidden or inactive | `main` | `035c0ddc3e6c91667747644e9ff07ec07d074b99` |
| 23 | [#18](https://github.com/dylldev/wax-signer/pull/18) R11: Prepare validated release candidates from tagged sources | `codex/r4-distribution-correctness` | `524ef773ab58784440347165bdde65fc106cefb0` |
| 24 | [#6](https://github.com/dylldev/wax-signer/pull/6) Track R3–R20 execution evidence and continuation gates | `main` | `5c67e8cfd76beb754ffd2c76436357e0a455e838` |

#15 is deliberately before #19 so the R10 words and loopback-test union are resolved once before the final coordinator integration. #11 precedes #19/#18 so source-built probe/version1 behavior is preserved, not restored to the historical opaque resource. #21 is after #7 and does not by itself adopt a new app production CMS policy. #6 documentation is last so its ledger reflects actual reviewed integration, rather than asserting that a proposed order already happened.

## Confirmed textual conflicts

The refreshed overlapping-net-file assessment checked33 overlapping PR pairs;8 returned conflicts. Dependencies can inherit a known conflict even when their new net file sets are disjoint. In particular #25 inherits #24/#21 BundleSigner integration requirements.

- **#25 + #15:** `App/IdentityReadiness.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift`.
- **#25 + #11:** `App/IdentityReadiness.swift`.

- **#24 + #21:** `Sources/SigningKit/BundleSigner.swift`.
- **#24 + #15:** `App/IdentityReadiness.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift`.
- **#24 + #11:** `App/IdentityReadiness.swift`.
- **#19 + #15:** `App/IdentityReadiness.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift`.
- **#19 + #11:** `App/IdentityReadiness.swift`.
- **#15 + #13:** `Tests/InstallKitTests/LoopbackHostTests.swift`.

Required resolutions:

1. `Tests/InstallKitTests/LoopbackHostTests.swift` (#13/#15, also inherited into #19): retain **all** accepted-connection, backpressure/handle, cancellation/republish and empty-input tests **and** R10 truthful transfer-message assertions. Do not resolve by choosing an entire side or deleting tests. `LoopbackHost.swift` itself auto-merges, but its generation ownership and changed error wording both need to survive.
2. `App/IdentityReadiness.swift` (#19/#15/#11): retain #19's reservation-before-sign, retained tasks/artifacts, session-filtered callbacks and cancellation-aware polling; preserve #15's scheme-detected/launch-unverified wording and contextual limits; retain #11's source-built probe version1/build1 contract. #19 already sends build1 and uses detection wording, so review equivalent lines rather than restoring the old unowned implementation.

## Clean text merges that still need combined regressions

| Overlap / dependency | Combined verification gate |
|---|---|
| #3/#17/#19 `SigningModel.swift`, #3/#17 `SourcesModel.swift` | R3 save/index failure and retry/export + owned background UUID tests + R8 canceled signing/handoff. A completed signed artifact must remain durable even when install cancellation wins. |
| #14/#19 `OTAInstallModel.swift`, #14/#20 `S3Host.swift` | Bucket preparation before PUT; expiry before link; canceled/late publish cannot expose link; active-record cleanup exclusion; settings changes cannot redirect DELETE; bounded reply/deadline cancellation retains cleanup obligations. #19 tests #3/#13/#14/#17 together, but #19+#20 still needs a combined final-head CI. |
| #8/#10 `SourceStore.swift` | Both source-cache generation/ETag race tests and actual-byte/deadline/redirect budgets. Clean auto-merge does not prove a stale refresh cannot resurrect a removed source or acquire unbounded JSON. |
| #7/#12/#19 `CredentialsView.swift` | Prefix labels, import retry/cancel controls and probe admission/cancel must coexist. Run credential-import outcome tests, probe/install overlap tests, Dynamic Type/VoiceOver check. |
| #3/#11 `project.yml` | Preserve WaxModelTests target, source-built WaxProbe target/dependency/resource exclusions and bundled probe manifest test. Regenerate with XcodeGen, unsigned physical-iOS build and complete Simulator tests. |
| #3/#16/#19 `SignView.swift` | Preserve confirmed shelf-save messages/retry/export, owned install cancellation and hidden/inactive animation pause. Retained tabs stay mounted, so visibility cannot rely only on onDisappear. |
| #4/#18 Source scripts; #11 probe build | Run all source tests (26 on #18 baseline), probe packager6, allowlist/hash checks and an authorized fresh-tag candidate dry run only after integration. No publishing/deployment. |
| #7/#21 `BundleSigner.swift`; R1/R2 core | Run all prefix, signing plan, parser, entitlement/CMS and final-artifact regressions; independent codesign of normal and planned/re-extracted signed fixtures. Plan output is not provisioning/trust acceptance. |
| #5 server vs client lifecycle changes | Server55 concurrency/quota/retention cases plus client error/cancel tests. Proxy/slow-client operator checks and actual iPhone delivery are still separate. |

## Text-merge evidence

Pairs below are based on current declared-base net file overlap. A clean result means the Git merge algorithm found no textual conflict for that pair; it does not predict arbitrary future heads, sequential conflict resolutions or runtime correctness.

| PR pair | Result | Shared net files |
|---|---|---|
| #24 + #21 | CONFLICT | `Sources/SigningKit/BundleSigner.swift` |
| #24 + #19 | clean merge-tree | `App/IdentityReadiness.swift`, `App/OTAInstallModel.swift`, `App/SigningModel.swift`, `Tests/AppModelTests/OTASessionOutcomeTests.swift` |
| #24 + #17 | clean merge-tree | `App/SigningModel.swift` |
| #24 + #15 | CONFLICT | `App/IdentityReadiness.swift` |
| #24 + #14 | clean merge-tree | `App/OTAInstallModel.swift` |
| #24 + #11 | CONFLICT | `App/IdentityReadiness.swift` |
| #24 + #7 | clean merge-tree | `Sources/SigningKit/BundleSigner.swift` |
| #24 + #3 | clean merge-tree | `App/SigningModel.swift` |
| #23 + #21 | clean merge-tree | `Sources/IPAKit/ArchiveIntegrity.swift` |
| #21 + #7 | clean merge-tree | `Sources/SigningKit/BundleSigner.swift` |
| #20 + #14 | clean merge-tree | `Sources/InstallKit/S3Host.swift` |
| #19 + #17 | clean merge-tree | `App/SigningModel.swift` |
| #19 + #16 | clean merge-tree | `App/SignView.swift` |
| #19 + #15 | CONFLICT | `App/IdentityReadiness.swift` |
| #19 + #14 | clean merge-tree | `App/InstallSection.swift`, `App/OTAInstallModel.swift` |
| #19 + #12 | clean merge-tree | `App/CredentialsView.swift` |
| #19 + #11 | CONFLICT | `App/IdentityReadiness.swift` |
| #19 + #7 | clean merge-tree | `App/CredentialsView.swift` |
| #19 + #3 | clean merge-tree | `App/SignView.swift`, `App/SigningModel.swift` |
| #17 + #3 | clean merge-tree | `App/SigningModel.swift`, `App/SourcesModel.swift` |
| #16 + #3 | clean merge-tree | `App/SignView.swift` |
| #15 + #13 | CONFLICT | `Sources/InstallKit/LoopbackHost.swift`, `Tests/InstallKitTests/LoopbackHostTests.swift` |
| #15 + #11 | clean merge-tree | `App/IdentityReadiness.swift` |
| #12 + #7 | clean merge-tree | `App/CredentialsView.swift` |
| #11 + #3 | clean merge-tree | `project.yml` |
| #10 + #8 | clean merge-tree | `Sources/SourcesKit/SourceStore.swift` |

Additional sequential check: virtual non-published merge-tree/commit-tree objects combined #3, #4, #5, #7, #8, #9, #10, #12, #13, #14 and #17 cleanly, then stopped at #15 with the expected `LoopbackHostTests.swift` conflict. No conflict resolution was guessed, no assessment ref was pushed and no main/index/worktree was changed. Later steps are conditional on explicit reviewed resolution, not claimed to be fully simulated.

#22 is independent custom-icon acquisition/thumbnail limits. Its `SigningOptionsView.swift` and `AppEditor.swift` changes require combined image-edit/signing tests with #21's future preview integration, even without a current text overlap. Photos/iCloud lifetime and rapid selection/reset require a real device.

## Post-review integration procedure

Start an integration branch from freshly fetched main; integrate only independently approved changes in the order above. Keep all conflict resolutions explicit in commits for review. After each dependency group, run focused suites; at the complete integration head run full package tests, unsigned iOS build, Simulator app/model/probe tests, Python source/server/probe tests and shell assertions. Inspect actual logs and exact head SHA. Never treat the independent PR greens as a combined integration green. Retain xcresults/logs where the merged #11 workflow supports them. Finally perform the unexecuted physical-device matrix in the master checkpoint; do not claim actual installation/launch from Simulator or scheme detection.


Final-head code verification observed23:45UTC: #19 `b7edd93` CI39318615526, #20 `de21fa5` CI39317651235, #21 `c8248a8` CI39317698285, #22 `698b741` CI39318320934 allSUCCESS. Actual full package/iOS build/Simulator summaries are recorded in the master checkpoint. This does not change the unresolved combined-integration/device gates. PR#6's table SHA `ea1d3eb` is the starting documentation checkpoint, not the later documentation update containing this assessment.


Latest additions: #23 is independent extraction budgets; #24 depends on #19 + #23 through development composite `codex/r8-signing-cancellation-base` (`4554d4a`). Final CI is pending at this update, not covered by earlier greens. Recommended #23 → #24 → #21 integration keeps extraction/owner cancellation before R15 plan adoption. New conflict #24/#21 in BundleSigner requires retaining R15 shared planner/exact-CMS cache and R8 cancellation checks in shared preparation/execution. The #24/#15/#11 IdentityReadiness conflicts additionally require preserving the cancellation bridge alongside owned sessions, truthful probe wording and source-built probe1.0/build1. Add combined cancellation-at-each-stage, staged-packing/output-preservation, plan/stale-tree and low-storage regressions to the integration gate. No individual PR green proves that combined result.


## 2026-10-20 continuation gates

- #24's first run39344834650 passed612 package tests/13 skips and unsigned iOS build but failed to link WaxModelTests: the new tests directly use SigningCancellation without a SigningKit target dependency. Head `11150a48c393f7ab20b4b6add6c6540a65db2531` adds that explicit test dependency; corrected-head CI39345607344 subsequently succeeded:612 package/13 skips and306 Simulator/11 skips,0 failures; unsigned iOS build passed. This project.yml dependency must survive combined #3/#11 test/probe target integration.
- #25 adds background expiration callbacks and SourcesModel progress ownership. Preserve R3's completed-download retention and noninterruptible library transactions, #24's R2 publication barrier and #10's downloader cancellation-before-task-registration/byte/deadline defenses. Test foreground grace expiry, continued grant expiry, reentrant callbacks, old queued progress after retry, canceled late host readiness and bucket cleanup against original destinations. Background/OS scheduling still needs a phone.
- #26's SourceParser/SourceStoreTests changes text-merge with #8/#10 at this snapshot. Run their combined ETag/cache generation, cancellation, decoded-byte/total-time transfer limits, JSON structure/deadline refusal and cache/index preservation tests. A green source parser alone does not verify the integrated network/cache stack.
- #23's final run39344111323 actually succeeded:550 package/13 skips; unsigned build;240 Simulator/11 skips;0 failures. No Apple device evidence. New #25/#26 heads were pending at this inventory's initial refresh; master checkpoint supplies subsequent observed results.
- Recommended order now inserts independent #26 after #10 and dependent #25 after #24. #6 remains last and its table SHA is the documentation snapshot before the next checkpoint commit, not a self-referential final doc verification claim. Re-fetch and revalidate actual heads/reviews/protections before any later authorized merge.

#25 subsequently passed final-head run39345842055:612 package/13 skips,317 Simulator/11 skips,0 failures; unsigned iOS build and scripts passed. Its original pending text above describes the inventory refresh time, not the final observed result. Full combined #15/#11/#21 integration still has not been built or reviewed.

#26 subsequently passed final-head run39346300960:553 package/13 skips,240 Simulator/11 skips,0 failures; unsigned iOS build,45 server/3 source Python and both shell suites passed. All new parser/cache-refusal regressions executed. Thus all8 new source heads #19–#26 in this continuation are individually green. This does not resolve the8 documented pairwise conflicts or establish a full combined-integration test result.
