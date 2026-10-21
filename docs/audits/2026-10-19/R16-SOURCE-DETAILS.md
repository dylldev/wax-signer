# R16 — Source app details milestone

Base: merged R7 main `b4214fe592f4d391a3851cd19d2c0ea21a94c4d2`. Independent of unmerged R15 PR #29: no prepared-signing changes are copied into this branch.

`App/SourcesView.swift` previously rendered app name/version/size and Get, while parsed `SourceApp.summary` and `developer` were unused. Rows now have a distinct 44-point details action, separate from Get/Retry Save, and an adaptive scrollable details sheet. Source-reported claims are explicitly distinguished from inspected metadata of a previous committed download. It shows developer, bounded plain-text description, bundle/version/size and download hostname. URL credentials, path/query/fragment tokens are never displayed. No new requests, web views or artwork loading are introduced.

`SourceAppDetails` is a pure bounded display projection. Long strings are visibly shortened for presentation; raw source metadata is untouched. `SourcesModel.savedEntry` uses the existing exact source/download-key → committed entry UUID association. It never guesses identity from name, version, bundle ID or size. Missing/deleted entries disappear from the comparison. Actual saved name/version/build/bundle/size/SHA-256 are shown, and differing bundle/version/size claims are highlighted without claiming malware or installation verification. Existing R3 save/failure/retry/notification logic is reused unchanged.

Six deterministic app-model tests cover displayed fields, URL secret redaction, Unicode display bounds, actual-versus-advertised differences, unknown metadata and exact committed-key association/removal with a real IPA fixture. New UI has no fixed text height; VoiceOver labels/hints, selectable text and large sheet support Dynamic Type. Manual VoiceOver/device review remains unperformed.

This is a partial original R16 milestone. Bounded remote artwork, optional suppression, localization, broader accessibility and other source browsing improvements remain unfinished. Existing AsyncImage behavior is not changed or represented as resource-safe by this patch.

Verification: changed Swift files will receive syntax checking locally; full package/build/Simulator verification must pass on the exact PR head in macOS CI. No physical installation/launch or visual-device test is claimed. Costs are a small display projection only when opening details and an in-memory saved-entry lookup; no file hashing/inspection or network I/O runs in the view.


PR: [#30](https://github.com/dylldev/wax-signer/pull/30). Initial source head `748fe39688dd32c83274eb1fb00e8f6516f0e77c`, [CI 39507380067](https://github.com/dylldev/wax-signer/actions/runs/39507380067) running at this checkpoint; later heads must receive their own CI. Final exact-head results are recorded in the PR after execution, not inferred from source-level inspection.

Non-destructive integration assessment against R15 head `c6a7bcb85452a503537a1afcee19aebcfa93defa`: no production/test/config paths overlap. `git merge-tree --write-tree` reports only the two current headers of `MASTER-ROADMAP-EXECUTION.md` conflicting. Preserve both R15 and R16 milestone/evidence records in an ordinary forward resolution. Recommended eventual review/merge order: #29, then #30 retargeted/refreshed on actual merged main with combined app-model and signing regressions plus full macOS CI. Neither feature PR is authorized for automatic merge. No branch/index/worktree or main was modified by the merge-tree assessment.

The details presentation is dismissed when routing away from Sources, including successful Download → Sign routing; it cannot cover the destination signing screen. Save failures keep the sheet and existing Retry Save action available.
