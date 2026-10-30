# Wax UI scorecard

Date: 2026-10-29. **Current baseline: 6.71/10. Full-roadmap projection: 8.63/10.** Neither the projection nor the baseline is a measured user-study score. The projection assumes the proposed roadmap is implemented and validated; it is not the achieved score of this patch.

Weights sum to100%. Confidence is moderate for source/standard visual inspection and low for unprofiled performance, complete assistive-technology behavior and the unfinished adaptive matrix. Scoring penalizes uncertainty rather than awarding unverified excellence.

| Category | Weight | Current | Projected | Evidence and weakness |
|---|---:|---:|---:|---|
| Usability and task completion | 20% | 6.5 | 8.5 | Checklist and recovery are strong; direct downloads, cancellation and library search remain weak. |
| Navigation and information architecture | 12% | 7.2 | 8.8 | Four stable tabs and reselection; job cancellation is distant and largest-text tab labels disappear. |
| Visual design and perceived polish | 13% | 7.5 | 8.8 | Cohesive brand and captured spacing; report form and some dense technical rows remain uneven. |
| Accessibility | 14% | 6.0 | 8.5 | Adaptive palette and text; press motion, hidden tab text and fixed pills need correction. |
| Feedback, errors and truthful states | 12% | 6.4 | 8.8 | iOS acceptance caveats are sound; shelf-save success and direct-job feedback need work. |
| UI performance and animations | 9% | 6.4 | 8.3 | Detached signing and throttling exist; hidden timeline and cold main-actor decode are source risks, not measured lag. |
| Adaptive layout and responsiveness | 7% | 6.0 | 8.6 | Standard layout is sound; large text/action sheets and small screens need full coverage. |
| Design system consistency | 5% | 7.8 | 9.0 | Semantic palette, shared rows/buttons; a few fixed sizes and native form surfaces differ. |
| SwiftUI architecture and maintainability | 5% | 6.8 | 8.4 | Existing reuse and state separation help; large screens and source-derived body work limit clarity. |
| Onboarding and discoverability | 3% | 7.8 | 8.8 | Permission introduction and five-page skippable guide exist; task-focused coaching could be shorter. |

Calculation: sum(category rating × weight)/100. No rounded intermediate values.

## Requirements for higher ratings

### Usability and task completion: 6.5/10

Evidence/strengths/weaknesses: Checklist and recovery are strong; direct downloads, cancellation and library search remain weak. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Make direct downloads visible, attach recovery to the failed job, add library search and keep cancellation beside the active task. Pass those novice task journeys without instructions. For10/10: Observe independent first-time users completing import, sign, recover and install handoff without assistance; resolve repeated errors across a sustained release period.

### Navigation and information architecture: 7.2/10

Evidence/strengths/weaknesses: Four stable tabs and reselection; job cancellation is distant and largest-text tab labels disappear. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Keep four named tabs readable at the largest text sizes, preserve each navigation stack, and verify reselection, modal dismissal and keyboard transitions. For10/10: Independent screen-reader and novice sessions find destinations and recover context across interruption/restoration without unexplained failures.

### Visual design and perceived polish: 7.5/10

Evidence/strengths/weaknesses: Cohesive brand and captured spacing; report form and some dense technical rows remain uneven. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Remove clipped technical values and ambiguous row hierarchy, align shared components, and inspect comparable light/dark screenshots across device sizes. For10/10: Comparative user feedback and independent visual review find no material readability, hierarchy or consistency defects across the tested matrix.

### Accessibility: 6.0/10

Evidence/strengths/weaknesses: Adaptive palette and text; press motion, hidden tab text and fixed pills need correction. See the matching source register and screenshot matrix. Confidence: low.

For9/10: Pass automated audits and manual VoiceOver, largest-text, contrast, Reduce Motion, Bold Text and keyboard task journeys on supported hardware. For10/10: Independent assistive-technology testers complete all critical tasks, including failure recovery, with no material barriers across releases.

