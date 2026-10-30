# Improvement roadmap

## Delivery boundary

The user approved the audit and safe local fixes. This roadmap proposes later work; it does not approve releases, pushes, account changes, hosting changes or device use. Preserve signing validation, certificate/profile rules, artifact provenance, library commits, install-session ownership and iOS acceptance caveats.

Recommendation: Direction A, Refined Wax. See DESIGN-DIRECTIONS.md for alternatives and FEATURE-IDEAS.md for 32 scored opportunities. Risks and proposals require validation before defect claims.

## Tier 1: approved safe fixes, integration in progress

These five work packages are planned or in progress across the audit team. “In progress” includes a tested patch held for baseline capture. Root's final diff, tests and rendered checks determine completion; this document does not claim they have shipped.

| Package | Scope | Acceptance and evidence |
|---|---|---|
| Shelf truth | SignView reads actual shelf save state, offers retry/export and links to Signed only after commit. | Delayed save, failure and retry checks; retained output remains exportable. Source/behavior tests must distinguish signing success from storage success. |
| Delete confirmation | ContentView confirms the selected IPA before removing Wax's copy. | Cancel preserves entry/file; confirm removes only the chosen entry; prompt names the app and does not promise uninstall. |
| Reduce Motion press feedback | Existing primary/tab button styles suppress scaling and springs with the preference on. | Source checks plus rendered press/release checks in both preference states. |
| Scalable pills and visible tab labels | WaxPill grows with text; tab titles remain visible at accessibility sizes. | Narrow width, both appearances, largest text, distinct tap targets and selected-state accessibility checks. |
| Melt visibility | SignView passes selected-tab visibility into existing WaxMelt pause input. | Source regression test demonstrates red/green/revert-red/restored-green. Actual hidden callback and energy behavior still needs profiling. |

Baseline coordination matters. Accessibility and melt patches briefly existed during root's baseline work, then workers restored baseline on request. Root must ensure before captures use a known baseline binary and after captures use the final edited binary. A mixed build cannot support a before/after claim.

## Tier 2: common-flow clarity

1. Correct host readiness wording and step-specific recovery (O10, O12). Review messages with current model states; do not infer reachability from configuration.
2. Preserve source-add attempts and show direct-download jobs (O07, O08). Agree on job identity and stale-result rules before changing source state.
3. Expose cancellation beside the active install/download and retain useful artifacts (O09, O11). Trace session ownership and failure paths before adding controls.
4. Keep errors and refresh retries attached to their source/app/job (O14, O18). This is a shared-state change, so use an approved design and consequential review.
5. Make source redownload actions explicit and credential choices distinguishable (O13, O15, O16). Check duplicate names, renewed certificates and prior-versus-current source metadata.

Verify each package independently with controlled fixtures and focused regression checks. Add rendered interaction checks when the change affects sheet dismissal, focus or navigation. No broad visual rewrite is needed for this tier.

## Tier 3: adaptable layout and library scale

- Give action sheets scrollable content and expandable detents (O20).
- Stack editable option fields at accessibility sizes and verify nested target frames (O21, O24).
- Add screen heading traits and check VoiceOver rotor/focus behavior (O25).
- Add shelf search only after checking representative library sizes and selection behavior (O17).
- Clarify unsigned empty-state copy, option effects and saved-default scope (O19, O22, O23).

Acceptance includes ordinary/XXXL/all accessibility sizes, light/dark appearances, narrow width, landscape where supported, Reduce Motion, VoiceOver and dismissal-focus restoration. Source tests do not replace those checks.

## Tier 4: profile-led performance work

Start with cold source loading (O27), large shelves (O28) and repeated search filtering (O29). Use PERFORMANCE-AUDIT.md for commands and evidence boundaries. Record one controlled baseline, change one cause and compare the same scenarios. Do not optimize from elapsed compile time.

Artwork bounds, startup changes and preview caching remain investigations (O30-O32). Inspect existing PreparedIcon and migration ordering first. Add a dependency or change observation architecture only when a trace identifies a problem that current helpers cannot solve.

## Later design gates

Direction B requires navigation/control migration and a reviewed spec. Direction C requires a shared job contract, recovery ownership and broader tests. Neither belongs in the safe-fix patch. Revisit them after Tier 2 results show whether local improvements cover the task-recovery need.

## Completion evidence

For each implemented package, root records final changed files, exact checks with exit codes, screenshots from a known binary and unresolved limits. A successful simulator build proves compilation for that target. UI captures prove only the states shown. They do not prove physical-device signing, installation, launch, battery behavior or a full VoiceOver audit.

## Final integration status, 2026-10-30

See IMPLEMENTATION-REPORT.md for the final checkout, test counts and screenshot comparisons. The targeted source fixes are applied. Small-screen AX5 navigation and large dark journeys pass. The automated Dynamic Type audit remains failing; manual VoiceOver and active-job Instruments profiling remain unverified. The free-only three-model panel is incomplete (0/3); no paid fallback. This status supersedes earlier in-progress notes.
