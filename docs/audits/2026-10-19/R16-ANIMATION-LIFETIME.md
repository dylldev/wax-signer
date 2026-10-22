# R16 milestone — Pause hidden/inactive decorative animation

Baseline R2/main `8ad4b2e`. Original `App/LocalIPASignerApp.swift:82–108` keeps all four tab trees mounted and switches only opacity/hit-testing/accessibility. `App/WaxMelt.swift:12` pauses its30Hz TimelineView only for Reduce Motion, so a signing screen hidden behind another tab continues decorative work; inactive scenes are not explicitly paused either.

`App/SignView.swift` now supplies actual tab visibility to WaxMelt. `App/WaxMelt.swift` pauses the animation schedule when hidden, scene inactive/background, Reduce Motion enabled, or progress complete. Rendering uses a static time when paused, while real progress changes can still update the drawing. Existing palette, geometry and Reduce Motion behavior remain. Debug preview defaults visible.

This small UI lifetime correction has no new dependency/test framework or mirrored policy tests. Syntax parse and existing Apple build/simulator CI are the available compatibility checks; physical Instruments/VoiceOver/Dynamic Type review remains necessary. No measured battery/CPU improvement is claimed. Test protocol: start a long sign, switch away and compare TimelineView/Canvas activity using Instruments; foreground/background, Reduce Motion and completion should stop periodic decorative ticks; returning to Sign resumes only when appropriate. Signing progress and job execution must continue independently.

Original R16 is not complete: source detail/developer information, bounded/downsampled artwork, localization, adaptive security sheets and full AX1–AX5/VoiceOver verification remain. R3 separately fixes source-scoped download identities. No visual redesign, job/cancellation/signing behavior change or device verification claim.
