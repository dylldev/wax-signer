# Simple signing flow implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this approved scope task by task.

**Goal:** Make ordinary signing continuous, setup destinations direct, and developer diagnostics opt-in within Settings.

**Architecture:** Retain immutable preparation, credential validation and signed-output checks. Default SigningModel.sign to continuous prepare/sign; expose explicit review only through Settings Developer. Reuse the Settings navigation stack for install setup. Smooth the existing wax animation rather than replacing the signing engine.

**Tech stack:** Existing SwiftUI, Swift, XCTest and shell/Python build tooling. No dependencies.

**Spec:** User-approved bounded chat scope on November7: automatic checks, no normal Passport, Developer controls in Settings, exact setup routes, shorter copy, smoother progress with Reduce Motion. Built-in public feed was separately requested. No publishing, app deletion or new phone operation in this pass.

## Global constraints
- Preserve certificates, profiles, saved IPAs and custom feeds.
- Keep normal/Dev identity and probe separation.
- Keep TLS, DNS-loopback, profile, credential, cancellation and output-integrity checks.
- Do not advertise an install prompt as installation success.
- Preserve the raw largest-text AX5 failure; do not filter it.

## Review focus
- A blocked or expired preparation must never publish or install.
- Cancellation and changed inputs must discard stale results throughout the continuous job.
- A background expiration must cover preparation and signing, not only a second tap.
- An explicit no-feed build must stay empty despite project defaults.
- Hidden tabs and reduced-motion/background animation must stay idle.

### Task1: Built-in feed
**Files:** project.yml, scripts/build-release-ipa.sh, scripts/test_build_channels.py, README.md, SECURITY.md, Sources/InstallKit/CertificateFeed.swift, CHANGELOG.md.
- [x] Add failing tests for inherited normal/Dev defaults and unspecified-versus-empty shell overrides.
- [x] Include existing public URL/domain through build settings; preserve explicit custom/empty overrides and chain checking.
- [x] Run nine channel and36Source tests; expected zero failures.
- [ ] Inspect actual built normal/Dev Info.plists and resource boundaries.

### Task2: Continuous signing
**Files:** App/SigningModel.swift, Tests/SigningKitTests/SigningModelTests.swift.
**Interface:** sign(standalone: Bool = true, compression: SigningCompression.Flags? = nil, backgroundID: UUID? = nil, cancellation: SigningCancellation? = nil, reviewBeforeSigning: Bool = false) -> Task<Void,Never>?
- [ ] Add testOneTapSigningProducesVerifiedSavedOutput asserting one sign call yields a report, empty check failures and a saved entry; no Passport pause. Add a cancelled automatic-run regression.
- [ ] Run PassportTests selected SigningModelTests and confirm new automatic case fails before changing production behavior.
- [ ] Make the fresh prepared transaction continue into signing unless reviewBeforeSigning is true. Start standalone background ownership for automatic preparation/signing; keep stale-run/input/cancellation checks and failed transaction cleanup.
- [ ] Remove the first-tap preparation branch from signAndInstall so the existing reserved installation transaction owns the entire job. Keep explicit review tests by passing reviewBeforeSigning:true to their preparation calls.
- [ ] Run the full PassportTests scheme, including background-expiration and changed-input regressions.

### Task3: Exact setup routes
**Files:** App/LocalIPASignerApp.swift, App/SettingsView.swift, App/SignView.swift, Tests/AppModelTests/RouterTests.swift, Tests/UITests/WaxUITests.swift.
**Interface:** Router.SettingsRoute.installHost and Router.openInstallHost(); reuse InstallSection in a pushed Install host screen.
- [ ] Add router assertions for settingsPath == [.installHost] and tab == .settings. Confirm missing interface fails compilation.
- [ ] Route the install-host summary row and missing-host primary action to openInstallHost(). Preserve credentials direct route. Audit remaining generic Settings links.
- [ ] Add a normal UI case that taps the host row and verifies Install host contents without a second Settings tap.
- [ ] Run model and selected navigation UI cases, including back/reselection behavior.

