# Simple Wax: usability, onboarding and signing options

Date: 2026-10-28. Status: approved by Dylan on 2026-10-28; resumed after usage warning.

## Intent and constraints

Make normal Wax easy to understand and operate, fix clipped content, and expose useful compression choices without bringing back developer tools. Work on the Mac and iOS simulator only. Do not access the physical phone, change personal signing data, publish, push, or release. Preserve existing local changes. All external model reviews must use the guarded free-only provider configuration and report incomplete reviews.

This update cannot establish that every possible IPA, certificate or iOS installation will work. Acceptance covers the defined supported flows and failure cases; physical installation remains a separate verification boundary.

## Approach

Keep SwiftUI and UIKit with the existing Wax components and visual style. Prefer built-in permission, motion, sharing and accessibility APIs. Do not add an analytics SDK, crash-report backend or new dependency.

Alternatives considered: a wholesale UI redesign would increase regression risk; a new feedback service would add account and privacy work. Recommend focused changes to existing screens and a local report preview with a user-controlled sharing action.

## Normal and Dev builds

Normal Wax retains Sources, IPA library, Sign and Settings. Hide advanced app edits behind a collapsed More options section. Keep probes, raw entitlement editing, raw Info.plist editing, diagnostic logs, profiling and test actions restricted to Wax Dev. Compression, notification permission, the tutorial and reporting a bug are normal user features. Keep the separate Dev download and app identity.

Audit both source conditionals and built app resources. Do not remove validation, signing failures, recovery messages or helpful explanations to make the interface appear simpler.

## Layout and visual polish

Reproduce the last-row cutoff in Settings and IPA with populated content. The root already uses safeAreaInset; source inspection does not prove the cause. Inspect the populated screen and bar frames, including nested navigation containers, before selecting a fix. Ensure the last row and every control scroll completely above the actual bar without adding a duplicate inset. Avoid a fixed guessed spacer that fails at larger text sizes.

Audit all tabs, signing options, credential import, profile cards, report sheets and first-run guide for alignment, spacing, truncation, keyboard overlap and usable touch targets. Reuse shared spacing and typography. Test light/dark appearance, small phone, standard phone, iPad, large text and Reduce Motion. Preserve text selection and scrolling where appropriate; do not clip long names or errors to force alignment.

## Notifications

For authorization not yet determined, show Enable notifications and request alert/sound permission directly in response to that tap. Reuse one permission coordinator for signing completion and expiry reminders. Permission requests originate only from the explicit Enable notifications action. Remove automatic authorization requests from ordinary signing/install jobs; jobs and reminders consult permission without prompting. Test that signing alone cannot open the permission alert. Refresh actual permission state after the prompt and app foreground. Handle denial and request errors without claiming permission was granted.

For denied permission, explain the iOS restriction and offer Open Settings. iOS does not show its permission prompt again after the decision. For authorized/provisional states show the actual state and avoid sending the user to Settings unnecessarily. Do not prompt automatically inside the tutorial. Enabling expiry reminders must explain whether notifications are available.

## Compression and signing speed

Expose one plainly named compression picker in Signing options, replacing conflicting compression toggles for normal users. Use existing modes: Standard compression, Faster compression, and Faster signing / larger file. Preserve existing preferences: until an explicit picker choice, keep legacy behavior (standard exports, existing flags for phone installs). For the picker initial selection, map storeUncompressed=true to larger-file mode, otherwise fastDeflate=true to faster compression, otherwise standard. Once explicitly selected, persist one global mode immediately, labeled Applies to future signing jobs; this setting is separate from app-edit Save as defaults. Resetting app edits does not silently change compression.

The control must state that it affects changed large files; Wax already reuses unchanged compressed data. The existing uncompressed path affects changed files of at least 2 MiB. Avoid claiming the whole IPA is uncompressed. Capture a single chosen mode for each signing transaction so changing Settings cannot alter a running job. Apply the explicit selection consistently to signing/export and installation, with descriptions of the resulting file-size tradeoff. Keep existing archive and signature integrity gates.

Benchmark representative small/large and compressible/incompressible inputs, warm and repeated runs, with phase timings and output sizes. Separate engine, library save, upload and iOS installation. Simulator/Mac timing is not proof of faster physical installation. Add a speed change only after measuring its bottleneck and showing correctness and cancellation/storage regressions pass. Existing compressed-entry reuse and saved-app installation must stay intact.

Research additional signing options, but add only a useful, supported option with a clear user benefit and verified platform behavior. List other candidates and tradeoffs in the audit instead of adding speculative switches.

## Shake to report a bug

Recognize the native shake-ended event and open a local Report a problem sheet. Include a Settings entry so the same feature is accessible without shaking, and allow disabling shake reporting. Do not interrupt a password entry, document picker, tutorial or an in-flight signing/install action; defer or ignore repeated shakes safely.

The sheet lets the user describe what happened and expected behavior. Include only app version/build and OS version by default. Show the entire report before sharing. Provide Copy report and system Share; opening the existing GitHub issue form is an explicit user action. Never submit a report automatically. Do not attach screenshots, logs, certificate names, fingerprints, UDIDs, URLs, keys, passwords or IPA contents automatically. Cancel discards the draft without sending anything. Screenshot/log attachment support is outside this update.

## First-launch permissions

Before the tutorial, show a skippable permissions setup with Enable notifications and Not now. State: You can change these later in Settings. Call the system notification prompt only from an explicit Enable action. Explain any action-bound permissions, such as local network access, when the relevant feature first uses them; do not invent a general iOS settings permission or request broad photo/file access when a system picker suffices. Include the same permission controls and explanations in Settings.

## Skippable animated tutorial

On a genuinely new installation, show a short guide covering Sources, IPA, Sign and Settings plus the need to bring signing files. Use animated examples with Next, Back, Skip and a final Get started action. Keep Skip visible from the first page. Persist completion or skipping, and offer Replay guide in Settings. Determine legacy state before model constructors create storage. Existing credential/library/source index files or app-owned saved preferences suppress automatic onboarding; unreadable existing state also suppresses it rather than pretending the app is new. Do not infer freshness from initially empty arrays while models load. Record the decision once, then persist Skip or Finish. Existing users can replay from Settings. An old installation with no remaining persisted evidence cannot be reliably distinguished from a new installation; document this limit.

The guide illustrates actions without importing files, signing, changing settings, scheduling notifications or launching other apps. Use actual section names and plain language. Respect Reduce Motion with static examples, VoiceOver labels and focus, large text and dark mode. Avoid timers that advance pages before the user is ready.

## Verification and audit evidence

Write failing tests before behavioral fixes. Cover notification authorization transitions; compression preference mapping and frozen transaction behavior; tutorial start/skip/replay persistence; report draft privacy/cancel/repeated-shake handling; normal/Dev feature separation. Use synthetic signing fixtures only.

Run relevant package and app-model suites, both app builds and packaging checks. Exercise simulator flows for populated library scrolling, imports, wrong-password retry, identity selection, signing/export, saved-app installation handoff, source errors, notifications, tutorial and reporting. Record screenshots and a check matrix, including failures and things the simulator cannot prove.

Use the three-model free panel for consequential signing/concurrency/privacy decisions and final review. A timed-out panel is incomplete; do not label it a clean review. Keep private review and simulator artifacts local. No release is part of this scope.
