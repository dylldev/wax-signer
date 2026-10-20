# R7 / R15 continuation — 2026-10-20

PR #28 was squash-merged with explicit user authorization after its unchanged reviewed head `11aada4954cf8cab17a807b2fc08e08f3f2b09fe`, successful CI 39495578350, empty unresolved review threads and clean merge/protection checks. Merge: `b4214fe592f4d391a3851cd19d2c0ea21a94c4d2`. Actual-main push verification: [39503390099](https://github.com/dylldev/wax-signer/actions/runs/39503390099), **SUCCESS**: 713 package/366 Simulator tests, 13/11 skips and zero failures, unsigned build plus Python/shell/codesign/CMS. R1/R2 ancestry and exact R7 tree equality were checked after merge.

Only open source PR now: [#29](https://github.com/dylldev/wax-signer/pull/29), `codex/r15-prepared-ipa-preview`, based on that main. It contains the prepared-IPA/app confirmation completion, not a composite replay of the original PR tree. It depends on merged R3/R6/R7/R8/R14 foundations. SigningModel, SignView, BundleSigner and archive manifest checkpoint APIs require combined package, app-model, build and Simulator testing; exact-head CI is mandatory. Leave #29 open for independent review. No other merge is authorized by the latest feature request.

All earlier integration milestones and original scope below are history; remaining incomplete roadmap items are not marked complete by this continuation.

# Existing-PR integration — current checkpoint

Updated2026-10-20. This section supersedes historical old-main and no-merge statements below. User explicitly authorized integration of the original24 source PRs. **All24 merged individually** through supported GitHub operations, exact-head checks, live review/protection checks and incremental merge-tree validation. No Phase7 feature is included. No force-push, admin bypass, release, deployment, production credential or distribution-repository mutation occurred.

Baseline `8ad4b2eed8b062b0ddb419f33fa0f858ff0b0379`. Integrated source/documentation main before this regression checkpoint: `48b6e2a56959ca1fb176abd5bd0ce07127190832`. The integration branch's production/configuration tree is byte-for-byte identical to frozen combined candidate `ef427d4dde578d36d244ade0233005feea915aae`. Initial [combined CI39349296379](https://github.com/dylldev/wax-signer/actions/runs/39349296379) passed **before the first merge**:695 package tests/13 skips;366 Simulator tests/11 skips;0 failures; unsigned iOS build;55 server/26 source-release/6 probe tests; both shell suites; independent codesign/CMS fixture controls executed.

Main checkpoints b4d5079/[39350943230](https://github.com/dylldev/wax-signer/actions/runs/39350943230) (664 package/310 Simulator) and8773c99/[39352035793](https://github.com/dylldev/wax-signer/actions/runs/39352035793) (667/310), each13/11 skips and0 failures, also passed. Updated conflict-bearing PR15 head0ccac85/run39350807268, PR19 head4eebf6b/run39352047580 (667/327), and PR21 head46d50a0/[39353267108](https://github.com/dylldev/wax-signer/actions/runs/39353267108) (691/363) each passed their own macOS package/build/Simulator gates before merging. PR6's updated docs headdea2b8e/run39352249119 also passed. Intermediate superseded main runs were canceled only after checking for actual failure; canceled runs are not represented as successful. One duplicate PR15 run39350807115 was canceled after verifying identical head/base/workflow; retained39350807268 passed.

**Current verification gate:** #27 now contains only four interaction regressions and current records. Its updated exact head must pass macOS CI before merge. Actual final main must then pass its own push workflow. The final SHA/run/counts are recorded in #27 after execution, avoiding a false claim that an unexecuted self-referential documentation commit is already verified. Current full local Apple builds are unavailable (Linux host); macOS CI supplies Apple SDK/Xcode/Simulator/tool verification.

## Actual dispositions and scope

Original inventory24 open PRs (#3–#26): merged24; closed as superseded0; original PRs remaining0. Every original PR had unique required work, so none was closed merely to reduce the count. #27 is the narrow regression/checkpoint PR, not a composite squash shortcut. Remote branch cleanup remains gated on final-main SUCCESS, preserved merge ancestry, exact expected remote tips and no active dependency; local worktrees and original untracked audit artifacts are retained.

| Original task | Actual integrated milestone / remaining work |
|---|---|
| R3 | Durable SHA-256 library/index transactions, recovery and truthful save outcomes integrated; real-device/files-provider/low-storage verification remains. |
| R4 | Artifact-derived source validation and reproducible staged repair integrated; distribution repository/deployment not changed. |
| R5 | Isolated concurrent uploads and session publication integrated; live deployment/proxy acceptance not performed. |
| R6 | Independent App ID prefixes integrated; authorized real-profile/keychain-continuity device gate remains. |
| R7 | Source/download/reply/icon/extraction/JSON-structure budgets integrated; packaging scratch, provider, legacy-cache/artwork/whole-engine budgets remain unfinished. |
| R8 | Loopback/background/OTA session ownership, signing cancellation and expiration integrated; deeper CPU boundaries and bounded probe retention remain. |
| R9 | Off-main retained credential import/retry integrated; actual supported-device custody/responsiveness remains unverified. |
| R10 | Truthful observation/delivery wording and shelf-save outcomes integrated; contextual snapshots/retry history remain. |
| R11 | Tagged-source candidate validation integrated; approved-tag actual candidate/protected promotion/rollback not executed. |
| R12 | Source-built probe packaging and retained CI evidence integrated; physical installation/launch controls remain. |
| R13 | Deterministic synchronized benchmark timing/output isolation integrated; representative corpus/metrics/phone budgets remain. |
| R14 | Source cache transactions and destination-bound bucket cleanup ledger integrated; secret/accessibility migration remains. |
| R15 | Immutable unpacked-tree planning/execution parity integrated; prepared-IPA/app confirmation/stale-config transaction remains. |
| R16 | Hidden/inactive animation and prior source IDs integrated; browsing/details/artwork/localization/AX work remains. |
| R17 | Signing graph/integrity history investigated, not completed. |
| R18 | Measured optimizations/new formats investigated, not completed; R12/R13/R17 gates remain. |
| R19 | Research/protocol only; legitimate domain/issuer authorization and physical experiments blocked. No private-TLS feature claimed. |
| R20 | Library journal/probe v1 are groundwork; recoverable jobs/probe improvements/diagnostics not completed. |

Program remains **PARTIALLY COMPLETE**. Integration of implemented milestones does not complete partial original roadmap items.

## Conflicts and combined regression preservation

- LoopbackHostTests: retain both connection/stop/backpressure/cancel/republish/empty-input controls and truthful incomplete-transfer assertions.
- IdentityReadiness: retain generation-owned tasks/reservations, source-built probe build1, retained artifacts, cancellation-aware polling and centralized detected/launch-unverified wording.
- BundleSigner: retain shared immutable prepare/entitlement resolution, exact-raw-CMS trust caching, frozen plan and R8 entry/after-thinning cancellation checks. Main production/config matches the tested candidate; no whole-side source resolution discarded another milestone.
- SourceStoreTests forward merge: the only difference was the new stale-refresh/budget interaction regression; retained it alongside every original source cache/budget test.
- Historical checkpoint add/add conflicts: newer main records preserved the original specifications/evidence and appended authorized integration state. Historical instructions are labeled as history.
- Four new tests: canceled owner cannot enter shared planning/direct prepare; canceled frozen execution refuses mutation/reuse; App ID prefix agrees between plan and execution; rejected JSON-budget refresh cannot authorize a stale response commit. No signing algorithm or credential policy change.

Dependencies followed:3 before12/14/17;4 and source-built probe11 before release tooling18 execution;7 before21;13/14/17 before19;14 before20;19 and23 before24;24 before25. Development composite bases were not merged wholesale as unrelated features. Dependency roots retained merge ancestry; focused leaves used squash; retargeted24/25 after parents landed; ordinary forward integration preserved published histories15/19/21.

## Exact original PR dispositions

| PR | Original branch | Original head | Verified merge head | Disposition | Merge SHA |
|---|---|---|---|---|---|
| [#3](https://github.com/dylldev/wax-signer/pull/3) | `codex/r3-durable-library` | `2a045f98c18ae2d09fc881c192c13b3828f9f610` | `2a045f98c18ae2d09fc881c192c13b3828f9f610` | Merged (merge) | `8da5dc70be11b50e48f5eeb1a92bd6adcccbe20c` |
| [#4](https://github.com/dylldev/wax-signer/pull/4) | `codex/r4-distribution-correctness` | `45342312868f6e31af28f1b7402edcdc55631b2e` | `45342312868f6e31af28f1b7402edcdc55631b2e` | Merged (merge) | `8709429707cd44c64a90d72df063f77d8f58daa3` |
| [#5](https://github.com/dylldev/wax-signer/pull/5) | `codex/r5-ota-upload-reliability` | `3e30326629fa1db3536b0e03dd994122b502fa47` | `3e30326629fa1db3536b0e03dd994122b502fa47` | Merged (squash) | `cce1e28dceab64efc9c8d58590498f7a03ee53b2` |
| [#6](https://github.com/dylldev/wax-signer/pull/6) | `codex/master-roadmap-execution` | `049d56ded87f3f0f3493aebea2e03d78962d0bec` | `dea2b8e9fe9ee5ed7967085b309bc28c0e79d53f` | Merged (squash) | `a5069ebbd5e502227a0221d8604319033f5b90a4` |
| [#7](https://github.com/dylldev/wax-signer/pull/7) | `codex/r6-app-id-prefix` | `3ef32fec540cc7af3ea979ce9cb2b17a42786d8a` | `3ef32fec540cc7af3ea979ce9cb2b17a42786d8a` | Merged (merge) | `485aedb31675dc1b09d11fc1fee9f65e3e614f75` |
| [#8](https://github.com/dylldev/wax-signer/pull/8) | `codex/r14-source-cache-transactions` | `be5c53c6a63c0f8d5dd2a86e41f1f0b90a74d249` | `be5c53c6a63c0f8d5dd2a86e41f1f0b90a74d249` | Merged (squash) | `207eaa40dc99bab2d3f242e3620e3b4da7b37b27` |
| [#9](https://github.com/dylldev/wax-signer/pull/9) | `codex/r13-performance-evidence` | `6d4ccf0e8bfeee2d4bc22b06cccc4e1c9d2cd6ef` | `6d4ccf0e8bfeee2d4bc22b06cccc4e1c9d2cd6ef` | Merged (squash) | `e6b56ad6af1b061151892c0ec2fd4ae62d3c49bf` |
| [#10](https://github.com/dylldev/wax-signer/pull/10) | `codex/r7-download-budgets` | `023a29b67390575f1815b99c8526ccbbd5822880` | `023a29b67390575f1815b99c8526ccbbd5822880` | Merged (squash) | `bd16bcd155a42b0ca53841994abc2490599dcb38` |
| [#11](https://github.com/dylldev/wax-signer/pull/11) | `codex/r12-probe-conformance` | `afb1ce598c4de957c9edaecc555cecdd77570a65` | `afb1ce598c4de957c9edaecc555cecdd77570a65` | Merged (squash) | `ff3e9d6ace4291afcb05d6b337afaa72200f95bb` |
| [#12](https://github.com/dylldev/wax-signer/pull/12) | `codex/r9-responsive-import` | `e60774128ce0d7b48c679af4583d5afb9356bb85` | `e60774128ce0d7b48c679af4583d5afb9356bb85` | Merged (squash) | `a50e1632e5c22293f527e75f11ec4e837646c430` |
| [#13](https://github.com/dylldev/wax-signer/pull/13) | `codex/r8-loopback-session-ownership` | `0a044e02d753c93d65b1200700a206532e50183c` | `0a044e02d753c93d65b1200700a206532e50183c` | Merged (merge) | `c0304d548411933b799bb1cb4524c337f9cc0eec` |
| [#14](https://github.com/dylldev/wax-signer/pull/14) | `codex/r14-bucket-cleanup-ledger` | `0760cf52adb02a47cfb5ae0dcb853a20a27f147a` | `0760cf52adb02a47cfb5ae0dcb853a20a27f147a` | Merged (merge) | `d40c4a824a0053780cb232fdf8a37ce45ef8204f` |
| [#15](https://github.com/dylldev/wax-signer/pull/15) | `codex/r10-install-observation-language` | `73d3020f92781a3978e7ba7a857537fb48a04f91` | `0ccac854a6a40d14ecc7aafc7ede594898deb37e` | Merged (squash) | `8773c9970e9ba3691542db3a7c557d6ccf4f680f` |
| [#16](https://github.com/dylldev/wax-signer/pull/16) | `codex/r16-pause-hidden-animation` | `035c0ddc3e6c91667747644e9ff07ec07d074b99` | `035c0ddc3e6c91667747644e9ff07ec07d074b99` | Merged (squash) | `201f6411b95318db0280aa13cc81b8c2619f46a7` |
| [#17](https://github.com/dylldev/wax-signer/pull/17) | `codex/r8-background-job-ownership` | `731e5fc46d30e0c1520c7b561bce6687dc691932` | `731e5fc46d30e0c1520c7b561bce6687dc691932` | Merged (merge) | `ccd994f16daafd692fe93bf1191b018a67d9e8c4` |
| [#18](https://github.com/dylldev/wax-signer/pull/18) | `codex/r11-release-candidate-gate` | `524ef773ab58784440347165bdde65fc106cefb0` | `524ef773ab58784440347165bdde65fc106cefb0` | Merged (squash) | `b4d507923de6da4de20f15017df139931d486d3d` |
| [#19](https://github.com/dylldev/wax-signer/pull/19) | `codex/r8-ota-session-ownership` | `b7edd93e975cbdb48a90169f2aa6f159363d8634` | `4eebf6b00d8ef900c99b6754ee20993d34363ef4` | Merged (merge) | `65486c34a6afce61e55fdbe3f2a4d44787cea07f` |
| [#20](https://github.com/dylldev/wax-signer/pull/20) | `codex/r7-install-response-budgets` | `de21fa573a27f19293a112c9db5d8465266c5230` | `de21fa573a27f19293a112c9db5d8465266c5230` | Merged (squash) | `2f9612fdcb1ffbab387e0ca82bff33257968c772` |
| [#21](https://github.com/dylldev/wax-signer/pull/21) | `codex/r15-read-only-signing-plan` | `c8248a8f0385a460a59864e1c31e3224984bcee5` | `46d50a05cb584da7a760381de9b16ce954d0cb35` | Merged (merge) | `48b6e2a56959ca1fb176abd5bd0ce07127190832` |
| [#22](https://github.com/dylldev/wax-signer/pull/22) | `codex/r7-icon-input-budgets` | `698b741c0d679a78b3b0fc29c20a6ad9df43ec0f` | `698b741c0d679a78b3b0fc29c20a6ad9df43ec0f` | Merged (squash) | `de7acde45465b374dadcc3600528c4ac69f16aa2` |
| [#23](https://github.com/dylldev/wax-signer/pull/23) | `codex/r7-extraction-budgets` | `1d6f207f0cdb08ab0424d990fd2daebf074a064d` | `1d6f207f0cdb08ab0424d990fd2daebf074a064d` | Merged (merge) | `05a4c6961b9dd92f580615c635bde49c791dcf4b` |
| [#24](https://github.com/dylldev/wax-signer/pull/24) | `codex/r8-signing-cancellation` | `11150a48c393f7ab20b4b6add6c6540a65db2531` | `11150a48c393f7ab20b4b6add6c6540a65db2531` | Merged (merge) | `a4087fdda6c2f3b3655d93b8382ae30aa79b96bb` |
| [#25](https://github.com/dylldev/wax-signer/pull/25) | `codex/r8-background-expiration` | `a33156f230cece7d07db0704c127c73992213f50` | `a33156f230cece7d07db0704c127c73992213f50` | Merged (squash) | `867ca2d9cc2f9d2385abd890f2f3724289d90c80` |
| [#26](https://github.com/dylldev/wax-signer/pull/26) | `codex/r7-source-object-budgets` | `a3774382c5b1465493d65efe08c243104fa27db6` | `a3774382c5b1465493d65efe08c243104fa27db6` | Merged (squash) | `b5cba2f02aada53b76d0b059996aa773d2df615d` |

## Next exact action and device requirements

1. Push updated narrow #27; obtain its exact-head full macOS CI, inspect logs, merge only if checks/reviews/protections permit. Inspect actual final-main push CI and record final SHA/counts/URLs on #27. Then safely delete obsolete remote task/composite refs only after preservation checks; retain all local worktrees/untracked audits.
2. After final-main SUCCESS, create a focused R7 packaging-budget branch: bounded compression workers, output-owned scratch, active temporary-write/disk/deadline/cancellation checks, preserving R2 final actual-byte/tree verification and R8 publication sealing. New Phase7 features remain review-gated and must not be auto-merged.
3. Continue R15 prepared-IPA snapshot/preview/confirm, then remaining R8/R10/R14/R16 and original R17–R20 in dependency order. Preserve the original task specifications below; do not recreate completed implementation.

Physical gates remain: authorized certificate/profile import and Keychain custody; files-provider/low-storage/restart recovery; normal/nested/extension sign, export, supported install and actual launch; lock/background expiration/cancel/retry; app-update prefix/keychain continuity; issuer/domain TLS experiments. Simulator tests, internal signature consistency, independent codesign/CMS fixtures, OS trust, physical install and physical launch are distinct. No real-device result, distribution publication or iPhone performance improvement is claimed.

Durable session state: `/workspace/shared/wax-pr-integration-state.json`; resumed tools `/workspace/shared/integration-tools/`. Detailed machine-readable dispositions are in INTEGRATION-LEDGER.json. Original untracked ROADMAP/AUDIT/repros remain untouched.

---

## Historical inventory and checkpoints

Preserved for traceability. Old main/open counts, no-merge instructions and next actions below are historical; use the current checkpoint above.

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


## Authorized integration checkpoint — 2026-10-20

The latest user instruction explicitly authorizes verified integration/merging/closure of the existing source PRs #3–#26. Earlier no-merge instructions in historical sections are superseded for this frozen inventory; newly developed Phase7 features remain separately review-gated. No branch protection, required approval or failing check may be bypassed. Distribution repository/release/deployment/production credentials remain out of scope.

Original source main8ad4b2e; original24 open PRs all had green frozen-head checks, zero unresolved review threads and no configured main protection rules. The one PR3 general issue comment was inspected as nonblocking design advice, not a formal change request; no external promotional link was followed. Combined branch codex/verified-roadmap-integration, PR#27, ef427d4dde578d36d244ade0233005feea915aae passed CI39349296379:695 package tests/13 skips,366 Simulator tests/11 skips,0 failures; unsigned iOS build;55 server/26 source-release/6 probe tests; both shell suites; independent codesign/CMS fixtures. This success preceded every main merge.

Three explicit combined resolutions retain both loopback test suites, owned probe tasks+source-built build1+central truthful messages, and shared immutable planning/exact-CMS trust plus cancellation checks. Four new interaction regressions are on #27 and will be integrated only as a narrow follow-up after existing source changes reach main; #27 is not a wholesale composite squash shortcut.

### Merged and tree-verified so far

| PR | Original head | GitHub merge SHA | Method |
|---|---|---|---|
| #3 | `2a045f98c18ae2d09fc881c192c13b3828f9f610` | `8da5dc70be11b50e48f5eeb1a92bd6adcccbe20c` | merge |
| #4 | `45342312868f6e31af28f1b7402edcdc55631b2e` | `8709429707cd44c64a90d72df063f77d8f58daa3` | merge |
| #5 | `3e30326629fa1db3536b0e03dd994122b502fa47` | `cce1e28dceab64efc9c8d58590498f7a03ee53b2` | squash |
| #7 | `3ef32fec540cc7af3ea979ce9cb2b17a42786d8a` | `485aedb31675dc1b09d11fc1fee9f65e3e614f75` | merge |
| #8 | `be5c53c6a63c0f8d5dd2a86e41f1f0b90a74d249` | `207eaa40dc99bab2d3f242e3620e3b4da7b37b27` | squash |
| #9 | `6d4ccf0e8bfeee2d4bc22b06cccc4e1c9d2cd6ef` | `e6b56ad6af1b061151892c0ec2fd4ae62d3c49bf` | squash |
| #10 | `023a29b67390575f1815b99c8526ccbbd5822880` | `bd16bcd155a42b0ca53841994abc2490599dcb38` | squash |
| #26 | `a3774382c5b1465493d65efe08c243104fa27db6` | `b5cba2f02aada53b76d0b059996aa773d2df615d` | squash |
| #12 | `e60774128ce0d7b48c679af4583d5afb9356bb85` | `a50e1632e5c22293f527e75f11ec4e837646c430` | squash |
| #13 | `0a044e02d753c93d65b1200700a206532e50183c` | `c0304d548411933b799bb1cb4524c337f9cc0eec` | merge |
| #14 | `0760cf52adb02a47cfb5ae0dcb853a20a27f147a` | `d40c4a824a0053780cb232fdf8a37ce45ef8204f` | merge |
| #17 | `731e5fc46d30e0c1520c7b561bce6687dc691932` | `ccd994f16daafd692fe93bf1191b018a67d9e8c4` | merge |
| #11 | `afb1ce598c4de957c9edaecc555cecdd77570a65` | `ff3e9d6ace4291afcb05d6b337afaa72200f95bb` | squash |
| #20 | `de21fa573a27f19293a112c9db5d8465266c5230` | `2f9612fdcb1ffbab387e0ca82bff33257968c772` | squash |
| #23 | `1d6f207f0cdb08ab0424d990fd2daebf074a064d` | `05a4c6961b9dd92f580615c635bde49c791dcf4b` | merge |
| #22 | `698b741c0d679a78b3b0fc29c20a6ad9df43ec0f` | `de7acde45465b374dadcc3600528c4ac69f16aa2` | squash |
| #16 | `035c0ddc3e6c91667747644e9ff07ec07d074b99` | `201f6411b95318db0280aa13cc81b8c2619f46a7` | squash |
| #18 | `524ef773ab58784440347165bdde65fc106cefb0` | `b4d507923de6da4de20f15017df139931d486d3d` | squash |
| #15 | `73d3020f92781a3978e7ba7a857537fb48a04f91` | `8773c9970e9ba3691542db3a7c557d6ccf4f680f` | squash |

Current main at this document's authoring is8773c9970e9ba3691542db3a7c557d6ccf4f680f (19 original PRs merged). Main checkpoint b4d507923de6da4de20f15017df139931d486d3d passed full CI39350943230:664 package/13 skips;310 Simulator/11 skips;0 failures; unsigned iOS build and55 server/26 source/6 probe/shell tests. Later R10 head0ccac854a6a40d14ecc7aafc7ede594898deb37e passed39350807268:636 package/13 skips;301 Simulator/11 skips;0 failures and unsigned build, then merged as8773c99. These are distinct verification levels, not a final-main claim.

Dependency roots use GitHub-supported merge commits to retain original parent ancestry; independent leaves use squash. Before each merge: live frozen/explicitly updated head, successful applicable checks, no unresolved threads/required blocker, incremental file scope against original base, clean merge-tree simulation; after merge: GitHub merged state, merge SHA, exact simulated tree and main ancestry. No force-push/admin override.

### Current next action

Wait for PR#19 forward-integrated head4eebf6b00d8ef900c99b6754ee20993d34363ef4 / CI39352047580. Its original head b7edd93 was preserved by an ordinary forward merge with main; IdentityReadiness resolution comes from inspected/tested combined stage293b736. After success, merge19; retarget24/25 and verify only their increments; forward-integrate21 using stageb6caf50 BundleSigner shared prepare/cancellation resolution, obtain its own green CI. PR#6's updated documentation head also needs its own checks. All final dispositions, new source/regression-only #27 diff, final-main CI and safe branch cleanup still require completion.

A redundant identical PR15 CI event39350807115 was canceled only after confirming same head/base/workflow/creation instant; retained39350807268 passed. Superseded intermediate main runs were canceled to conserve runners, never represented as passing. Major checkpoint39350943230 was retained through success. One transient read-only401 recovered by bounded normal API retry; no authentication settings changed.

Program remains PARTIALLY COMPLETE. Original R7 packaging/provider/legacy-cache/artwork/whole-engine budgets; R15 prepared-IPA/app preview; R8 deeper cancellation/probe retention; R10 contextual history; R14 secret/accessibility migration; R16 browsing/AX; R17–R20 remain as inventoried. Device install/launch/OS expiry, actual Keychain custody and issuer-policy experiments remain unverified. Read-only packaging investigation is saved at /workspace/shared/WAX-R7-PACKAGING-NEXT.md, not implementation.

Per-merge resumable state: /workspace/shared/wax-pr-integration-state.json; guarded scripts /tmp/wax-merge-one.py, /tmp/wax-forward-pr.py, /tmp/wax-cancel-obsolete-main.py, /tmp/wax-integration-progress.py. PR#27 description carries the current durable live table. Original audit artifacts remain untracked and untouched. No release/deployment/distribution or production credential change occurred.
