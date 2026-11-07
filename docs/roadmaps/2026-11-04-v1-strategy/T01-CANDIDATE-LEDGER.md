# T01: pin the starting point before selecting fixes

Recorded November 5, 2026. This ledger selects the starting source and stabilization scope for the recommended roadmap. It does not freeze a release artifact, qualify a device, approve a security design, create a tag or merge a feature branch. T12 will freeze the actual candidate after the required fixes and review.

## Pinned inputs

| Input | Exact revision | Decision |
|---|---|---|
| Public source main | `62ff68b72f27e9e33987a87a48f27765369e126f` | Starting application source for T02–T05. |
| Published `v0.16.3` | `61a6aad18e6f6b49cf1ce721ce16a8b4939c7fb3` | Historical release source, not the next candidate. The tag is lightweight; do not rewrite it to satisfy the annotated-tag gate. |
| Roadmap documents before T01 | `32335d78df39f1ecdcb8a9996a74723a85f2c03e` | Documentation only, layered over public main in [draft PR35](https://github.com/dylldev/wax-signer/pull/35). |
| UI and credential draft | `a007ee99e4ca752143187fe1fe4fc83e6213faa6` | [PR33](https://github.com/dylldev/wax-signer/pull/33) remains draft. Select individual changes below; do not merge it wholesale. |
| Original local committed work | `518156f253c890bcd7fa5f83e06f984f025d4915` | Comparison input only. Do not use its private history as a public release parent. |
| Website draft | `9202ff0483dd40f222f0dc6bb5b6c26a9fbbfd07` | [Distribution PR3](https://github.com/dylldev/wax/pull/3); separate from application qualification and still unpublished. |
| Distribution main | `fef904c77ff92a6461b0ce35ab36353ddd6a91ba` | Preserve existing site/feed/artifact history. Updating the website does not qualify or release an application. |

The release source and public main differ in five files: CODEOWNERS, two workflows, README and protected-publishing instructions. No application, package or test source changed between those two revisions. Public version metadata is **0.16.3/build 108** for normal Wax and Wax Dev. WaxProbe's separate 1.0/build 1 metadata is not the product version.

The original local checkout remains on `audit/2026-10-24`. Its observed working changes comprise seven modified tracked files, eight deleted tracked fixture files and four untracked paths. Preserve them. The fixture removals predate this work; do not infer their purpose or restore them as part of T01. No dirty local file is selected automatically.

## Select changes by owner and closure evidence

“Required” means required for the stabilization scope; it does not mean the implementation is approved or already integrated. The next implementer must use a public-main-based branch and review the named input against that base.

| Slice | Decision and owner | Source to inspect | Closure evidence |
|---|---|---|---|
| Existing signing, immutable preparation, archive limits and transactional shelf | Retain the public baseline. Signing/recovery owners maintain its invariants. | Public `Sources/SigningKit`, `Sources/IPAKit`, `Sources/InstallKit`. | Existing regression suites plus final exported-output and lifecycle gates; do not replace working mechanisms. |
| Channel-correct candidate preparation | Required T02; release-tooling implementer. | Public `Source/prepare_release.py`, its tests and `scripts/build-release-ipa.sh`. | Independent standard/Dev selection and IDs; both feed flavors; production-entry synthetic cases; normal excludes probe, Dev validates it. Real builds remain T12. |
| Runtime certificate/readiness parity | Required T03; credential implementer. Prefer the public draft as the inspectable input. | PR33 `CredentialStore.swift`, `Models.swift`, readiness callers and corresponding Keychain/model tests. Compare the local guard without copying unrelated files. | Wrong-leaf failure, matched-leaf success, legacy-record handling and hosted Keychain checks; no credential deletion. Do not attribute the older Ad Hoc failure to this gap without proof. |
| Dynamic Type, truthful save feedback and safe deletion | Required T04 for the selected normal UI; UI implementer. | PR33 `SignView`, `Theme`, relevant `SigningModel`/row changes and `WaxUITests` target. | Reproduce the draft failure on the selected base, identify the cause, then run normal Release accessibility/navigation/save/delete checks. PR33 CI success does not close the separately reported AX failure. |
| Profile trust explanations | Required T05; credential UI implementer after T03. | Public `CredentialsView.swift` and actual profile-verification findings; inspect PR33 copy changes. | Integrity, chain trust and unknown revocation stay distinct in fixture-backed tests. No installation guarantee. |
| First-run guide, notification flow, shake/report preview and compression choices | Preserve as deferred input for 0.18, not a bulk 0.17 merge. Separate UX owners after shared-model review. | Named PR33 additions and the original uncommitted report/notification changes. | Reconcile overlapping versions, consent/redaction tests, normal/Dev behavior and measured compression choices. Their existence locally is not release evidence. |
| Source artwork, richer receipts and new formats/transports | Outside the initial stabilization cut. Milestone owners use the ranked backlog. | [Innovation register](INNOVATION-LAB.md). | Separate feature or feasibility PR after its dependencies; never enlarge T02–T05 to include it. |
| Website release awareness | Separate distribution owner. Keep PR3 independent. | Its pinned head above. | Seven Node and five Python tests, browser failure-path checks and separate publishing approval. It does not update `apps.json` or prove feed validity. |

No slice is cherry-picked in this task. Before applying a slice, compare the exact source SHA, files and tests; keep only that task's changes and record the resulting commit in its PR.

## Adopt the narrow candidate contract

For the first stabilization train, use **0.17.x** as a proposed milestone name only. Do not bump metadata, create an RC tag or publish an asset in T01.

- Normal Wax remains the everyday application; probes, raw technical controls and diagnostic test apps stay in Wax Dev. The two identities remain `io.github.dylldev.wax` and `io.github.dylldev.wax.dev`.
- Qualify authorized, unencrypted classic-ZIP IPAs with supported arm64 device slices, a user-owned RSA identity and a matching profile. Development/Ad Hoc claims depend on exact physical tuples. Enterprise credentials, additional crypto algorithms, new archive formats and arbitrary injected-code compatibility are outside the initial stable promise.
- The core journeys are sign and retain/export, retry delivery from the same retained bytes, and renew/update with identity warnings. Never infer installation or launch from upload completion.
- Signed-file export is the baseline fallback. A tested user-owned HTTPS route is the proposed supported installation path. Shared-key loopback and bucket stay explicitly experimental. No new infrastructure or certificate policy is activated by this selection.
- iOS 17 is the deployment target, not evidence that every iOS 17+ device works. Final supported device/OS/credential/host combinations remain undecided until G2. Require the two-device qualification in [release readiness](RELEASE-READINESS.md), or narrow the supported claim.
- All eight gates must pass on the eventual candidate. Current evidence remains 6/16; the roadmap and this ledger do not authorize a release or substitute for full required review.

The release owner chooses and approves a new annotated candidate tag only after the selected source is reviewed. Record that tag's object SHA, source commit and actual artifact digests at T12. Never relabel the lightweight historical tag or mix the two configuration dimensions: application channel and installation-feed flavor.

## Reproduce the T01 checks

Run from a clean public-main-based checkout with these source objects available:

```sh
git rev-parse HEAD
git rev-parse 'v0.16.3^{commit}'
git cat-file -t refs/tags/v0.16.3
git diff --stat 'v0.16.3^{commit}'..62ff68b72f27e9e33987a87a48f27765369e126f
git ls-remote publish refs/heads/main refs/pull/33/head
python3 scripts/test_build_channels.py
xcodegen generate
xcodebuild -list -json -project LocalIPASigner.xcodeproj
```

Fresh results: six build-channel tests passed. XcodeGen succeeded and Xcode listed Debug, Release and Development configurations. Application/test schemes include `LocalIPASigner`, `WaxDev`, `PassportTests`, `WaxModelTests`, `CredentialAppTests`, `IdentityProbe`, `WaxProbe` and the package schemes. **`WaxUITests` is absent on public main**; T04 must deliberately bring and review that draft target before invoking it. Scheme enumeration is not a build or a device test. The generated project is ignored; no tracked project settings changed.

If a pinned branch advances, compare the changed files and reassess only affected decisions. If a source or required scheme is unavailable, stop that task and record the missing input rather than silently substituting local work.

## Handoff to T02

T01's source comparison, owner map, exclusions, support boundary and scheme checks are complete. No release artifact is frozen. Start T02 from the pinned public application source, carrying this ledger as its decision record. Keep the future code PR focused on channel-correct candidate tooling and its tests. T03 and T04 may proceed independently after the same baseline is pinned; T05 follows T03. Publication and full security/release review stay separate.
