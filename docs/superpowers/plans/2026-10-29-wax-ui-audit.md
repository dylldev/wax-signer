# Wax UI audit implementation plan

> **For agentic workers:** Use the existing parallel source-audit workers for independent fixes; the root agent owns simulator execution and final integration.

**Goal:** Audit the rendered Wax interface and fix confirmed low-risk defects while preserving the existing identity and signing behavior.

**Architecture:** Keep the existing four tabs and shared visual components. Derive status from existing model state. Keep signing engines, credentials and persistence unchanged.

**Tech Stack:** SwiftUI, XCTest, Swift Package Manager, XcodeGen, MobileBuildMCP.

**Spec:** `docs/audits/2026-10-29/ui/SCOPE.md`; the user explicitly authorizes immediate investigation, Tier 1 fixes, isolated implementation and a review PR.

## Global constraints

- iOS deployment target remains 17.0; add no dependencies or paid services.
- Preserve the original dirty checkout and signing/recovery behavior.
- Use `codex/wax-ui-audit-improvements` in the isolated worktree.
- Keep probes and diagnostics out of normal Wax.
- Do not publish releases, merge, upload private IPAs or change real credentials.

## Review focus

- A failed shelf save must preserve export and expose retry without claiming success.
- Accessibility text must retain tab names and avoid fixed-height status clipping.
- Reduce Motion must suppress shared press scale and spring effects.
- Hidden/background signing views must stop decorative timeline updates.
- Before/after screenshots must identify device, appearance and text size; unobserved states stay unverified.

## Task 1: Establish baseline and render reachable screens

Files: `project.yml`, `Tests/UITests/WaxUITests.swift`, audit artifacts outside Git.

- [ ] Run `swift test` in the isolated checkout; retain full output and counts.
- [ ] Add a dedicated Release `WaxUITests` scheme without changing existing test targets.
- [ ] Run `mobilebuildmcp simulator test --scheme WaxUITests --configuration Release --simulator-id BCE070AC-FF9A-4F02-A3ED-5D11196E6017` against `testNavigationAndReportPreview`.
- [ ] Capture Sign, Sources, IPA, Settings top/bottom, signing options, report and keyboard, tutorial, credentials. Retain XCTest screenshots as attachments.
- [ ] Run the same flow on small/large devices in light/dark with accessibility text. Record unavailable states rather than inventing evidence.

## Task 2: Correct shelf-save status

Files: `App/SignView.swift`, targeted regression script and existing model/library tests.

- [ ] Add a failing regression requiring `signedShelfLink` to branch on `model.shelfSaveState`.
- [ ] In the existing `@ViewBuilder` rendering, show saved navigation only for `.saved`, saving feedback for `.saving`, and retry invoking `retrySignedSave()` for `.failed`.
- [ ] Keep retained export outside the shelf-success branch.
- [ ] Run regression red, green, exact reversion red, restoration green. Run existing persistence/recovery tests.

## Task 3: Adapt shared controls

Files: `App/Theme.swift`, `App/WaxTabBar.swift`, dedicated UI policy regression script.

- [ ] Require Reduce Motion gating for primary/tab press scale and animation; verify test fails on baseline.
- [ ] Read `accessibilityReduceMotion` in both styles and use scale 1 with nil animation when enabled.
- [ ] Change status pill height26 to minimum height26; retain tab names at accessibility sizes with wrapping.
- [ ] Run regression red/green/revert/green and render equivalent large-text captures.

## Task 4: Stop hidden signing animation

Files: the WaxMelt call in `App/SignView.swift`, focused regression script.

- [ ] Add a failing check that the call supplies `isVisible: router.tab == .sign`.
- [ ] Pass actual tab visibility to the existing WaxMelt parameter; keep its scene-phase and Reduce Motion gates.
- [ ] Verify red/green/revert/green, compile, and record measurement limits. Do not claim CPU savings without measurements.

## Task 5: Report and review

Files: ten requested audit reports under `docs/audits/2026-10-29/ui/`.

- [ ] Consolidate source findings and real captures; label confirmed defects, risks and proposals separately.
- [ ] Calculate the weighted score from the supplied weights and provide explicit confidence and evidence gaps.
- [ ] Evaluate at least25 distinct opportunities if evidence supports them; rank ten concrete proposals.
- [ ] Run package, app-model, UI, channel and permission checks; preserve failures and skip counts.
- [ ] Inspect complete diff, obtain independent review and resolve proven findings. Use free-only quorum for consequential changes; incomplete panels remain incomplete.
- [ ] Commit scoped baseline/fixes/reports, scan for secrets and publish only source and safe public artifacts to a review PR. Do not merge or release.

Self-review: tasks cover the requested audit domains and protect existing behavior. Physical shake, credentials-dependent success screens, Instruments frame pacing and full manual VoiceOver require separate evidence; they are never inferred from compilation.
