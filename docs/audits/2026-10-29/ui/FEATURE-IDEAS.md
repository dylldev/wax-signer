# Evidence-backed opportunities

## Scoring and limits

Scores are reviewer judgments, not user-study results. V = user value, Vis = visual impact, U = usability benefit, F = feasibility, each out of 10. Higher feasibility means easier delivery. Effort: XS is a local edit, S is a small component change, M spans a flow, L changes shared ownership. Regression risk describes what a change could disturb. Priority: P1 addresses misleading outcomes, data loss or access; P2 improves a common flow or measured-risk candidate; P3 is optional polish or scale work. A risk remains unverified until its acceptance checks run.

Source paths refer to the audit worktree. Baseline line numbers may move after approved fixes. Confirmed means source behavior, not runtime reproduction. Proposed features still need design approval where the global rules require it.

## Opportunity register

| ID | State and opportunity | Evidence | V/Vis/U/F | Effort | Regression risk | Priority |
|---|---|---|---|---|---|---|
| O01 | Confirmed: show actual shelf-save outcome after signing | SigningModel.swift:101-122; SignView.swift:470-539 | 10/6/10/9 | S | Medium: recovery/artifact access | P1 |
| O02 | Confirmed: confirm named IPA deletion | ContentView.swift:112-123; IPALibrary.swift:265-271 | 10/3/9/10 | S | Low: action-sheet handoff | P1 |
| O03 | Confirmed: honor Reduce Motion for press feedback | Theme.swift:182-183; WaxTabBar.swift:111-112 | 8/5/8/10 | S | Low: button feedback | P1 |
| O04 | Confirmed constraint: let status pills grow with text | Theme.swift:161-163 | 8/7/9/10 | XS | Low: neighboring row layout | P1 |
| O05 | Confirmed: retain visible tab names at accessibility sizes | WaxTabBar.swift:80,95 | 9/8/10/8 | S | Medium: narrow-width navigation | P1 |
| O06 | Confirmed: pass tab visibility to signing animation | LocalIPASignerApp.swift:98-103,141-147; SignView.swift:418 | 6/2/5/10 | XS | Low: static illustration | P1 |
| O07 | Confirmed: show direct-URL download status and recovery | SourcesModel.swift:75-80,127-141; SourcesView.swift:23-46 | 9/7/9/7 | M | Medium: job/error ownership | P2 |
| O08 | Confirmed: preserve failed source URL and pending state | SourcesView.swift:105-118,137-142; SourcesModel.swift:82-88 | 8/5/9/8 | S | Low: form submission | P2 |
| O09 | Confirmed: place install cancellation beside active job | SignView.swift:414-436; InstallSection.swift:124-126; SigningModel.swift:332 | 9/4/9/7 | M | Medium: install session ownership | P2 |
| O10 | Confirmed: replace configured-host “Ready” with accurate wording | SignView.swift:204-208,314-324; OTAInstallModel.swift:146-153 | 9/3/9/10 | XS | Low: status copy | P2 |
| O11 | Confirmed: provide download cancellation | SourcesView.swift:311-336; SourcesModel.swift:127-197 | 8/4/8/6 | M | Medium: retained files/background lifetime | P2 |
| O12 | Confirmed: offer recovery for the failed step | SignView.swift:52-55,145-147,556-560 | 9/4/10/6 | M | Medium: error taxonomy | P2 |
| O13 | Confirmed: label prior-download status and explicit repeat action | SourcesView.swift:322-327 | 7/6/8/9 | S | Low: repeat download semantics | P2 |
| O14 | Confirmed: attach source errors to the owning app/job | SourcesModel.swift:70,98,118,132,188-193; SourcesView.swift:193,287 | 9/5/9/5 | L | High: shared source state | P2 |
| O15 | Confirmed: distinguish renewed certificates in pickers | CredentialsView.swift:189-208; SignView.swift:248-250 | 8/4/8/7 | M | Medium: selection identity/privacy | P2 |
| O16 | Confirmed: name certificate/profile in deletion prompts | CredentialsView.swift:141-155 | 8/2/8/9 | S | Low: duplicate-name clarity | P2 |
| O17 | Confirmed scale opportunity: search the IPA shelves | ContentView.swift:23-79; SourcesView.swift:205 existing pattern | 7/5/8/7 | M | Medium: filtering/selection state | P3 |
| O18 | Confirmed: attribute combined refresh errors to each source | SourcesModel.swift:109-118 | 7/3/8/8 | S | Low: error display | P2 |
| O19 | Confirmed: clarify Unsigned empty-state destination | ContentView.swift:138-146 | 6/3/7/10 | XS | Low: copy | P3 |
| O20 | Risk: make action sheets scroll and expand for larger text | Theme.swift:350-364; ContentView.swift:96; SourcesView.swift:67 | 9/7/10/8 | S | Medium: sheet action/dismissal reachability | P2 |
| O21 | Risk: stack signing fields at accessibility sizes | SigningOptionsView.swift:168-179,275-284 | 8/6/9/7 | M | Medium: editable-field focus | P2 |
| O22 | Proposal: qualify runtime effects of signing switches | SigningOptionsView.swift:77-85 | 6/1/7/10 | XS | Low: copy comprehension | P3 |
| O23 | Proposal: explain session switches versus saved defaults | SigningModel.swift:43-46,354-359; AppEditor.swift:66-71 | 6/2/7/9 | S | Low: copy | P3 |
| O24 | Risk: size nested icon/text actions to a 44pt target goal | SigningOptionsView.swift:205-208,260-262,283-286,375 | 8/4/9/8 | S | Medium: adjacent hit-region overlap | P2 |
| O25 | Confirmed: add accessible screen heading traits | Theme.swift:237,253; FirstRunGuide.swift:172 precedent | 7/1/9/10 | XS | Low: rotor duplication | P2 |
| O26 | Proposal: align determinate interpolation with motion preference | Theme.swift:211,214-215 | 5/3/6/9 | XS | Low: perceived progress | P3 |
| O27 | Confirmed: move cold source-cache decode off UI actor | SourcesModel.swift:60-65; SourceStore.swift:65-70 | 8/2/8/6 | M | Medium: snapshot/loading race | P2 |
| O28 | Confirmed scale risk: create IPA rows lazily | ContentView.swift:30-68,253-264 | 7/2/7/8 | S | Medium: scroll/task lifecycle | P3 |
| O29 | Confirmed repeated work: derive one search result snapshot | SourcesView.swift:183-199 | 6/1/7/8 | S | Low: stale query/catalog results | P3 |
| O30 | Risk: bound source artwork decode size after profiling | SourcesView.swift:240-245 | 6/3/6/6 | M | Medium: image quality/cache behavior | P3 |
| O31 | Risk: profile synchronous startup storage work | LocalIPASignerApp.swift:54-65; CredentialsModel.swift:32-43; SourceStore.swift:41-58 | 7/1/7/8 | S investigation | High if migration ordering changes | P2 investigation |
| O32 | Risk: cache chosen-icon preview only if repeated decode is material | SigningOptionsView.swift:211,223 | 4/1/4/7 | S investigation | Low: preview freshness | P3 |

