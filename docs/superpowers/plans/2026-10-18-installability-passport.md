# Wax Installability Passport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an evidence-backed, local preflight report before signing, while reusing the same prepared IPA worktree so the report does not force Wax to unpack the IPA twice.

**Architecture:** Split the current `IPASigner.sign` flow into preparation and signing phases. Preparation inspects and extracts into a private temporary worktree, applies requested edits only there, then calls the existing `BundleSigner` read-only preflight and planning logic to produce a report. The user reviews the report; continuing signs and packs that same prepared worktree, while canceling or changing inputs discards it. The report labels facts as pass, warning, blocked, or unknown and never claims Apple's final install decision.

**Tech Stack:** Swift, SwiftUI, Foundation, existing IPAKit/CredentialKit/SigningKit APIs, XCTest fixtures.

---

## Scope and files

- Modify `Sources/SigningKit/BundleSigner.swift`: expose the existing read-only preflight/planning result through a prepared plan, without performing signature writes during preparation.
- Modify `Sources/SigningKit/IPASigner.swift`: split extraction/edit/planning from signing/self-check/packing; own and clean up the temporary worktree on cancel, failure, or completion.
- Modify `App/SigningModel.swift`: snapshot selected identity, profiles, bundle-ID settings, entitlements and edits; prepare once; invalidate prepared work when any input changes; continue or cancel safely.
- Modify `App/SignView.swift`: show the concise Passport in the Sign flow before continuing, with expandable evidence and plain language about unknown checks.
- Modify `Tests/SigningKitTests/ProfileSelectionTests.swift` and `Tests/SigningKitTests/IPASignerTests.swift`: cover report evidence and preparation immutability/reuse with existing fixtures.
- Modify `Tests/InstallKitTests/SignScreenLogicTests.swift` only if the existing presentation-state helpers are extended; do not create a new UI framework or module.

## Task 1: Preserve the signing engine's read-only plan as an explicit result

**Files:**
- Modify: `Sources/SigningKit/BundleSigner.swift`
- Test: `Tests/SigningKitTests/ProfileSelectionTests.swift`

- [ ] Add a public, `Equatable` preflight row/result model in `SigningKit` with only the four statuses `pass`, `warning`, `blocked`, and `unknown`. Each row stores a short title, explanation, and evidence text; no opaque numeric score.
- [ ] Extract the common `Context` setup, `preflight()`, and `plan()` invocation so both normal signing and preparation use exactly the same eligibility and profile-selection code.
- [ ] Return profile selections, rejected-profile reasons, bundle-ID changes, requested and unmet entitlement keys, and profile signature status from the read-only plan. If no profile can be selected, return a `blocked` finding with the existing rejection reasons instead of losing them in a thrown error. Keep `signBundle` and every file-writing operation out of this API.
- [ ] Add fixture-backed cases proving an eligible profile is reported as selected, an expired/unlisted/mismatched profile yields a blocked finding, and ungranted requested entitlements are disclosed.
- [ ] Run `swift test --filter ProfileSelectionTests` and confirm all focused cases pass.

## Task 2: Prepare an IPA once, then continue or discard it

**Files:**
- Modify: `Sources/SigningKit/IPASigner.swift`
- Test: `Tests/SigningKitTests/IPASignerTests.swift`

- [ ] Introduce a prepared-signing handle that owns a unique temporary directory, extracted app tree, immutable input/settings snapshot, preflight result, and input metadata. Its cleanup must be idempotent and run on cancel, failure, and after successful packing.
- [ ] Implement `IPASigner.prepare(...)` to run `IPAInspector.inspect`, `IPAExtractor.extract`, `AppEditor.applyDetailed`, and the read-only `BundleSigner` plan in the temporary tree. It must not modify the source IPA or write a signed output. A blocked report is still reviewable but cannot continue to signing.
- [ ] Refactor the current `IPASigner.sign(...)` implementation to use the same preparation and continuation path immediately, preserving its existing public behavior and progress stages for current callers.
- [ ] Implement continuation to sign the already-prepared tree, run the existing `SignatureVerifier` self-check, and pack to the requested output. Do not repeat extraction or edits after the user accepts the Passport.
- [ ] Add tests showing source IPA bytes are unchanged after prepare, prepared output signs successfully, cancel removes the temporary tree, and a failed prepare does not leave a partial worktree. On startup, remove only stale directories under Wax's dedicated preparation prefix; never sweep shared temporary storage.
- [ ] Run `swift test --filter IPASignerTests` and confirm the focused cases pass.

