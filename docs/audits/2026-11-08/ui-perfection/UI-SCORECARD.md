# UI scorecard — Brief 05

Weights (original, sum 100): alignment 20, aesthetics 15, consistency 12,
motion 12, typography 10, usability 10, accessibility 10, performance 6,
states 5. Only what was verified is scored. "Not reached" dimensions are
capped and stated, not extrapolated.

| Dimension (weight) | Score | Evidence |
|---|---|---|
| Alignment (20) | **16** | Tab widths equal (−0), header-above-bar (−0), primary ≥ 54 pt (−0) pinned by new tests; shared leading/trailing row anchors verified by reading (library `WaxRow` 40 pt tile + 68 pt min-height) but **not** assertable without a populated library tree walk; XXXL bottom-row overlap still open (E1/E3). |
| Aesthetics (15) | **12** | Oxblood/cream tokens untouched and contrast-passing; `WaxMelt` centred, pool never leaves canvas, seal prints in last fifth (read). Mid-melt pixels **not captured** (cannot reach signing), so candle/flame/pool judged from code +4 for prior 03 art, −3 for unproven mid-frame. |
| Consistency (12) | **8** | One spring + `waxMotion` vocabulary on paper; 5 unguarded `Wax.spring` sites (A5), 1 `List` vs `ScrollView+VStack` (S8), no paragraph token (S7), `WaxListRow` limit missing (S6). Token discipline otherwise holds (`Wax.Space`, `Wax.Ramp` adoption). |
| Motion (12) | **8** | No double-animation on the same property anywhere; Reduce Motion honoured in every Wax-owned site (tab, primary, sheet, stage, stamp, guide, melt). Deducted for A1–A5 unguarded fills, highlights, rescrolls, and A7 snapped pill on programmatic tab changes. |
| Typography (10) | **7** | `Wax.Ramp` covers display→mono; large percent is monospaced-digit (no width wobble); stage/result text uses fixed sizes. Deducted for S7 (paragraph pieces improvised as `.body`/`.subheadline`/`.footnote`) and S4 profile wrap. |
| Usability (10) | **7** | Primary reachable at default size; all four tabs labelled; `performAccessibilityAudit` passes at default size. Deducted for S1 (primary below fold at XXXL, scroll to reach) and S2 (stage strip misreports preparation/handoff). |
| Accessibility (10) | **6** | Token contrast all ≥ 4.5:1; Differentiate Without Colour holds; touch targets pinned; `testAccessibilityAudit` passes at default. **Two failing gates at XXXL** (contrast-under-bar + library hit-test) cap this at 6 until E1/E3 are fixed. |
| Performance (6) | **4** | Invalidation bounded by throttle (≤ 100 `progressCard` rebuilds/run) and per-row expiry cache reads once; `WaxMelt` paused offstage/background/finished. **No frame rate measured** and signing never run end-to-end, so capped at 4 — this is a reasoned budget, not a profile. |
| States (5) | **3** | Idle, error, empty, and result headers all have truthful copy and screenshots. Deducted for S2/S3 (preparing/handoff + estimate percent) and the un-captured populated-dark-library (S9). |

**Total: 71 / 100.** What would move it: fixing E1 + S1 (one layout fix
each) lifts accessibility and usability by ~3; A1–A5 (five one-line Reduce
Motion guards) lifts motion by ~2; a real signing capture lifts aesthetics
and states by ~2. Until then 71 is the honest score for the verified build.

## After the fix pass

The same weights, re-scored on the fixed build. The 71 above stays as the
brief-05 score of the merged base; this is what the same rubric says about
the current branch.

| Dimension (weight) | Score | Why it moved |
|---|---|---|
| Alignment (20) | **19** | The XXXL under-bar overlap is gone and the last library row now clears the bar (E3 test passes). Only open point: no automated leading/trailing anchor assertion across library rows. |
| Aesthetics (15) | **13** | Dark populated library captured and clean. The mid-melt frame is still not captured, so the candle at partial progress remains judged from code. |
| Consistency (12) | **12** | A5 guards, the last product `List` replaced, the paragraph token added, and `WaxListRow` now has a title limit. |
| Motion (12) | **12** | A1–A5 and A7 fixed; A6 accepted by design and documented. Every Wax-owned animation is guarded. |
| Typography (10) | **9** | Paragraph copy has one token; the profile row no longer wraps to three lines. Fixed-size stage and percent text is deliberate. |
| Usability (10) | **9** | S2 and S3 fixed; at XXXL every action is now on screen, though the summary button still needs a scroll. |
| Accessibility (10) | **9** | Both XXXL gates pass and the busy import is announced. One point held back because VoiceOver was not driven by hand. |
| Performance (6) | **4** | Unchanged: still no frame-rate measurement and no end-to-end signing run. |
| States (5) | **5** | Preparing and handoff are real stages, the percent is measured, and the dark populated library is captured. |

**Total: 92 / 100.** The remaining eight points are evidence gaps rather than
known defects: an unmeasured frame rate, an uncaptured mid-melt frame, no
manual VoiceOver pass, one layout that cannot fit AX5 without scrolling, and
one missing anchor assertion. Claiming them without that evidence would be
inflation.

## Simulator capture (2026-11-10)

First run of the branch on a booted simulator: iPhone SE (3rd generation),
iOS 27.0, Xcode `Development` configuration, bundle `io.github.dylldev.wax.qa`,
build 0.17.3 (201). Driven with `agent-device`; captures in
`06-candle-simulator/`. This closes the mid-melt gap. It does not close the
frame-rate gap: `agent-device perf frames` refuses simulators ("Apple
frame-health sampling is currently available only on connected iOS devices"),
so no FPS or hitch number exists.

| Capture | What it shows |
|---|---|
| `04-light-0.png` | Full candle, pool absent, flame lit. |
| `01-light-35.png` | Candle shortened, first wax runs at the lip, small pool. |
| `02-light-97.png` | Wax collapsed into a wide pool, short burning stub. |
| `03-light-100.png` | Pool at its widest, stub still lit — the metaphor completes. |
| `05-dark-35.png`, `06-dark-100.png` | The same two states in dark appearance. The scene is a warm near-black card in both appearances, so it reads as one object rather than a hole. |
| `melt-animation.mp4`, `sheet.png` | 6.4 s recording of the slider dragged 95% → 6%. 24 distinct cells: the candle grows back continuously, the pool recedes, no pop, no restart, no jump. This is the 0→100 defect fixed, seen frame by frame. |

Re-scored with that evidence:

| Dimension (weight) | Was | Now | Why |
|---|---:|---:|---|
| Aesthetics (15) | 13 | **15** | Mid-melt verified in both appearances at four progress values; palette, silhouette and pool all hold. |
| Performance (6) | 4 | **4** | Unchanged. Continuity is proven; rate is not measurable here. |
| Everything else | — | — | Unchanged. AX5 primary confirmed visible on the SE, matching the earlier reading. |

**Total: 94 / 100** on this rubric. The six points left are evidence, not
defects: two for a device frame rate, one for a hand-driven VoiceOver pass,
one for the AX5 summary scroll, one for the missing leading/trailing anchor
assertion, and one for fixed-size stage and percent text held back as a
deliberate choice rather than a verified win.
