# Start with five bounded pull requests

This plan assigns future work. The documents contain no implementation, release approval or phone result. Pin the chosen branch before each PR. Use fixture material generated for the test. Obtain the owner's approval before physical devices, real credentials, host changes, tags, publication or rollback. For consequential security, shared-interface or release decisions, obtain the required independent panel or an explicit owner exception. On November 4 the permitted panel preflight returned a local policy error for all three configured models. No full panel approval exists.

## Keep the existing architecture

| Boundary | Early investment | Defer until evidence warrants it |
|---|---|---|
| IPAKit archives and streaming | Preserve extraction/packing budgets, CRCs, safe paths, validated output and cancellation. Expand malformed corpus and measure scratch. | ZIP64, new compression types or format replacement only with real demand. |
| SigningKit Mach-O and signature | Test supported slices, checked offsets, nested signing, resource seals and independent CMS. Profile before changing binary reads. | File-backed hashing only when representative RSS improves without signature drift. |
| Immutable signing plan | Keep captured input, frozen edits, once-only confirmation, stale-plan rejection and final verification. Improve disclosure from existing fields. | No separate rules engine or speculative graph database. |
| Credentials and profiles | Bind selected identity metadata to runtime leaf, preserve device-only storage, validate profile and show trust limits. | New account service or key algorithm needs independent approval and conformance. |
| Library and jobs | Extend journal fixtures and normal-model recovery; separate durable completion from interrupted work. Maintain compatibility with existing index/records. | Resume only a verified expensive stage. Avoid wholesale coordinator or persistence replacement. |
| Transports | Keep ownership, finite deadlines, same-origin bearer rules, private saved snapshot and export fallback. | Pairing, private CA/domain setup or a new hosted service are separate spikes. |
| Diagnostics and UI | Use normal SwiftUI and existing model boundaries. Keep Dev probe separate. Cover consent, redaction, accessibility and honest terminal outcomes. | Rich history can follow a versioned, bounded SigningRecord schema in 1.1. |
| Configuration and migration | Test legacy shelf/index, identity and bucket service separately. Version schema and make migration idempotent; recover without deleting original data. | No database rewrite or automatic cleanup of user records without demonstrated need. |

