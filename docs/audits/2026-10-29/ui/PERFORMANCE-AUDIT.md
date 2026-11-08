# Performance audit

## Evidence boundary

This document records source inspection on 2026-10-29. The reviewer did not build Wax, run a simulator, use a phone or record a runtime trace. Root's separate build and UI work may supply additional evidence; no pending result counts as a measurement here. Compile duration measures the build process, not launch time, frame rate or signing speed.

Repository paths below refer to the audit worktree. Source lines describe the audit baseline and may move after the approved fixes. Detailed evidence: `/Users/[private reference omitted]/.codex/artifacts/wax-ui-audit-20261029/performance-references.md`.

## Findings

| ID | Source-proven behavior | Consequence to investigate | Recommendation |
|---|---|---|---|
| P1 | App/LocalIPASignerApp.swift:98-103,141-147 keeps four screens mounted through opacity. App/WaxMelt.swift:8-15 defaults visibility true and requests a 1/30-second timeline. App/SignView.swift:418 omits tab visibility. | Hidden signing illustration remains eligible for updates while another tab shows. Actual draw callbacks and energy cost require a trace. | Pass selected-tab visibility into the existing pause condition. This is an approved Tier 1 fix, pending root's final integration verification. |
| P2 | MainActor SourcesModel.apps(of:) at App/SourcesModel.swift:60-65 calls SourceStore.cached. Sources/SourcesKit/SourceStore.swift:65-70 synchronously reads and decodes JSON. SourceAppsView invokes it during body evaluation at App/SourcesView.swift:183-199. | Cold source loading performs file I/O and parsing on the UI actor. | Load a source snapshot off the UI actor and publish explicit loading/error state. Preserve cached-content availability. |
| P3 | App/ContentView.swift:30-68 uses VStack for all shelf rows. SignedExpiryPill at 253-264 can launch detached archive inspection for legacy entries. | Large shelves eagerly create views and initial expiry tasks. | Measure the scale threshold, then reuse the LazyVStack pattern already present in SourcesView. Preserve row identities and expiry caching. |
| P4 | App/SourcesView.swift:183-199 recomputes filtered matches for prefix, counts and empty state; the 300 cap applies after filtering. | Search work grows with the full catalog and repeats within body evaluation. | Derive one result snapshot per query/catalog revision if profiling establishes a material cost. |
| P5 | AsyncImage at App/SourcesView.swift:240-245 scales/clips to 40×40 pt without an explicit decoded-pixel policy in this view. | Large source artwork may deserve bounded thumbnails and cache accounting. | Measure remote dimensions, decoded memory, requests and decode stacks. Do not claim AsyncImage lacks framework caching or always decodes on the main actor. |
| P6 | App init runs keychain migrations and constructs credential storage at App/LocalIPASignerApp.swift:54-65. CredentialsModel.swift:32-43 loads stored metadata. SourceStore.swift:41-58 reads its index during SourcesModel initialization. | Startup includes synchronous storage work. | Profile launch stacks before rearranging required migration ordering. |
| P7 | App/SigningOptionsView.swift:211 constructs UIImage(data:) in body. PreparedIcon supplies the bytes at 223. | Repeated preview construction may show in a profile. | Inspect existing PreparedIcon bounds before adding another image abstraction or dependency. |

## Existing controls to preserve

LibraryModel.refresh performs recovery, enumeration and URL preparation in Task.detached (App/LibraryModel.swift:38-47). Import and archive inspection also use detached tasks. CredentialsModel.refreshIdentityChecks uses a detached worker and rejects stale results (50-70). SigningModel uses detached signing work and ProgressThrottle (435-496,653 onward). The throttle already limits unchanged-message progress publication to one-percent advances. Do not describe all signing or import work as main-thread work.

Shared ObservableObjects and persistent screens do not alone prove excessive invalidation. Keep the existing ownership model unless SwiftUI profiling identifies the expensive dependency and a narrower change can address it.

## Measurement plan

No numeric latency, CPU, memory or energy baseline exists in this review. Use the same build configuration, input bytes, catalog, shelf population and device/OS for comparisons. Save raw samples and environment details before comparing revisions.

1. Inventory tools with `xcrun xctrace list templates`. The reviewer verified xctrace exists at `/Applications/Xcode.app/Contents/Developer/usr/bin/xctrace` but did not run a capture.
2. Record active signing and signing while Sources is selected. Compare WaxMelt callback counts, CPU stacks, main-thread work and hitches using installed Instruments templates. The source's 30 Hz request is not a measured frame rate.
3. Open a source cold, reopen warm and search fixed queries. Record JSON bytes, catalog count, source icon dimensions, network requests, memory and parsing stacks. Separate network wait from parsing and rendering.
4. Compare an empty library with fixed larger shelves, including legacy signed entries lacking a signing record. Track first usable render, row creation and expiry inspection tasks. Validate scroll state and row actions after any lazy-layout change.
5. Profile cold launch with controlled source/credential metadata. Do not read private key material for this audit. Capture launch-to-interactive and the actual stacks that occupy the UI thread.
6. Repeat UI scenarios with Reduce Motion enabled. Assess physical-device thermal and battery effects only in an authorized device session; a simulator cannot establish either.

## Existing engine harness

`docs/benchmarks/R13-METHODOLOGY.md` documents an opt-in engine test:

```sh
WAX_PERF_IPA=/path/input.ipa WAX_PERF_OUT=/path/samples swift test --filter PerfTests.testStageTimings
```

This command builds and was deferred. Record revision, toolchain, OS, input SHA-256, compression and filesystem; use one warm-up plus at least five samples. Report median and nearest-rank p95. The harness records progress-event intervals, not CPU time or independent duration for overlapping stages. It cannot establish UI smoothness, installation success or phone energy behavior.

## Design implication

Direction A keeps the candle as a signing-specific identity cue. Stop its decorative updates when hidden; keep stage, percentage and recoverable outcomes readable. Improve cold loading and shelf scale before adding visual effects. No performance claim here justifies an engine rewrite.

## Recorded simulator observation

The root agent collected five host `ps` observations one second apart after launching the Release app on the iPhone17 simulator, empty Sign screen. Reported CPU percentages were0.1,0.8,1.3,1.8,3.3; resident sizes were290000,290000,290016,290016,290016 KiB. The process was recently launched and these host values include startup/scheduling effects. They do not measure phone energy, frame pacing, an active signing operation or CPU saved by hiding WaxMelt. The raw local artifact is `idle-before.json`. No before/after speedup is claimed. A fresh detached-work optimization needs a controlled active-job Instruments comparison.

## Final integration status, 2026-10-30

See IMPLEMENTATION-REPORT.md for the final checkout, test counts and screenshot comparisons. The targeted source fixes are applied. Small-screen AX5 navigation and large dark journeys pass. The automated Dynamic Type audit remains failing; manual VoiceOver and active-job Instruments profiling remain unverified. The free-only three-model panel is incomplete (0/3); no paid fallback. This status supersedes earlier in-progress notes.