### Feedback, errors and truthful states: 6.4/10

Evidence/strengths/weaknesses: iOS acceptance caveats are sound; shelf-save success and direct-job feedback need work. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Derive save/delivery/install labels from acknowledged state, show per-job progress and error attribution, and retain valid files after failure. For10/10: Controlled disk/network/background/cancellation failures and independent user sessions verify every status/recovery branch without misleading success.

### UI performance and animations: 6.4/10

Evidence/strengths/weaknesses: Detached signing and throttling exist; hidden timeline and cold main-actor decode are source risks, not measured lag. See the matching source register and screenshot matrix. Confidence: low.

For9/10: Measure launch-to-interactive, main-thread stalls, scrolling frame times and active/hidden animation work on a named device and input; meet the recorded device-specific frame budget. For10/10: Repeat the controlled profiles across supported device classes and large realistic datasets, with stable results and no unexplained energy or memory regressions.

### Adaptive layout and responsiveness: 6.0/10

Evidence/strengths/weaknesses: Standard layout is sound; large text/action sheets and small screens need full coverage. See the matching source register and screenshot matrix. Confidence: low.

For9/10: Verify small/standard/large screens, light/dark, keyboard, portrait/landscape where supported and the full Dynamic Type range, with no clipped essential actions. For10/10: Independent adaptive-layout review covers long names, localization expansion, display zoom, assistive controls and interruptions without material defects.

### Design system consistency: 7.8/10

Evidence/strengths/weaknesses: Semantic palette, shared rows/buttons; a few fixed sizes and native form surfaces differ. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Route status, spacing, motion and control variants through existing semantic components; remove justified one-off inconsistencies without erasing Wax branding. For10/10: A maintained component gallery and visual regressions cover states, sizes and themes, and independent reviewers find consistent meaning across screens.

### SwiftUI architecture and maintainability: 6.8/10

Evidence/strengths/weaknesses: Existing reuse and state separation help; large screens and source-derived body work limit clarity. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Keep view rendering free of synchronous disk decode, preserve job ownership and cancellation, and test state transitions through behavior rather than string snapshots. For10/10: Independent whole-flow reviews and long-running regression history support changes without recurring state or data-integrity incidents.

### Onboarding and discoverability: 7.8/10

Evidence/strengths/weaknesses: Permission introduction and five-page skippable guide exist; task-focused coaching could be shorter. See the matching source register and screenshot matrix. Confidence: moderate.

For9/10: Make permission choices optional, keep Skip/replay discoverable, and show the next action in context without requiring a full tour. For10/10: First-time users with varied signing knowledge complete setup and recover from denied permissions without coaching; improvements hold across repeated studies.

## Screen ratings

| Screen | Current /10 | Full-roadmap projection /10 | Basis / blocker |
|---|---:|---:|---|
| Sources | 6.2 | 8.6 | Good provenance/search; direct-job and retry feedback gaps |
| IPA Library | 6.3 | 8.8 | Recovery works; no search and unsafe baseline deletion |
| Sign | 7.2 | 8.8 | Clear setup; distant cancel and technical host terms |
| Signing Options | 7.0 | 8.6 | Progressive disclosure; dense field rows and defaults terminology |
| Signing Preview | 7.0 | 8.8 | Truthful passport; runtime credential-dependent screen not captured |
| Signing Progress/Results | 6.2 | 8.8 | Real pipeline stages; save-status bug and unprofiled animation |
| Credentials | 6.8 | 8.6 | Safe import/retry; duplicate names and technical concepts |
| Installation | 6.4 | 8.5 | Honest iOS caveat; configured/ready and scattered recovery |
| Settings | 7.6 | 8.8 | Standard capture reaches bottom; advanced grouping can improve |
| Global Navigation | 7.2 | 8.8 | Stable tabs; largest-text visible names removed |

A defensible10/10 requires broader real-user, assistive-technology, failure-injection and profiling evidence than this audit provides. No usability testing with novices has been fabricated.