## Top ten: design and technical acceptance

### O01: Truthful shelf-save feedback

Design: keep the successful signing result, then show a distinct shelf state: Saving, Saved under Signed, or Save failed. Put Retry Save and retained export beside failure. Only a committed save may display the Signed-shelf destination link.

Technical acceptance: derive the card from existing SigningModel.shelfSaveState and call retrySignedSave. Exercise delayed commit, committed save and failure fixtures. Verify failed commit preserves exportable output and does not announce a successful save. Retrying must use the retained artifact without signing again. Preserve the distinction between signature checking and iOS acceptance. Existing files: App/SignView.swift and App/SigningModel.swift.

### O02: Named IPA deletion confirmation

Design: after Delete, show the selected app name and explain that Wax removes its stored IPA copy. Offer Cancel and a destructive confirmation. Do not imply removal of an installed app.

Technical acceptance: store the pending LibraryEntry before the action sheet dismisses; call LibraryModel.remove only from confirmation. Cancel must not mutate storage. Check unsigned/signed entries, long names, repeated presentations and a dismissal followed by another selected entry. Preserve existing library error reporting. Existing file: App/ContentView.swift.

### O03: Reduce Motion press feedback

Design: keep immediate color/opacity feedback while suppressing press-scale and spring effects when Reduce Motion is enabled. Normal settings retain current behavior.

Technical acceptance: read accessibilityReduceMotion in the existing primary and tab button styles. With the setting on, scale remains 1 and animation is absent. Toggle the preference while the app is open. Test primary buttons and four tabs. Source regression checks prove wiring; rendered press/release checks prove actual behavior. Existing files: App/Theme.swift and App/WaxTabBar.swift.

