# Wax and Wax Dev Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this approved scope inline.

**Goal:** Ship a simple Wax build and retain downloadable diagnostic tools in Wax Dev.
**Architecture:** Keep one app target and signing engine. Add a Development configuration and WaxDev scheme with a separate bundle ID and WAX_DEVELOPMENT compilation flag. Release and Debug exclude diagnostic UI and probe resources.
**Tech Stack:** SwiftUI, XcodeGen, Python unittest, Bash.
**Spec:** Dylan approved the chat description on 2026-10-27: normal Wax keeps import, sign, install, saved apps and sources with optional edits tucked away; Wax Dev keeps probes, logs and technical controls as a separate app. Publication requires separate approval.

## Global constraints
- Preserve existing dirty edits, signing checks, stored credentials and the normal bundle ID.
- No phone changes, paid reviews, push or release in this task.
- Keep normal compression defaults; hide tuning controls in normal Wax.
- Developer configuration uses io.github.dylldev.wax.dev and display name Wax Dev.

## Review focus
- Normal app artifacts must contain neither WaxProbe.ipa nor probe-build.json, including after a dev build into the same output directory.
- Normal settings must expose no probe action, import log, compression tuning or raw entitlement/plist editor.
- Developer IPA must retain the source-built probe, developer actions and unique app identity.
- Existing app tests that exercise IdentityTester must run against the developer configuration.
- Invalid build channel must fail before compiling or writing an IPA.

### Task 1: Build channel boundary
Files: project.yml, scripts/build-release-ipa.sh, scripts/test_build_channels.py.
- [x] Add runnable tests that execute the resolved probe packaging build phase for normal/dev channels, including stale output cleanup, and exercise the release script's channel rejection.
- [x] Run `python3 -m unittest discover -s scripts -p test_build_channels.py -v`; observe failure on existing unconditional probe packaging.
- [x] Add Development release configuration, WaxDev scheme, conditional probe packaging, separate identity, and `build-release-ipa.sh <outdir> [standard|dev]` with distinct filenames.
- [x] Re-run the channel tests and existing probe packaging tests.

### Task 2: Simple normal UI
Files: App/LocalIPASignerApp.swift, IdentityReadiness.swift, CredentialsView.swift, SettingsView.swift, SignView.swift, SigningOptionsView.swift, DocumentPicker.swift.
- [x] Compile IdentityTester and its environment object only with WAX_DEVELOPMENT; preserve static identity compatibility checks in both variants.
- [x] Hide test actions/results, logs, SHA-1 metadata, compression tuning and raw entitlement/plist controls from normal Wax. Keep ordinary signing options behind the existing Options screen.
- [x] Keep technical options in Wax Dev; move less common normal app edits into a collapsed More options group.
- [x] Build both configurations; inspect built resources, display names, IDs and compiled diagnostic strings. Run app model tests against Development and package tests.

### Task 3: Download instructions and verification
Files: README.md, .github/workflows/ci.yml.
- [x] Document standard/default and optional developer filenames and local build commands; explain separate signing imports.
- [x] Make CI compile Release plus Development and run hosted tests against Development.
- [x] Request one independent review of this task's diff; inspect findings and verify any correction.
- [x] Record exact test/build results and remaining device/publication boundary in local artifacts and vault.
