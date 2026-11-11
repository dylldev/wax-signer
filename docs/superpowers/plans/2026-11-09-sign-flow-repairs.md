# Sign flow repairs

Approved scope: restore host-independent signing/export, truthful progress, and phone handoff retry. No phone, merge, publication, credential changes, or adoption of the saved-file proposal. Base a906932; isolated branch codex/wax-sign-flow-repairs. Preserve OpenCode and credential worktrees.

1. Reproduce the host-reservation stage ordering with SignStageTests, then correct precedence and ordering in Sources/InstallKit/SignScreenLogic.swift. Signing and reading beat a reserved/preparing host; preparation precedes upload.
2. Add rendered SignView regressions in Tests/AppModelTests/SignPresentationTests.swift using synthetic credentials and injected hosts. Verify standalone export without host configuration, no100 percent at reservation, and actionable retry while a phone transfer remains pending. Run before changing App/SignView.swift.
3. Change only SignView presentation: host-independent export with credentials/profile checks; preparation does not imply uploaded bytes; active signing wins over reservation; keep retry and stay-open text outside the progress card accessibility group.
4. Run package tests, hosted presentation/model tests, normal and Dev simulator builds, independent source review, and free-only quorum for the shared presentation contract. Preserve logs and report missing reviews. Do not clear physical-device, signing-library, or accessibility gates.

Existing tests encode an incorrect preparation-after-upload assumption; update those expectations to the real OTA lifecycle. Do not weaken failed checks. The unrelated saved-list race remains outside this scope.

## Reproduction and verification

The baseline targeted package run passed11 tests. The corrected stage test first failed on preparation precedence and ordering, then passed7 tests after the source fix. The first rendered test harness could not inspect SwiftUI accessibility elements in process; that is not product regression evidence. Replacing that harness with screenshot text recognition produced3 valid failures on missing export, premature100percent, and missing handoff controls. All3 then passed after SignView changed. Screenshot checks establish visible text, not VoiceOver or tappability.

Full package run:850 executed,18 skipped,0 failures. Development app-model run:131 passed,0 failed,0 skipped, including5 real rendered-screen cases. Normal Release and Dev builds passed. The normal Debug model bundle cannot compile an existing Dev-only IdentityTester reference in OTASessionOutcomeTests; no test configuration was changed to hide it. Normal Release navigation checks are recorded separately.

Independent source review approves the bounded fixes with no blocker. Free review plan had0 successful responses (timeouts and Zen quota exhaustion); full panel had0/3 and stopped when the free-only policy refused a model route. No paid fallback, retries after policy stop, guard changes or review exception. Three-model review remains open.

The pre-existing cross-run stale handoff/error issue and the saved-list race remain outside this patch. The owner's excluded saved-file URL proposal remains separate. No phone access, merge or publication.

Reproduction commands, from this worktree:

```sh
swift test --scratch-path /tmp/wax-sign-flow-repairs-package --filter SignStageTests
swift test --scratch-path /tmp/wax-sign-flow-repairs-package
mobilebuildmcp simulator test --json '{"projectPath":"LocalIPASigner.xcodeproj","scheme":"WaxModelTests","configuration":"Development","simulatorId":"60A427CE-1AD1-42E7-A439-62B4738D49AC","derivedDataPath":"/tmp/wax-sign-flow-repairs-build","extraArgs":["-parallel-testing-enabled","NO"]}'
mobilebuildmcp simulator build --project-path LocalIPASigner.xcodeproj --scheme LocalIPASigner --configuration Release --simulator-id 60A427CE-1AD1-42E7-A439-62B4738D49AC --derived-data-path /tmp/wax-sign-flow-repairs-build
mobilebuildmcp simulator build --project-path LocalIPASigner.xcodeproj --scheme WaxDev --configuration Development --simulator-id 60A427CE-1AD1-42E7-A439-62B4738D49AC --derived-data-path /tmp/wax-sign-flow-repairs-build
```


Normal Release UI:3 passed,0 failed (direct host setup, largest-text bottom options, public navigation). Screenshots confirm the export action and retry text remain visible; a separate slow-host screenshot shows50percent with upload incomplete. These are simulator observations. No frame-rate, VoiceOver, physical installation or real certificate-feed claim. Hygiene check identified0MB eligible cleanup; nothing deleted.

Final focused rerun after test cleanup:5 passed,0 failed,0 skipped. Evidence: `wax-sign-flow-presentation-final-20261109.log`. The cleanup releases suspended fake hosts if rendering throws; production source did not change. All scoped fixes remain local pending integration and outstanding review gates.
