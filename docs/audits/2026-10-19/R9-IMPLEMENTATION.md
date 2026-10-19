# R9 — Responsive, retryable credential imports

Stacked on R3 `469a10efaece5d00e48201741fc1433e983cc928`; PR targets `codex/r3-durable-library`. R1/R2 signing and final-byte integrity checks are unchanged. No signing algorithms or Keychain custody rules change.

## Confirmed defects and changes

Baseline R2 `App/CredentialsModel.swift:54–66` runs PKCS#12 crypto and persistence on MainActor and unconditionally clears encrypted pending input even after a wrong password. Profile import/deletion also perform store operations on MainActor (`:71–95`). The file read (`:112–123`) materializes unbounded Data before CredentialKit's size check and publishes stale callbacks without operation identity.

`App/CredentialsModel.swift` now retains an operation Task and generation token, confines UI state to MainActor, and performs file acquisition/bounded streaming reads, crypto, persistence and metadata snapshots on detached workers. Read caps match CredentialKit: 5 MiB P12 / 1 MiB profile. Initial length is an early rejection; actual chunk count is authoritative and changed/truncated length fails. Encrypted pending bytes stay only in bounded memory across password failures, clearing on success/cancel/dismiss/new pick. Immutable password/Data snapshots belong only to the confirmed worker; static outcome logs never dump unknown errors or passwords. A read-phase token also prevents late progress callbacks from restoring a finished/canceled busy state.

Confirmation begins a **non-cancellable credential-store commit**, explicitly guarded against replacement and competing deletion/import. Dismissal does not pretend to roll back a confirmed Keychain operation. Pre-confirmation cancellation invalidates publication; external provider acquisition may still finish under ExternalFile's timeout. Cooperative provider cancellation and general job ownership remain R8 work. No claim of secure-memory zeroization, KDF interruption, high-work-factor CPU budget or process-termination rollback is made.

`App/CredentialsView.swift` disables competing actions while busy, clears password entry on departure, offers Retry password / Discard pending import, and offers Cancel opening before confirmation. Success scrolling/announcements occur only after the importer returns an actual nonempty result. Unknown errors get a safe actionable generic message. CredentialKit's existing partial multi-identity persistence behavior is unchanged; successful outcome lists contain actual returned identities, not the original bag count.

## Regression coverage and verification

`Tests/AppModelTests/CredentialImportOutcomeTests.swift`: 11 deterministic app-model tests cover blocked off-main worker/MainActor responsiveness, no overlapping confirmed imports, repeated wrong-password retry without repicking, cancellation/dismissal, overlapping picks/stale read completion, empty outcomes/Keychain errors, actual returned identities, unknown-error/password redaction, exact/oversized/missing/nonregular reads, and off-main profile success/failure.

Local command: offline Swift6.2.3 `swiftc -frontend -parse App/CredentialsModel.swift App/CredentialsView.swift Tests/AppModelTests/CredentialImportOutcomeTests.swift` passed. Linux lacks SwiftUI/Security/UIKit/Xcode, so this is syntax checking, **not execution of app-model or crypto tests**. macOS package tests, unsigned iOS build and iOS Simulator outcome tests must pass on the final PR head; CI results will be recorded after execution. Existing modern/legacy PKCS#12/Keychain tests remain enabled.

Device gates: real Files/iCloud acquisition, high-work-factor P12 responsiveness, alert/VoiceOver lifecycle, wrong-password retry, and real Keychain entitlement failures. No physical-device results claimed. Passwords are not persisted by this model; Swift/Data automatic memory management does not guarantee immediate zeroization. Peak input memory is bounded but importer crypto allocations are not newly measured or bounded by this milestone.
