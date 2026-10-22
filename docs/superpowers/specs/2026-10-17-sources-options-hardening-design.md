# Sources, more signing options, install robustness, safe to open-source (design)

Status: draft for review, 2026-10-17. Decisions come from a grilling session with the owner (answers quoted where they set scope).

## Intent
Wax is a free, open-source, iPhone-only signer. the owner wants to (1) grab IPAs quickly from sources he adds, (2) have the signing options ESign and Feather have, (3) have signing and installing fail less, and (4) publish the code without exposing his server or personal data, while letting anyone with their own server (for example Oracle's free tier) use it.

Success: a stranger can clone the repo, deploy the server template on their own VPS with one command, paste one setup line into Wax, add a source, tap Get, then Sign, and install; and nothing in the repo or history points at the owner's server or credentials.

## Already done
Credentials moved into Settings. Tapping the tab you are on returns to its first screen and scrolls to the top. IPA shelves (Unsigned, Signed). Settings tab. Candle animation. Background signing works (verified on device).

## 1. Sources tab (leftmost tab; tabs become Sources, IPA, Sign, Settings)
- the owner: "allow adding sources but dont build any in". Wax ships with NO sources, built in or suggested. Empty state: "Add a source" with a paste field, and a one-line note that the user is responsible for what they load.
- Source formats: AltStore/Feather JSON, both layouts (apps[].versions[] and the older app-level downloadURL/version). Also a pasted direct link to one IPA.
- Large sources (one real repo is 17 MB, 6,400 apps): parse off the main thread, keep a compact on-disk cache (name, bundle ID, icon URL, latest version, size, download URL), show a spinner only on first load, refresh in the background.
- Per source: name, last updated, app count, remove. List with search. App page: icon, name, version, size, description, Get.
- Get: downloads with progress (URLSession, survives leaving the app), then files into the Unsigned shelf. Setting "Sign right after download" (off by default) then opens Sign with that app chosen.
- Some links carry expiring tokens: on 401/403 refetch the source once and retry.
- Saved sources live in the app's own storage, never in the repo.

## 2. Signing options (the ESign and Feather union, minus what does not fit)
Easy (Info.plist only): appearance (light, dark, system), game mode, iPad full screen, remove the device restriction, custom Info.plist key editor (add, change, delete), Files-app support (exists), high frame rate (exists), remove URL schemes/extensions/Watch (exist), minimum iOS (exists).
Medium: change the app icon, custom entitlements file, choose the profile for this app instead of automatic, compression level (speed, balanced, size), re-sign reminder (two ESign options, "remove the profile after signing" and "modify only, no signing", are dropped: their output cannot install) before a profile expires (local notification).
Hard: inject libraries (.dylib, .framework, .deb) into an app (copy into the app, add a load command, sign them), remove existing libraries; later, fix jailbreak dependencies once the helper library's license is verified.
All new switches that suit every app can be saved as defaults, like the current ones.

## 3. Install robustness (from the space-bunny audit, each checked against the code)
1. Signer ignores profile kind: never pick an App Store profile; prefer profiles that include this phone.
2. A .p12 with several identities is rejected: import each identity as its own certificate.
3. Fat (arm64+arm64e) Mach-O files abort the whole signing: keep the arm64 slice (else arm64e) and drop the others, which an iPhone never uses.
4. One extension with an unusual ID can discard a finished signing: try the full suffix, then shorter, then keep the ID.
5. After uploading, GET the public manifest link and fail with a clear message if it is not reachable; test the token with a tiny authenticated request when the server is set up.
6. Pass the .p12's own intermediate certificates into the signature (unverified need; check with a reseller p12).
7. (deepseek) The app accepts tokens of 16+ characters but the server needs 32+: enforce 32+ in the app.
8. (deepseek) Keychain items are "when unlocked": a locked phone breaks a background upload or signing. Move the token and the signing key to "after first unlock, this device only".
9. (deepseek) After signing, plan() must prove every final bundle ID is unique across the main app, extensions, editor renames and prior renames; fail with the list.
10. (deepseek) The install manifest's bundle-version uses the marketing version; use the build number.
11. (deepseek) Server TTL 20 minutes means tapping "Ready to install" later hits a 404: raise to 6 hours (files are served by Caddy, so there is no refresh-on-download).
12. (deepseek) Signing deletes the previous output before the new one is in place; move first, delete after. The "signed IPA already installable" upload path skips the guard against replacing the running Wax.
Not doing: UIBackgroundModes (disproved on device).

## 4. Install speed
In order: overlap uploading with packing; skip re-uploading an IPA the server already has (hash); then a 30-minute spike on a real domain pointing at 127.0.0.1 (could remove the upload entirely; untested, expected to fail).

## 5. Safe to open-source, usable with any server
Repo scrub before publishing: remove the server address from Tests/InstallKitTests/OTATests.swift (use example.test); remove team ID and personal bundle IDs from docs and tests; publish from a fresh squashed history because the address appears in an old commit; add SECURITY.md. Already clean: no tokens, keys, .p12 files, passwords, or phone IDs in files or history; the app has no built-in server (it is entered by the user and the token lives in the Keychain).
Server template for anyone: `Server/wax-ota/install.sh` for a fresh Ubuntu VPS: installs Caddy and the upload service, generates a token, opens only ports 22/80/443, enables fail2ban and a firewall, exposes only /ota-up and /ota, prints the one-line `WAXINSTALL1 <https url> <token>` to paste into Wax. README covers Oracle Always Free. The service gains failed-login throttling (per IP lockout), keeps loopback-only binding, 32+ char tokens, TTL, quotas.
the owner's own server (needs his approval, listed separately): close public rpcbind (111) and bark (2588) unless wanted, turn on the firewall and fail2ban, remove the stale /control and catch-all Caddy routes.

## 6. Install without a server of your own
Fact: iOS only installs from an HTTPS address with a trusted certificate that is not this phone, so some HTTPS host must serve two files (manifest, IPA). It does not need to run code.
Plan, in this order:
1. The domain-to-127.0.0.1 spike (section 4). If it works, nobody needs any host. Expected to fail.
2. A second install backend: any S3-compatible bucket (Cloudflare R2, Backblaze B2, Oracle Object Storage, MinIO). Wax uploads with the user's access keys (kept in the Keychain), keeps the bucket private, and hands iOS short-lived signed links, so nothing is public and links expire. No server to run or patch. Setup is a paste of endpoint, bucket and keys. Free tiers exist; some providers ask for a card at sign-up (unverified per provider).
3. Always available: export the signed IPA and install it any other way.
Not doing: a shared server run by the project (cost, liability, privacy).

## 6b. Everything stays free (the owner: "make sure its all free")
- Wax and the server template use no paid service, API or dependency. Apache-2.0 code only (the signing and injection code is our own; any helper library is added only after its license is checked).
- Free tiers named for the cloud-bucket option (from third-party summaries, not verified on each provider's own site): Cloudflare R2 10 GB with free downloads; Backblaze B2 10 GB with limited free downloads; Oracle Object Storage Always Free (10-20 GB, about 50,000 requests a month). Several ask for a card at sign-up to verify identity and do not charge inside the free amount; the setup screen says this plainly and never claims "no card".
- To stay under the caps, uploads are short-lived: Wax deletes the uploaded files after the install window (6 hours) and the setup guide has the user add a one-day expiry rule on the bucket as a backstop. Typical use (an IPA at a time) stays far below 10 GB.
- The VPS route stays free on Oracle Always Free. Sources need no host (they are public links the user adds).

## 7. Done on the owner's server (2026-10-17, approved)
Backed up Caddy config, firewall rules and the Bark unit (`/home/ubuntu/hardening-backup-20261017`). Bark moved behind HTTPS on a secret path and now listens on loopback only; its public port is closed. Removed stale firewall rules (8081, 8082, 2588) and persisted the firewall; disabled rpcbind; installed fail2ban (sshd jail); removed dead web routes (`/control`, `/signed`, catch-all now 404). SSH was already key-only. The Mac notifier was repointed and its tests updated.

## 8. Declined, and kept but not extended (2026-10-18)

A full-codebase review on 2026-10-18 found three items from sections 2 and 4 that were specified but never built. They were reviewed rather than quietly dropped.

**Declined, not implemented:**

- *Remove existing libraries* (section 2, "Hard"). `LibraryInjector` only injects. Removing a library means stripping its load command and deleting the binary, and getting either wrong leaves an app that crashes on launch with no way back. Not wanted for the cost.
- *Overlap uploading with packing* (section 4). Packing must finish before there is anything to upload, and doing both at once doubles peak memory on a phone. The upload is short-lived and the link survives 6 hours, so the saving does not pay for the complexity.
- *Compression level (speed, balanced, size)* (section 2). `IPAArchiver.deflate` uses `COMPRESSION_ZLIB`. Exposing a knob means shipping three code paths that differ only in one constant, with no measured user benefit — a phone signs an IPA in seconds either way.

**Kept, deliberately not to be extended:**

- *WaxProbe self-install* (`App/IdentityReadiness.swift:70-120`, bundle resource `App/Resources/WaxProbe.ipa`). Wax signs and installs a tiny probe IPA onto itself to prove the signing identity and install path work before the user signs anything real. It was never asked for, but it is the difference between "Wax says it is ready" and "Wax has been proven on this phone". Keeping it as-is; the probe is not a general self-install feature and must not grow into one.
- *`Source/make_source.py`* (`Source/`, with `test_make_source.py` and `validate_source.py`). The owner's ruling when sources were added was "allow adding sources but don't build any in". This is the tool for authoring one by hand; Wax ships with none. It stays as a developer tool and is not a seed list, a default shelf, or a source the app falls back to.

## Out of scope
Built-in sources of any kind, iCloud sync of the shelves, App Store profiles, a Mac companion.

## Checks
Unit tests for: both source formats, cache, expired-link retry, each option's plist/entitlement effect, profile-kind guard, multi-identity import, fat binary signing (fixture), ID fallback, link check, throttling. Device checks: Get then Sign then install from a real source; a dylib-injected app launches; audits re-run (Codex, space-bunny, deepseek) after building.
