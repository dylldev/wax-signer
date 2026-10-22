# Changelog

## 0.16.0
- Signed apps on the shelf show when their profile expires ("Profile expires in 3 days", "Profile expired"), red within a day and amber within three, and have a Re-sign action. Works for free 7-day and one-year enterprise profiles; it reads only the profile, so it cannot see a revoked certificate.
- Passport understands enterprise (In-House) profiles: no device list means any iPhone is eligible, and the revocation note explains that enterprise certificates can be revoked long before they expire.
- Expiry reminders come a week ahead for long-lived profiles (one day ahead for 7-day ones).
- Settings > Speed: "Fast compression for installs" (on by default).
- Fixes from a multi-model code review: a failed signing no longer blocks the next one; changing strict entitlements discards a stale preparation; a result is dropped if its input changed while saving; each run ends only its own background job; the fast level reaches all large files; compression write accounting; calendar-correct expiry days.

## 0.15.2
- Faster signing again: very large executables are compressed in parallel blocks, installs from This iPhone use a faster compression level (the file is about 2.5% bigger), and the "tree unchanged" safety proof now runs while the archive is being written instead of after it. Every check still happens; on a Mac a 322 MB app went from 21 s (0.15.0) to about 11 s.

## 0.15.1
- Signing is faster again: the safety checks added in 0.15.0 (hashing the whole app tree and verifying the finished archive) now use every CPU core. Same checks, same results; on a Mac a 322 MB app went from 21 s to about 14 s.
- The Bundle ID warning now says that keeping the ID with a one-app-ID profile can make iOS silently refuse an update of an app installed under another ID, and to use Rename to fit.

## 0.15.0
- Integrates the independent hardening work (R1-R16): bounded, recoverable IPA handling (parsers, archive integrity, packaging and extraction budgets), a transactional signed-IPA shelf (a failed save never loses the signed file; retry from the Sign screen), session-based installs with cancellation, cleaner background jobs, bounded source downloads, and a source-app details screen that shows what a source claims next to what the downloaded file really contains.
- Installability Passport stays the pre-sign check; a new strict-entitlements option refuses signing when a profile cannot grant what the app requests.
- Fixes the simulator test target (a fixture lookup that only worked under Swift Package Manager).

## Unreleased (0.14.1)
- Much faster signing: unpacking on every core, faster checksums, parallel hashing; about 19 s to 8 s for a 320 MB app on a Mac. On an iPhone 17, signing, uploading and installing a 322 MB app takes about 42 s end to end.
- New "Installability Passport": Wax checks the certificate, profile and app before signing and explains anything iOS may refuse. Only iOS makes the final install decision.
- Settings > Speed: optional "Skip compression for installs". Tested on a phone: no measurable gain, and the file is about 165 MB bigger, so it is off by default.
- Clearer Bundle ID help: to update an app already installed under another ID, use Rename to fit.
- Symlinks with `..` that stay inside the app are accepted; every link is checked against where it really leads.
- Unsupported universal-binary formats are refused instead of being sealed as plain files.
- Extensions nested inside Watch apps are found and signed again.
- Sources rows have a visible options button (and work with VoiceOver); screen headers no longer clip at large text sizes; an identity that needs attention shows a red tag.
- The on-device self-test app (`WaxProbe.ipa`) is now part of the repository.
- Contributor files, issue and PR templates, more tests in CI.

## 0.14.0
- Install host "This iPhone" (experimental): Wax serves the app to iOS from the phone itself. No server, bucket or account of yours.
- "My server" and "Bucket" (experimental) install hosts.
- Hardened certificate feed; the listener closes once iOS has the whole file; honest failure messages.
- Bundle ID is now `io.github.dylldev.wax`.