### O04: Scalable status pills

Design: preserve the capsule shape and ordinary size, but let the label increase its height. Allow containing rows to adapt rather than shrinking text.

Technical acceptance: replace fixed 26pt height with a minimum and padding. Test short/long statuses at ordinary and all accessibility sizes, in both appearances. No text escapes the capsule or overlaps neighboring identity text. Preserve current status semantics and spoken values. Existing file: App/Theme.swift, WaxPill.

### O05: Visible enlarged tab labels

Design: keep Sources, IPA, Sign and Settings visible at accessibility sizes. Permit wrapping and a taller bar within the safe area. Preserve selected-state cues beyond color.

Technical acceptance: remove the source branch that omits visible titles. Test narrow supported width, long localized labels, all accessibility sizes, keyboard presentation and bottom inset. Each tab remains separately tappable and speaks its name/selected state once. Do not lock fonts to ordinary sizes. Existing file: App/WaxTabBar.swift.

### O06: Tab-aware candle animation

Design: the candle stays as the signing identity cue. Other tabs do not need its decorative timeline updates; returning to Sign shows current real progress.

Technical acceptance: pass `router.tab == .sign` into WaxMelt.isVisible at the existing SignView call. Keep scene phase, Reduce Motion and completion checks. Source check must fail without that argument, pass with it, fail on reversion and pass on restoration. Later profile draw callbacks with Sign visible and hidden; no energy or frame-rate claim follows from source checks. Existing files: App/SignView.swift and App/WaxMelt.swift.

### O07: Direct-download job card

Design: after a pasted IPA URL starts work, replace the disappearing address with a card showing filename and transfer/save phase. Keep failure, retry and retained export attached to this card. Show the shelf destination only after commit.

Technical acceptance: give source-less downloads a stable visible job identity. Reuse existing SourcesModel.get and library save states instead of a second download engine. Cover network failure, archive rejection, save failure, duplicate file, retry and successful commit. Starting another job must not erase the first job's actionable failure. Existing files: App/SourcesView.swift and App/SourcesModel.swift. This requires a small flow design before implementation.

### O08: Recoverable source-add form

Design: retain the submitted address while adding a source. Show pending state and preserve the address on failure. Successful completion can clear it. Keep direct IPA jobs visibly distinct from repository addition.

Technical acceptance: add an operation result/pending state to the existing source-add path. Prevent accidental repeated submissions for the same attempt. Test malformed address, non-HTTPS rejection, network error, parse error, duplicate source and successful add. A stale operation must not clear a later edited address. Existing files: App/SourcesView.swift and App/SourcesModel.swift.

### O09: Local install cancellation

Design: place Cancel beside the current installing/uploading job and keep the result in the same context. Explain which saved file remains available. Do not dismiss a job as complete because upload ended.

Technical acceptance: call the existing cancellation capability for the owning install session. Cover cancellation before upload, during upload, after a ready link, and a stale callback from a canceled session. Keep signed/exported artifacts and prevent a canceled session from replacing a newer result. Preserve existing session ownership tests. Existing files: App/SignView.swift, App/InstallSection.swift, App/SigningModel.swift and App/OTAInstallModel.swift. Shared behavior needs the required design/review gate.

### O10: Accurate host readiness

Design: use Configured for syntactically complete host settings. Reserve stronger language for a relevant dated check, with a separate explanation that iOS decides installation.

Technical acceptance: derive the existing configuration-only row from the same model state while changing its displayed promise. Exercise missing, invalid and complete settings. Verify no new network request or validation bypass appears. Review passport and result copy together for consistent meaning. Existing files: App/SignView.swift and App/OTAInstallModel.swift.

## Prioritization caveat

The top ten emphasize concrete current behavior and small accessibility fixes. O27 cold source loading can move ahead of a broader feature when a trace shows UI-thread delay. O14 per-job errors and O09 cancellation change shared state and need more design work than their visible buttons suggest. Scores do not authorize those changes.

## Final delivery status

O01–O06, O10 and O19 now describe improvements implemented by this audit rather than future feature requests. O05's final design retains all labels but bounds navigation-label scaling at xxxLarge; main content still honors AX5. The final OCR test and a100pt maximum tab-button height guard replaced the oversized early wrapping prototype. Other opportunities remain proposals with the acceptance criteria above. See IMPLEMENTATION-REPORT.md for actual results and limitations.
