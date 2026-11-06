# Release only after eight gates pass

**No-go on the November 4 evidence.** A grade of 0 means a known failure or no qualifying evidence. A grade of 1 means scoped evidence exists but the complete candidate gate is open. A grade of 2 requires every acceptance condition for the exact approved candidate. The current 6/16 evidence points describe evidence coverage, not a percentage of work complete. Each gate must reach 2. Do not average away a failed gate. A reduced support claim needs its surviving tuples retested and its documentation updated.

| Gate | Grade | Current evidence | Objective acceptance and retained artifact | Blocker / owner task |
|---|---|---|---|---|
| G1 Signing correctness | 1 | One independent final-archive fixture and selected planner/archive tests passed. | For each promised input, sign with the frozen plan, export, unpack final bytes, verify each nested object and detached CMS using a second tool. Corrupt pages/resources/profile choice must fail. Record digest, verifier version, commands and nested results. | B02,B03,B11 / T03,T05,T08 |
| G2 Device installation and update | 1 | Older private development install/launch and saved reinstall were reported. Current candidate, Ad Hoc and continuity remain open. | Record all eight stages below on both target devices for every advertised credential/host combination. Wrong credentials fail before delivery. Compatible in-place update retains a fixture sentinel. Record actual fresh launch. | B06,B07 / T07,T12,T13 |
| G3 Security | 1 | Fixture defenses and source mitigations exist. Scope includes hostile archives, key custody, transport and updater. No clean full-candidate audit. | Trace untrusted ZIP/Mach-O/profile/injection/source inputs to parser, disk and signer. Trace identity lookup, log export and host redirects. Test limits, recursing links, path escape, mismatch, cross-origin bearer leakage and HTTPS refusal. Zero unresolved critical/high findings in supported scope. Preserve raw private evidence and redacted summary. | B02,B05,B07,B11 / T03,T07,T08,T10 |
| G4 Reliability and recovery | 1 | Journaling, stale-input checks, cancellation and fixture fault tests exist. Normal-flow restart, provider and lock cases remain open. | Execute the fault matrix below. In every interrupted case original and previous good result retain their hashes. No duplicate job or leaked active session. Each failure offers a tested retry, export or explicit start-over action. | B08 / T06,T07,T13 |
| G5 Performance | 1 | Historical one-device samples and a public methodology exist. CPU, RSS and scratch budgets lack a representative floor-device run. | Freeze corpus, measurement overhead and baseline before patching. Meet relative and absolute operational limits below. Retain raw samples, failures and thermal/OS metadata. | B09 / T09,T13 |
| G6 Usability and accessibility | 0 | Draft audit failed; primary normal-build VoiceOver journeys lack final proof. | At default, XXXL and AX5 on narrow and wide screens, perform three journeys with readable actions and errors. VoiceOver must reach, describe and activate every required control with predictable focus. Run automated audit, dark mode and Reduce Motion. Zero unresolved journey-blocking issue. | B04 / T04,T11,T13 |
| G7 Distribution | 0 | Normal candidate reader fails on a standard-shaped archive. Public CI and existing 0.16.3 release do not discharge it. | Real standard and Dev candidate builds, correct distinct IDs, exact tag/revision/build/provenance and independently recomputed IPA size/SHA across checksum, asset, source feed and site. Local previous-stage restore works. If publishing is approved, verify fetched bytes before declaring promotion successful. | B01,B10 / T02,T12,T14 |
| G8 Documentation and support | 1 | README, public conformance protocol and issue template exist. Candidate-matched first-use and support walkthrough absent. | Independent reader follows bootstrap, profile setup, first sign, export/server, renewal and recovery unassisted. Missing prerequisites lead to specific action. Support report strips secrets, device identifiers, URLs and input names before sharing. Document supported tuples and rollback contact. | B10 / T11,T14 |

## Record eight observations separately

