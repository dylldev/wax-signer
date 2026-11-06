# Give each change one owner

P0 blocks the critical path. P1 must close for its claimed milestone. P2 buys measured improvement. P3 funds an optional experiment. A confirmed defect, missing observation, product choice and experiment need different closure evidence. Each row is one independently reviewable task or a bounded evidence run, grouped here by dependency order. Days are hands-on estimates for an engineer familiar with Wax.

### T01 · Investigation · P0 · 0.17

Four divergent trees can contaminate a release. Record tag/main, local-only slices and PR #33 head in a sanitized candidate ledger. Adopt a narrow support contract before selecting changes. [RELEASE-CANDIDATES.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Source/RELEASE-CANDIDATES.md)

**Verify.** Compare git trees and list Xcode schemes. No production edits. **Acceptance.** Pinned base, inclusion/exclusion and owners reproducible from the ledger. **Depends on** none. **Effort** 0.5–1 d. **Risk.** Never import dirty files wholesale.

### T02 · Confirmed B01 · P0 · 0.17

Standard release preparation asks for missing probe files, always invokes the standard builder and accepts only the normal bundle ID. Add standard/Dev channel selection independent of feed flavor, pass it through the build call and validate io.github.dylldev.wax or io.github.dylldev.wax.dev for the selected channel. Extend the synthetic builder fixtures and production prepare tests. Preserve secret scanning, metadata and final hash checks. [prepare_release.py](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Source/prepare_release.py#L96-L130)

**Verify.** Source and build-channel suites, exercising production prepare with both channel IDs and both feed flavors. Build both real channels from an approved annotated tag at T12. **Acceptance.** Standard without probe passes. Dev with matching probe passes. Missing/corrupt Dev probe, swapped channel ID and missing channel propagation fail. Actual normal asset contains neither Dev file. **Depends on** T01. **Effort** 1–3 d. **Risk.** Do not weaken the Dev attestation.

### T03 · Confirmed B02 · P0 · 0.17

Runtime leaf can disagree with saved selection. Port only reviewed match/lookup semantics and bind readiness/prepare to the same identity, preserving old records. [CredentialStore.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/CredentialKit/CredentialStore.swift#L70-L82)

**Verify.** CredentialStore, KeychainIdentity, hosted SystemKeychain and app-model wrong-password tests. **Acceptance.** Swapped leaf rejected, match accepted, missing legacy metadata handled explicitly, no key deletion. **Depends on** T01. **Effort** 2–4 d. **Risk.** Guard does not establish physical Ad Hoc cause.

### T04 · Confirmed on draft B04 · P0 · 0.17

Draft AX audit failed and save/delete affordances are under review. Bring the audited draft UI test target onto a reviewed base. Fix reproduced Dynamic Type layout and verify chosen draft feedback. [SignView.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/App/SignView.swift#L328-L368)

**Verify.** Run exact WaxUITests accessibility audit plus navigation and delete controls, normal Release scheme. **Acceptance.** Audit passes at AX5, no missing or clipped action. Keep manual VoiceOver for T13. **Depends on** T01. **Effort** 1–3 d. **Risk.** Rebase before touching views shared by draft.

### T05 · Confirmed B03 · P1 · 0.17

Trust wording contradicts CMS verification. Replace one generic message with integrity, chain and revocation states consistent with actual planner. Add fixture-backed copy assertions. [CredentialsView.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/App/CredentialsView.swift#L59)

**Verify.** EligibilityFindings and ProfileSelection suites, hosted view-model checks. **Acceptance.** Invalid is blocked, valid untrusted differs from trusted and revocation remains unknown. **Depends on** T03. **Effort** 0.5–1 d. **Risk.** Never imply Apple installation approval.

### T06 · Investigation B08 · P0 · 0.18

Device recovery remains open despite shelf journal tests. Compose provider loss, low-space, duplicate bytes, cancel, termination, stale completion, save retry and export as normal-flow scenarios. Patch only reproduced defects. [IPALibrary.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/IPALibrary.swift#L284-L417)

**Verify.** LibraryTransactionTests + PreparedIPATests, then normal app model scenario. **Acceptance.** Input/previous output hashes unchanged, interruptions recover exactly once. Archive evidence per transition. **Depends on** T02,T03. **Effort** 2–4 d. **Risk.** Do not make intermediate signing state resumable by assumption.

### T07 · Product B07 · P0 · 0.18

Convenience host cannot exclusively authenticate its publicly shared identity. Lead with export. Qualify My server under valid HTTPS. Add destination disclosure and experimental host labels. Exercise isolated fault host. [InstallTransport.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/InstallTransport.swift)

**Verify.** InstallTransport, server Python suite and controlled DNS/TLS/network fault tests. **Acceptance.** No insecure fallback or bearer forwarding. Same signed output exports after failure. **Depends on** T04. **Effort** 2–4 d. **Risk.** Requires an operator for physical G2, no production host change in this task.

### T08 · Investigation B11 · P0 · 0.19/RC

One independently verified fixture is narrower than the release promise. Generate small, nested and malformed fixtures. Verify repacked final bytes with Apple codesign and detached CMS. Review changed parser/key/transport surfaces. [PreparedIPATests.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Tests/SigningKitTests/PreparedIPATests.swift#L329-L339)

**Verify.** PreparedIPATests, ParserSafetyTests, SignatureVerifierTests and corrupt controls. **Acceptance.** Verifier exits zero for each accepted sample and rejects damaged content. Findings tied to inputs and victims. **Depends on** T02,T03. **Effort** 2–4 d. **Risk.** Synthetic trust cannot prove iOS installation.

### T09 · Investigation B09 · P1 · 0.19/RC

Single historical workload lacks CPU, memory and scratch metrics. Create deterministic small/mixed/large corpus, record phase time, CPU, RSS, scratch, UI stalls and cancellation per G5. [R13-METHODOLOGY.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/docs/benchmarks/R13-METHODOLOGY.md)

**Verify.** Regenerate twice, run warm-up and five samples per mode and device. **Acceptance.** Hashes equal, raw samples and budget verdicts include actual floor hardware. **Depends on** T01. **Effort** 2–4 d. **Risk.** Simulator cannot qualify device budgets.

### T10 · Investigation B05 · P1 · 0.18

Legacy bucket service may miss accessibility migration. Create disposable legacy service items, test before and after startup, conditionally migrate same-service attributes only. [SecretStore.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/SecretStore.swift)

**Verify.** SecretStore fixtures, approved hosted Keychain and explicit lock check. **Acceptance.** Old value survives, unrelated service untouched, observed lock result or feature narrowed. **Depends on** T03. **Effort** 1–2 d. **Risk.** Keep original secrets and indexes intact.

### T11 · Product B10 · P1 · 0.18

New users need bootstrap, renewal, recovery and safe support instructions. Update normal setup, profile/host prerequisites, export fallback, permissions and support redaction. Review local onboarding separately. [README.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/README.md#L42-L57)

**Verify.** Run a blind walkthrough and deny-notification scenario, verify all links and normal/Dev separation. **Acceptance.** Reader can complete three journeys or identify a missing prerequisite unaided. **Depends on** T04,T05,T07. **Effort** 1–2 d. **Risk.** Do not promise notification delivery or untested installation.

### T12 · Investigation B01/B10 · P0 · 0.19/RC

A green build does not bind tests to the actual staged asset. Create reviewed source/export ledger, build normal and Dev locally under approved tag process. Freeze SHA, config, IPA digest and stage metadata. [RELEASE-CANDIDATES.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Source/RELEASE-CANDIDATES.md)

**Verify.** Full CI recipe, independent fixture suite and staged-feed validator. Reinspect packaged normal/Dev contents. **Acceptance.** Stable release candidate and fixture IDs recorded. No promotion or tag mutation without owner approval. **Depends on** T06,T07,T08,T09,T10,T11. **Effort** 1–2 d. **Risk.** Changing bytes reopens dependent gates.

### T13 · Investigation B06/B09 · P0 · 0.19/RC

Device journeys and final budgets have no candidate-specific proof. Run matrix with owner-provided authority and controlled host. Redact device records before publishing results. [README.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/docs/device-results/README.md#L11-L34)

**Verify.** All eight phases, wrong credentials, locked retry, continuity sentinel, AX and performance on two devices. **Acceptance.** G1–G6 reach 2 or failed combinations are excluded and remaining claims retested. **Depends on** T12. **Effort** 2–5 d + access. **Risk.** Keep device owner wait separate from engineering time.

### T14 · Release evidence B10 · P0 · 1.0

Feed, rollback and support must work on exact RC. Rehearse local stage promotion/restore, verify checksum through independently retrieved bytes after separately approved promotion. Archive redacted gate packet. [PROTECTED-PUBLISHING.md](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/docs/PROTECTED-PUBLISHING.md)

**Verify.** Validate feed/site/version, dry rollback, blind normal-app support walkthrough. **Acceptance.** All eight gates 2 and owner approval. If live verification fails, use approved rollback procedure. **Depends on** T13. **Effort** 1–2 d + approval. **Risk.** Do not overwrite prior valid release history.

### T15 · Product I13 · P1 · 1.1

A support request lacks a bounded record of observed outcomes. Extend existing record with version, digest and observed stage, read old records unchanged. [SigningRecord.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/SigningRecord.swift)

**Verify.** Schema round-trip, stale/missing record, redaction and explicit export tests. **Acceptance.** Old/new records readable and no unobserved install or launch claim. **Depends on** T14. **Effort** 3–5 d. **Risk.** Secrets or stable identifiers entering exported history.

### T16 · Product I14/I15 · P1 · 1.1

Users cannot see which nested app loses a capability. Render per-bundle planned disposition and known consequence from frozen plan. [SigningPlan.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/SigningPlan.swift)

**Verify.** Synthetic mixed grants, AX5 and VoiceOver. **Acceptance.** Display and execution refer to same plan digest. Unsupported features remain unknown. **Depends on** T15. **Effort** 2–4 d. **Risk.** Excess detail can obscure blocked main action.

### T17 · Experimental I34 · P2 · 1.5

Large-binary RSS may dominate a representative workload. If T09 identifies binary hashing as dominant, replace one measured whole-file read with bounded windowed reads. [MachO.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/MachO.swift)

**Verify.** Hostile offsets, signature parity, interruption, same-device RSS comparison. **Acceptance.** At least 20% lower peak RSS on selected workload with no >10% median regression and same verification result, or stop. **Depends on** T09,T14. **Effort** 5–15 d. **Risk.** Extra I/O or mutable input can invalidate signatures.

### T18 · Experimental I35 · P2 · 1.5

A measured high-cost interrupted stage may deserve scoped restart. Journal one validated stage with input digest and explicit restart when unsafe. [PreparedIPA.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/PreparedIPA.swift)

**Verify.** Kill at each journal transition, tamper, low storage, old schema. **Acceptance.** No partial publish, same preserved output and measurable avoided rework or defer. **Depends on** T15. **Effort** 5–10 d. **Risk.** Resuming unsigned intermediate state adds trust boundary.

### T19 · Experimental I39 · P3 · 2.0

Shared TLS identity cannot establish an exclusive host. Design a throwaway owner-private-domain proof with consent for issuance, revocation and test-device install. [LoopbackHost.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/LoopbackHost.swift)

**Verify.** Fake CA unit cases first, approved domain and device only if prerequisites met. **Acceptance.** Go only if exclusive key custody, renewal failure recovery and device acceptance are demonstrated. **Depends on** T13,T14. **Effort** 5–10 d spike. **Risk.** CA and DNS operations require separate approval.

### T20 · Experimental I41/I42 · P3 · 2.0

Demand for unsupported formats or identities is unmeasured. Choose one of ZIP64 or ECDSA after obtaining representative authorized inputs. Investigate the smallest isolated reader or signature fixture. [ZipArchive.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/IPAKit/ZipArchive.swift)

**Verify.** Malformed corpus, independent verifier and phone for any product claim. **Acceptance.** Separate feasibility decision for each format. Stop if no corpus, demand or safe bounded implementation. **Depends on** T08,T14. **Effort** 5–10 d per spike. **Risk.** No bulk format rewrite or unconditional support promise.

## Parallel ownership and serial handoffs

After T01, separate owners can work on T02 (Source), T03 (CredentialKit/readiness), T04 (draft UI) and T09 (benchmarks). T05 waits for T03 because readiness and trust copy share the credential journey. Coordinate T04 and T05 before either edits a shared credential view. T06 owns shelf and preparation tests. T07 owns transport and its UI after T04. T08 owns independent conformance tests after T02/T03. T10 owns legacy service fixtures after T03. T11 edits user guidance after host and copy decisions.

T12 is the join and freeze point. T13 operates on that exact candidate. T14 controls release evidence and requires separate owner approval for publication. After T14, T15 may extend the record schema. T16 and T18 both depend on T15, with disjoint UI and journal ownership. T17 changes signing internals only after T09 proves a bottleneck. T19 and T20 remain independent feasibility tracks. A repaired RC must repeat the affected dependency chain. [First five prompts and test commands](CODEX-EXECUTION-PLAN.md)