## Task 3: Connect the prepared run to Sign state

**Files:**
- Modify: `App/SigningModel.swift`

- [ ] Build the same candidate `ProfileSet`, `SigningOptions`, and `AppEdits` snapshot that the current `sign` method builds; pass those exact values into `IPASigner.prepare`.
- [ ] Publish the resulting Passport and a “ready to continue” state only after preparation completes. Keep signing idle while the user reviews it.
- [ ] Continue the same prepared handle when the user chooses to sign; preserve current export/install behavior and only upload after the signed self-check passes.
- [ ] Discard the handle if the user cancels or changes the IPA, identity, profile, bundle-ID mode, custom entitlements, or app edits. Ensure temporary-file cleanup also runs if the screen disappears or the app is terminated.
- [ ] Keep the existing signed-input install path (no signing identity) separate; do not show signing-profile checks for an IPA Wax will not sign.

## Task 4: Present the Passport before signing

**Files:**
- Modify: `App/SignView.swift`
- Optionally modify: `Tests/InstallKitTests/SignScreenLogicTests.swift` if existing state-resolution logic changes.

- [ ] Add the Passport to the existing Sign flow without a new tab. Present a compact summary and expandable rows with the four status labels, reason, evidence, and next safe action.
- [ ] State near the summary that Wax's checks are not Apple's install decision. Show unknown UDID membership, current revocation state, and final Apple/`installd` acceptance as **Unknown**; do not infer device eligibility from a profile's device count.
- [ ] Show known minimum-iOS incompatibility only when both the IPA minimum and current iOS version can be compared reliably. Show whether the selected host is configured; keep network reachability **Unknown** unless the user explicitly runs the existing host check. A configured or reachable host is never proof of install acceptance.
- [ ] Allow continuing past warning/unknown rows after they are shown. Keep definite signer failures blocked with their existing actionable error.
- [ ] Check Dynamic Type, VoiceOver labels/order, light and dark appearance, and the Sign screen's existing accessibility announcements in the simulator.

## Task 5: Verify integration and commit

**Files:**
- Verify: all files above
- Verify: `docs/superpowers/specs/2026-10-18-wax-installability-passport-design.md`

- [ ] Run `swift test` and confirm the package suite passes.
- [ ] Build the iOS simulator app with the repository's existing scheme and capture the Sign screen in light and dark appearance.
- [ ] Inspect both captures at normal and larger text sizes; confirm warning/unknown states remain readable and the Passport does not conceal the primary action.
- [ ] Review `git diff --check` and `git diff --stat`; ensure no IPA, profile, credential, or generated signing output is tracked.
- [ ] Commit the implementation in small commits: signing plan/preparation, Sign model flow, and Passport UI. Do not publish or release from this plan.

## Explicit non-goals

- No claim that Wax can prove Apple's final installation acceptance.
- No UDID acquisition, device-list bypass, revocation bypass, certificate sharing, or cloud upload.
- No automatic entitlement removal or bundle-ID rewrite triggered merely by viewing the report.
- No new installation mechanism, telemetry, dependency, or credential service.
- Do not release 0.14.1 until the real-phone test in the project handoff is completed.

## Risk to resolve during implementation

Holding a prepared worktree across a user decision creates a temporary-storage lifecycle. The handle must be invalidated on every relevant input change and clean itself after cancel/failure/completion. If the app is terminated, the next launch must remove only Wax-owned stale preparation directories; never sweep unrelated temporary files. The performance target is one extraction per sign attempt, not a second preflight extraction.
