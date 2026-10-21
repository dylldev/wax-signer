# Changelog

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