### Task4: Settings-only developer tools and concise UI
**Files:** App/DeveloperSettingsView.swift, App/SettingsView.swift, App/SignView.swift, App/SigningOptionsView.swift, App/CredentialsView.swift.
**Interfaces:** SigningOptionsView(model:showDeveloperTools:) and CredentialsView(showDeveloperTools:), both false by default; only the Developer settings subtree opts in.
- [ ] Remove the normal Passport card, review announcements and Continue labels; retain actionable error and warning text. Move plan inspection to a Development-only DeveloperSettingsView with Prepare preview calling sign(reviewBeforeSigning:true).
- [ ] Place import logs, certificate probes, raw entitlements/plist editing and preview inspection under Settings → Developer. Normal credentials and common app-edit screens never opt in.
- [ ] Remove routine helper paragraphs under obvious actions; keep missing-setup, failure, privacy/trust and meaningful destructive/rename explanations.
- [ ] Verify normal UI lacks Passport/Developer/probe entries and Dev common flow matches normal. Verify Developer tools remain reachable through Settings.

### Task5: Smooth branded progress
**Files:** App/WaxMelt.swift, App/SignView.swift, relevant UI fixtures.
- [ ] Reproduce the discrete progress jumps using the Dev melt preview; capture baseline.
- [ ] Use an animatable progress renderer inside the existing Canvas/timeline, with short eased interpolation and display-paced flame/drips. Keep displayed values tied to real progress. Pause hidden/inactive/reduced-motion timelines.
- [ ] Inspect simulator recordings with coarse progress jumps, Reduce Motion, rotation and large text. Measure frame cadence rather than claiming device performance from source.

### Task6: Final verification and review
- [ ] Run package tests, model/Passport suites, build-channel/Source checks and both generic device builds. Run meaningful UI cases and retain raw AX5 results separately.
- [ ] Require three distinct free reviewers for the changed signing transaction and trust-default decision. Inspect each finding against actual code and tests. No paid fallback.
- [ ] Run graphify update once after source changes; inspect diff/privacy. Preserve original worktrees and all unrelated files.
- [ ] Produce local unsigned0.17.1/build110 artifacts in iCloud root with checksums after verification; do not publish or merge without separate authorization.

## Execution ledger, November8

Ruling: keep the immutable engine preflight and signed-output checks, while making normal calls continuous. Explicit review stays in Developer Settings. This removes the extra tap without weakening cryptographic validation.

Ruling: use a cancellation handler around the detached worker to cancel its cooperative operation token. Do not replace the installation owner's background-expiration callback. Automatic preparation and signing share that owner's reservation.

Ruling: treat a stored blank feed as missing setup and use the bundled default. Keep nonblank custom addresses and explicit no-feed build behavior. No saved preferences are rewritten. The initial version of the build-script change hit Bash3 empty-array behavior; the settings array now always contains CODE_SIGNING_ALLOWED=NO.

Ruling: add an explicit missing-profile state so a selected certificate without any profile routes to import. Already-signed inputs without a selected certificate retain their install route.

Ruling: move the existing Dev animation demo into Settings and add a preview slider. Canvas now interpolates real progress and targets60Hz; pause/Reduce Motion guards remain. Keep signing progress visible through the signing-to-delivery handoff. The screenshots verify geometry changes and centering, not exact slider positions or physical frame rate. Native video has non-monotonic timestamps and is unsuitable for performance claims.

Verification: feed/channel9, Source36, probe6, CertificateFeed23 and full package847executed/18skipped/829passed. App-model119passed. Full hosted signing278passed/3skipped; final SigningModel14passed, including automatic expiry, stale-result rejection and one-action delivery to an injected host. Four normal UI cases passed; direct-host regression failed with old Settings-only actions and passed after restoration. Dev-only Settings navigation and animation preview passed. Raw largest-text accessibility audit still fails Contrast failed and remains unfiltered. A keyboard test stalled in UIKit text selection then passed; no speculative product patch was applied.

Review: two distinct free advisers completed; another timed out and the remaining allowed providers reported quota exhaustion. This is not full quorum approval. The final blank-feed and missing-profile refinements have direct regression tests and executor review but no third independent model review. Publishing/merging remains blocked; no paid fallback.

Remaining evidence: exact new artifacts need physical signing/install/launch/update testing and device animation assessment. The existing physical Wax Test0.17.0 remains untouched. Build a local metadata-only update variant for that verified test identity to avoid creating another phone copy. No release, public push, tag, deployment or phone operation is part of this pass.

Before running the Dev UI case, install/build WaxDev on the same simulator (the app-model suite does this). Normal-only UI runs can select the normal cases. Private results: ~/.codex/artifacts/wax-release-20261107/simple-flow-*.