| Stage | Required observation |
|---|---|
| 1. Import | Source-owned fixture and imported copy have the same SHA-256. Wrong-password and provider-cancel controls leave no partial item. |
| 2. Sign | User confirms the exact plan. The selected identity and profile match. Record signed output digest and plan fingerprint. |
| 3. Verify | Independent checker accepts final repacked bytes and nested signatures. Damaged control fails. |
| 4. Export | Files export exists and its SHA-256 matches the retained signed item. |
| 5. Deliver | Intended operator receives the exact bytes through HTTPS. Record server class and transfer completion without storing download tokens. |
| 6. Install | OS installation observed separately from handoff, download and prompt. Capture operator observation or sanctioned device tooling. |
| 7. Launch | Freshly open candidate fixture and observe a unique visible run marker or fresh process evidence. URL scheme alone is insufficient. |
| 8. Update | Seed fixture data, install compatible next build, launch it and read the original sentinel. Check bundle/prefix/group changes separately on an incompatible update. |

Run a simple app plus one app with an extension whose actual capability can be invoked. Pair each promised Development and Ad Hoc profile family with the proposed stable HTTPS route. Test an older floor device and a current supported device/OS. Record hardware class, OS version, credential type, profile scope, build, input and output digests, tool versions and permission state. Keep raw details private. With no suitable floor device, lower the claim to the verified combinations or hold release. Experimental routes receive separate observations. A bucket fixture or loopback download cannot substitute for an operator-host install.

## Trigger failures at the boundary that owns them

| Boundary | Fault injection | Observable after restart or retry |
|---|---|---|
| Files import | Cancel cloud download, invalidate provider handle, exhaust scratch while copying | Prior shelf/index unchanged. Action reacquires provider or explains missing storage. |
| Archive and sign | Malformed offsets/CRC, traversal, links, encrypted input, wrong identity, expired plan, changed prepared tree | No write outside staging, no invalid output publication, bounded work, useful message. |
| Library | Fail index commit, terminate after staged write, reimport equal bytes and same-name different bytes | Exactly one valid duplicate or a distinct version. Existing original and retained signed digests survive. |
| Background | Lock, expire task, cancel during CPU work, kill process, complete an old generation after starting a new job | Stop progress for obsolete job, no duplicate terminal result, recover completed item or restart safely. |
| Network | Slow headers, timeout, offline, 401/403 refresh, hostile redirect, TLS failure, interrupted upload, retry | Credentials never cross origin, finite attempts, stale hosts close, original signed item remains exportable. |
| Update / config | Launch against prior shelf and credential schema, deny reminders, stale host settings | Migration idempotent, deliberate reimport when required, no destructive reset or automatic upload. |

## Freeze performance limits before running the RC

Use deterministic small/71 MB-class/large mixed and extension fixtures. Match compression, source bytes, device and thermal class across baseline and candidate. Run one warm-up and at least five samples per case, report median and nearest-rank p95 (the maximum of five), plus cold start separately. Time signing, saving, exporting and delivering as distinct intervals. Record process CPU time, peak resident memory, peak temporary disk bytes, main-thread heartbeat and cancellation-to-idle. Retain full raw series including failed runs. [R13 method](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/docs/benchmarks/R13-METHODOLOGY.md)

Proposed go/no-go budgets for matching baseline hardware and workloads are at most 10% median elapsed or CPU regression, 10% peak RSS regression and 10% peak scratch regression. No memory-pressure termination, disk overcommit or uncaught OS termination on supported fixtures. No recurring main-thread stall over 250 ms and user cancellation produces visible feedback within one second; measure cleanup independently until idle. A missing comparable baseline blocks the numerical claim. Pre-register a workload-specific absolute memory and scratch ceiling from the floor phone before freezing the RC, publish that ceiling with results, and reject a candidate that breaches it. A speed gain cannot excuse incorrect signatures or impermissible memory use.

## Who signs off and when

The permitted November 4 panel preflight reported local policy errors for all three configured models. No full security or release panel approval exists. Consequential implementation or promotion needs the required independent review or an explicit owner exception. The signing reviewer owns G1, device operator G2, independent security reviewer G3, recovery owner G4, performance owner G5, accessibility reviewer G6, release owner G7 and independent first-use tester G8. Store evidence under a versioned private directory keyed by source SHA, asset SHA and matrix row, then publish just redacted summaries. A new binary invalidates its old binary-specific results. If a post-publication digest check fails, stop promotion and restore the last independently verified stage under the operator's approved rollback procedure.
