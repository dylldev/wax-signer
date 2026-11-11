# Credential import and signing recovery implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement each task and its checks.

**Goal:** Present one credential import sheet, readable fields, and a specific recovery for an extension that a profile cannot sign.

**Architecture:** Retain existing Keychain import, identity checks, immutable signing preparation and output verification. Keep nicknames in separate non-secret app preferences rather than changing the credential index. Extend the existing signing error presentation with an explicit output-only extension-removal action.

**Tech Stack:** SwiftUI, XCTest, existing CredentialKit/SigningKit, MobileBuildMCP.

**Spec:** User-approved scope in this chat on 2026-11-08: specific errors in normal Wax; .P12 Certificate, Mobile Provision, Certificate Password, Custom Nickname, Done, top-right X; temporary passwords; retained existing credentials; readable and aligned fields; local simulator verification only.

## Constraints and review focus

- No publication, phone access, credential deletion, weaker validation or silent extension removal.
- Cancellation clears transient password/file selections without deleting existing signing data.
- A partial import failure must state what succeeded; do not claim atomic rollback.
- Nicknames survive reload, remain distinct per identity, and never replace certificate trust metadata.
- Large text, long filenames and keyboard presentation must preserve usable fields and dismissal.
- Normal Sign never presents a Passport card. Retain automatic checks and show the underlying error.

## Task 1: Combined import sheet and nickname

Files: App/CredentialsView.swift, App/CredentialsModel.swift, new App/CredentialImportSheet.swift if needed, Tests/AppModelTests/CredentialImportOutcomeTests.swift, Tests/UITests/WaxUITests.swift (credential-sheet tests only).

Interface: add `func displayName(for certificate: CertificateInfo) -> String` to CredentialsModel, falling back to the existing organization/common name; persist only nickname metadata. Existing import APIs retain their behavior.

- [ ] Add failing model tests for combined import success, password failure, partial profile failure, dismissal and persistent nickname using isolated test preferences and synthetic credentials.
- [ ] Run WaxModelTests and confirm intended failures before production edits.
- [x] Implement the smallest model operation that reuses current bounded file loading/import logic. Clear secrets on completion/dismissal. Disable repeated Done during commit.
- [x] Replace separate normal import entry points/password alert with one scrollable native sheet, ordered fields and Done plus accessible top-right Close button. Preserve standalone profile management if needed for existing identities.
- [ ] Add and run simulator sheet navigation, dismissal, keyboard and largest-text checks. Screenshot long filenames and equal field insets.

## Task 2: Specific extension recovery

Files: App/SigningModel.swift, App/SignView.swift, Tests/SigningKitTests/SigningModelTests.swift.

Interface: app-local recovery state derived from the typed SigningError; `removeUnsupportedExtensions()` changes only the output-edit option, invalidates old prepared results, and requires another explicit Sign action.

- [ ] Add a failing test with an explicit main-app-only profile and an IPA containing an extension; assert the specific error and offered recovery, with no output written.
- [x] Implement typed recovery only for extension identifier/profile rejection. Certificate expiry, malformed input and main-app identifier failures must not receive this action.
- [x] Show the underlying error and an explicit Remove app extensions action with a brief consequence statement. Keep the original IPA intact and never auto-retry.
- [x] Verify recovery clears stale error/preparation, enables removeExtensions, and subsequent signing follows existing validation.
- [x] Use CredentialsModel.displayName(for:) in Sign summaries and identity choices after Task 1 integrates.

## Task 3: Readable fields and integration

Files: App/SigningOptionsView.swift, App/InstallSection.swift only where observed layout requires changes; Tests/UITests/WaxUITests.swift (non-credential checks).

- [x] Reproduce narrow fixed-width input labels in simulator and add a targeted layout test before the fix.
- [x] Use consistent stacked label/input layouts at large text and sufficient input width; preserve accessibility labels, secure fields and existing values.
- [ ] Run fresh package tests, model tests, signing subset, targeted UI tests and both build configurations serially on the owned simulator.
- [ ] Request independent code review, attempt the configured free-only panel for credential/security changes, and record incomplete review honestly if quota remains exhausted.
- [ ] Inspect screenshots, run git diff --check and graphify update once. Preserve evidence and report exact local state; no publish.

## Verification checkpoint, 2026-11-09


The full signing subset previously recorded17 passes and one intermittent output-file failure; an isolated two-test rerun passed. A fresh serial signing-model run is being recorded in `signing-final-serial-20261109-retry.log`. The first command passed the argument array incorrectly and did not run tests. Do not call the intermittent failure resolved without a reproduced cause and verification.

Source reviews approve the bounded credential and extension-recovery changes. Full free-model review remains incomplete. No production package sources changed, so no fresh package-suite result is claimed. No phone access, publication or OpenCode worktree changes. The independently tested saved-file URL proposal remains separate pending scope approval and a one-time review exception.

Fresh credential verification: `credential-final-20261109.log` records18 passed,0 failed,0 skipped. The 2026-11-09 serial signing run records17 passed,1 failed: testASignedCopyKeepsItsRecordAndTheNextPreparationComparesWithIt could not find library.signed.first despite confirmedSaved. This remains an unresolved integration gate. Owner explicitly declined adopting the separate saved-file proposal; it remains unapplied.
