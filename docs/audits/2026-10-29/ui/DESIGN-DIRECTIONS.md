# Design directions

## Recommendation

Choose A, Refined Wax. The current semantic palette, seal, shared components and restrained signing illustration provide a coherent identity. Improve truthful feedback, visible navigation labels and adaptable layout first. B offers stronger system conventions but requires a navigation redesign. C makes long jobs easier to follow but introduces more job-state ownership and maintenance.

These directions are proposals, not implemented designs or validated usability results. The comparison draws on source and current official guidance. No preference test, pixel comparison or device study occurred.

## A: Refined Wax

**Philosophy.** Make the existing warm, focused signing tool clearer. Let the wax seal mark identity; let app names, phases, destinations and recovery actions explain work.

**Navigation.** Retain Sources, IPA, Sign and Settings and their preserved context. Keep each tab's visible name at accessibility sizes. Make deliberate cross-tab actions state their destination. Keep common job recovery beside the owning job rather than requiring a Settings detour. Review the custom tab bar against native interaction expectations without replacing it in this phase.

**Type and spacing.** Retain system text styles and current semantic tokens. Keep the existing inset/spacing scale. Replace rigid content heights with minimums and wrapping when text grows. Promote screen titles to accessible headings. Use a stacked field layout at accessibility sizes instead of shrinking text.

**Components.** Refine existing WaxPill, WaxFeedbackCard, WaxActionSheet and WaxRow. Distinguish Saving, Saved and Save failed. Show configured versus checked host status accurately. Attach errors to the app/source/job that caused them. Confirm named IPA deletion before removing Wax's copy.

**Motion.** Keep the candle during signing. Pause it off-tab, when inactive, after completion and for Reduce Motion. Apply the same preference to press-scale feedback. Preserve numeric/stage text so motion never carries essential status alone.

**Accessibility.** Preserve visible labels, scalable pills, readable sheets, contextual actions and 44×44 pt target goals. Validate VoiceOver focus, headings and selected-tab announcements in the actual rendered app. Existing opaque enabled text/status token pairs mostly exceed 4.5:1; preserve those results and check composited appearances separately.

**Complexity and maintenance.** Low to medium. Reuse current components and model states. Narrow fixes keep current tests and state ownership useful. Later cold-source and per-job changes need their own review.

**Pros.** Preserves recognizable assets and current workflows; supports surgical implementation; addresses evidenced defects without creating a second theme.

**Cons.** Custom navigation and controls still need accessibility and OS-version checks. Warm surfaces can become visually dense if each status gains a separate card. Keep recovery grouped with its task.

## B: Native utility

**Philosophy.** Emphasize familiar iOS containers and compact utility tasks. Keep Wax color and seal as accents within system navigation.

**Navigation.** Evaluate native TabView and NavigationStack behavior for all four areas. Use system toolbars and standard navigation titles. Keep state restoration and tab reselection requirements explicit before migration.

**Type and spacing.** Use system title, body and caption styles with native list/form spacing. Prefer semantic separators and grouped sections over repeated inset cards. Keep app identity and primary action prominent.

**Components.** Standard confirmation dialogs, sheets, progress views and forms replace some custom components. Preserve the existing passport, saved-artifact distinctions and source provenance copy. Native components do not remove the need for truthful state mapping.

**Motion.** Use system transitions. Limit the candle to a small optional signing illustration or completion mark. Honor Reduce Motion and avoid delaying interaction for effects.

**Accessibility.** Gain system control behavior, then test custom content, large-text forms and focus restoration. Preserve labels and contextual destructive text; a native wrapper cannot certify accessibility by itself.

**Complexity and maintenance.** Medium to high initial migration, potentially lower custom-control maintenance afterward. Root navigation, sheets, screenshots and UI tests would change together. This crosses the shared-interface/design gate and needs an approved spec.

**Pros.** Familiar controls and adaptive system behavior; fewer bespoke interactions; clear separation between content and navigation.