[Package.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Package.swift#L4-L30) · [PreparedIPA.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/PreparedIPA.swift#L178-L219) · [IPALibrary.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/IPALibrary.swift#L284-L417) · [BackgroundJob.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/App/BackgroundJob.swift#L27-L151)

## Prepare the local test runner

Use the repository root with Xcode, Swift, XcodeGen and Python available. Set an artifact directory and simulator destination once in the shell running the relevant task. The resolved simulator identifier stays in private logs. Use a unique, empty result path for each command. Discovery of no supported simulator is a missing prerequisite.

```sh
ARTIFACTS=$(mktemp -d)
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for r,v in d.items() if "iOS" in r for x in v if "iPhone" in x["name"]), ""))')
test -n "$SIM_ID"
```

## T01 · Record provenance and select the surface

**Prompt.** “Own the candidate provenance ledger. Compare public main, v0.16.3, source PR #33, the website draft and named local-only features. Do not merge trees. List each chosen feature, owner, source and test. Record choices in a redacted document, then verify its public baseline and list the Xcode schemes available there.”

```sh
git rev-parse HEAD
git rev-parse 'v0.16.3^{commit}'
git diff --stat v0.16.3..HEAD
git status --short --branch
git ls-remote publish refs/heads/main refs/pull/33/head
python3 scripts/test_build_channels.py
xcodegen generate
xcodebuild -list -project LocalIPASigner.xcodeproj
```

Expected evidence is an exact SHA/tag relationship, channel-contract test exit 0, scheme list and a ledger that distinguishes source, draft and private changes. If a branch advanced, record the new SHA and reassess affected claims. Inspect the dirty checkout read-only.

T01 verification and inclusion decisions are recorded in the [candidate ledger](T01-CANDIDATE-LEDGER.md). It pins the starting source, not a qualified release artifact.

## T02 · Repair standard candidate provenance

**Prompt.** “Own Source/prepare_release.py, its tests and channel-contract explanation. Make a standard-shaped synthetic IPA without Dev files and show the current reader fails. Add explicit standard/Dev channel selection independent of feed flavor. Thread it through the production prepare entry point and build call. Validate io.github.dylldev.wax for standard and io.github.dylldev.wax.dev for Dev. Exercise production prepare with actual-shaped synthetic archives for both channels and both feed flavors, including wrong-channel controls. Keep Dev probe validation, metadata and secret scanning. Revert the repair temporarily to prove the failing test, restore and rerun. Do not publish or alter a real tag.”

```sh
python3 -m unittest discover -s Source -p 'test_prepare_release.py' -v
python3 -m unittest discover -s Source -p 'test_*.py' -v
python3 scripts/test_build_channels.py
python3 -m unittest discover -s scripts -p 'test_package_probe.py' -v
```

Capture red, green, revert-red and restored-green logs. Red must expose the normal missing-probe error, the absent Dev build selection and rejection of the actual Dev ID. Green must demonstrate channel propagation, accept standard without Dev files and accept Dev only with its expected ID and matching probe metadata. Reject swapped IDs, missing/corrupt Dev probe and embedded forbidden material for both feed flavors. Schedule both real approved-tag channel builds at T12. [test_prepare_release.py](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Source/test_prepare_release.py#L26-L37)

## T03 · Bind readiness to the selected leaf

**Prompt.** “Own CredentialStore runtime lookup and the minimum readiness caller needed for parity. Inspect the existing local guard as a candidate implementation. Reproduce a selected-record/returned-leaf mismatch in a disposable fixture. Fix the shared lookup, verify matching/legacy behavior, and retain all unrelated records. Keep the historical Ad Hoc phone symptom open for T13.”

```sh
swift test --filter 'CredentialStoreTests|KeychainIdentityTests|ProfileSelectionTests'
xcodegen generate
xcodebuild test -project LocalIPASigner.xcodeproj -scheme WaxModelTests -configuration Development -destination "id=$SIM_ID" -resultBundlePath "$ARTIFACTS/T03-models.xcresult" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LocalIPASigner.xcodeproj -scheme PassportTests -configuration Development -destination "id=$SIM_ID" -resultBundlePath "$ARTIFACTS/T03-passport.xcresult" CODE_SIGNING_ALLOWED=NO
```

Record actual executed suites and any skipped Keychain scenario. Require red/green leaf mismatch, matched identity success, a non-destructive recovery path and hosted key lookup. Physical lock and actual Ad Hoc install belong to T13. [CredentialStore.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/CredentialKit/CredentialStore.swift#L70-L82)

## T04 · Reproduce the draft accessibility audit

**Prompt.** “Own the chosen PR #33 UI test target and affected normal screens. Use the draft's Release WaxUITests scheme. First reproduce its exact accessibility audit and identify the offending element and rule. Fix the demonstrated cause, run the same audit and preserve navigation, save and deletion controls. If it cannot be reproduced, keep evidence and investigate the configuration before changing layout.”

```sh
xcodegen generate
xcodebuild -list -project LocalIPASigner.xcodeproj
xcodebuild test -project LocalIPASigner.xcodeproj -scheme WaxUITests -configuration Release -destination "id=$SIM_ID" -only-testing:WaxUITests/WaxUITests/testAccessibilityAudit -resultBundlePath "$ARTIFACTS/T04-audit.xcresult" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LocalIPASigner.xcodeproj -scheme WaxUITests -configuration Release -destination "id=$SIM_ID" -resultBundlePath "$ARTIFACTS/T04-journeys.xcresult" CODE_SIGNING_ALLOWED=NO
```

Run only after selecting the draft target; it is absent on public main. Save screenshots at narrow AX5 and ordinary size plus the issue tree. Manual VoiceOver remains a distinct G6 requirement. [Draft audit](https://github.com/dylldev/wax-signer/blob/a007ee99e4ca752143187fe1fe4fc83e6213faa6/docs/audits/2026-10-29/ui/ACCESSIBILITY-AUDIT.md#L50-L52) · [Exact test](https://github.com/dylldev/wax-signer/blob/a007ee99e4ca752143187fe1fe4fc83e6213faa6/Tests/UITests/WaxUITests.swift#L129-L139)

## T05 · Align trust words with verified states

**Prompt.** “Own the credential trust message and the smallest presentation test. Build synthetic invalid-CMS, intact-untrusted, trusted and revocation-unknown examples. Show the current message conflicts with ProfileTrust. Change just the copy or presentation mapping. Preserve strict signing policy and let the UI say unknown where the engine cannot decide.”

```sh
swift test --filter 'EligibilityFindingsTests|ProfileSelectionTests'
xcodegen generate
xcodebuild test -project LocalIPASigner.xcodeproj -scheme PassportTests -configuration Development -destination "id=$SIM_ID" -resultBundlePath "$ARTIFACTS/T05-trust.xcresult" CODE_SIGNING_ALLOWED=NO
```

The new presentation test must run in an enabled test target and assert each disposition. Inspect the xcresult to ensure the added test executed. A green existing package suite alone cannot verify changed UI text. [CredentialsView.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/App/CredentialsView.swift#L59) · [ProfileTrust.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/CredentialKit/ProfileTrust.swift#L5-L24)

## Spend physical test time where software checks end

Per PR, run targeted unit and fault tests on authorized synthetic fixtures and capture failing controls. On integration, run full `swift test`, server/source/script suites, both unsigned configurations and both hosted schemes using the repository CI commands. Run an independent review of changed code and sensitive callers. Record suite counts, skips, code SHA, fixture hash, tool versions, exit status and actual artifact digest. Do not infer independent CMS trust or an app launch from a test name.

At RC, exercise final-archive independent checks, malformed crypto, controlled network faults, normal UI with large text/VoiceOver and the [two-device install, continuity and performance matrix](RELEASE-READINESS.md). Reuse synthetic inputs and compatible device slots across tasks. Keep one optional real-input test explicitly skipped if no authorized file is supplied, and generate owned fixtures for mandatory scenarios. Save versioned private raw logs, traces and xcresults under an immutable candidate identifier, publish a small redacted manifest and candidate-level failure list. Keep rerun evidence when the digest changes. CI's seven-day retention is too short to substitute for a release archive. [CI recipe](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/.github/workflows/ci.yml#L15-L50)