**Cons.** Broad migration and regression surface; can reduce Wax's distinct identity; persistent screen state, keyboard behavior and reselection need explicit compatibility work.

## C: Task-centered workshop

**Philosophy.** Organize the experience around the app being prepared and its current job. Make interrupted signing, downloading and saving easy to resume.

**Navigation.** Keep Sources and Library as entry points, then show an app workspace with input, identity, preparation, signing, delivery and saved outcome. Consider an activity destination only after proving users need several concurrent jobs. Do not add a fifth tab from assumption alone.

**Type and spacing.** Use a clear app heading and a compact sequence of phase sections. Collapse finished phases while keeping their outcome available. Make the current phase and its action easy to locate without color alone.

**Components.** A reusable job panel owns phase, progress, cancel, retry, retained export and destination. Source and library actions enter that same workspace. This requires a defined job identity and error ownership contract, rather than reading one global source message.

**Motion.** Use phase transitions to communicate actual work. Reserve the candle for signing and retain a stable text progress location across phases. Show explicit waiting and failure states instead of decorative perpetual activity.

**Accessibility.** Announce phase changes with controlled frequency, preserve focus across updates and group each job's controls. Keep a static readable timeline at large text sizes. Test cancellation, restoration and multiple-job focus order.

**Complexity and maintenance.** High. New task ownership and recovery presentation touch source, library, signing, install and routing boundaries. Requires an architectural spec, migration strategy and multi-model review before implementation.

**Pros.** Could make long-running and interrupted work easier to understand; exposes recovery at the point of failure; scales toward concurrent work.

**Cons.** Adds state coordination, navigation decisions and testing burden. An activity hub can duplicate existing tabs. Current evidence supports local job feedback fixes before this redesign.

## Comparison

| Criterion | A: Refined Wax | B: Native utility | C: Task-centered workshop |
|---|---|---|---|
| Identity | Strong continuity | Accent-level branding | Strong task metaphor |
| Scope | Existing components and flows | Container/control migration | Job ownership and navigation redesign |
| Delivery risk | Lowest | Medium to high | Highest |
| Immediate evidenced benefit | Truthful outcomes and readable controls | Familiar system interaction | Consolidated job recovery |
| Maintenance | Existing design system | More system behavior | New shared job contract |
| Decision | Recommended now | Later alternative | Explore after job-feedback improvements |

## Official references and evidence limits

- [Apple accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) supports larger text, sufficient contrast, familiar gestures and assistive technology testing. Its current table gives 44×44 pt as the default iOS control size and 28×28 pt as minimum. Wax should target 44×44 pt; do not misstate that as Apple's sole permitted size.
- [Apple motion HIG](https://developer.apple.com/design/human-interface-guidelines/motion) recommends purposeful, optional motion and alternate feedback. [Progress HIG](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) calls for accurate determinate progress where possible, consistent placement and useful feedback when work stalls.
- [Apple tab-bar HIG](https://developer.apple.com/design/human-interface-guidelines/tab-bars) and [Explore navigation design for iOS](https://developer.apple.com/videos/play/wwdc2022/10001/) support distinct top-level categories, clear labels and preserved context. The session cautions against automatic cross-tab transport. Review Wax's deliberate destination buttons separately from unsolicited routing.
- [AltStore's official press kit](https://faq.altstore.io/about-us/press-kit) offers labeled Browse, My Apps, app-detail, Settings, trusted-source and error-log screenshots. These provide reference scenarios; the reviewer retrieved captions and URLs, not a complete visual comparison.
- [Feather's official repository](https://github.com/claration/feather) supplies product imagery and source for certificate signing, repositories, app/certificate details and options. Its Nuke acknowledgement establishes a library choice, not a speed comparison.
- [SideStore's official repository](https://github.com/SideStore/SideStore) identifies its AltStore ancestry and standard iOS framework use. Compare it as a related product family rather than three independent proofs for a layout choice.
