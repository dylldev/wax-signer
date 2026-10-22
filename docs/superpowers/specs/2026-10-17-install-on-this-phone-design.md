# Install on this phone: no server, no bucket, no account (design, draft for review)

Status: draft 2026-10-17. Builds on the verified spike `2026-10-17-loopback-domain-spike.md`.

## Intent
Anyone with Wax can sign an app and install it with nothing else: no VPS, no bucket, no card. Wax serves the manifest and
the IPA to iOS from the phone itself, over HTTPS, using a name that points at 127.0.0.1. Everything it relies on is free.

Success: on a fresh Wax install (no install host configured), Sign & Install signs, shows the iOS prompt, and the app
installs; Settings shows "This iPhone" as the default install host with nothing to fill in.

## What was proven
iOS 27.2 fetched the manifest and the IPA from an app listening on `https://<name>:8443` where `<name>` resolves to
127.0.0.1, trusted a Let's Encrypt certificate for it, and installed the app. Not proven: a large IPA, a long
download, the real Wax app as the server, and certificate refresh.

## Design
1. **Name.** One project-owned free name, for example `wax-install.duckdns.org` -> 127.0.0.1 (DuckDNS, free). It can
   only ever point at the phone it is opened on, so it exposes nothing and cannot reach anyone's server.
2. **Certificate.** Let's Encrypt, 90-day, issued by a scheduled GitHub Actions job (free) with the DNS challenge
   (DuckDNS token stored as an Actions secret). The job publishes `cert.json` (certificate chain + private key + expiry)
   on GitHub Pages (free), checked daily and renewed when under 30 days remain.
3. **Wax downloads `cert.json`** when needed (first install, or when the cached one expires within 7 days), checks
   it parses and matches the name, and keeps it in the app's storage. It refuses an expired certificate.
4. **Serving.** For each install Wax starts a small HTTPS listener on loopback (`NWListener`, TLS identity from
   `cert.json`) on a random free port, serves `/<random id>/manifest.plist` and `/<random id>/app.ipa` (supports `HEAD`
   and `Range`), opens the `itms-services://` link, and stops the listener when the download ends or after a time limit.
   Only loopback is bound; nothing is reachable from the network.
5. **Staying alive.** iOS downloads while Wax is in the background. Wax holds a `BGContinuedProcessingTask` (already
   used for signing) for the duration; a short IPA fits in the normal 30 s background window.
6. **Fallbacks.** If the certificate cannot be fetched, is revoked, or the listener fails, Wax says so and offers the
   other hosts (own server, cloud bucket) or Export. "This iPhone" is the default; the other two stay as options.
7. **Settings.** Install host: This iPhone (default), My server, Cloud bucket.

## Risks, said plainly
- The private key is public by design (it is in `cert.json`). Let's Encrypt can revoke a certificate whose key is
  reported as compromised. If that happens every Wax is without this host until the job issues a new certificate
  with a new key (hours to days). The fallbacks above are the answer, and the job should rotate keys each issue.
- The key's only use is this name, which points at the phone itself, so a stolen key cannot impersonate a real site.
  Someone on the same phone could in theory serve different content for the name; they would already control the phone.
- DuckDNS and GitHub are free today and could change; the design keeps the name and the file in the project's own
  accounts so they can be moved.
- Apple could change how `itms-services` treats loopback in a future iOS. Fallbacks cover it.

- **Spoofed DNS on a hostile network.** Because the key is public, a network that answers DNS for the name with its own
  address could serve its own manifest and IPA with a valid certificate. Defences: Wax refuses to publish unless the
  name resolves only to loopback on the phone's own resolver (checked right before each install); the install link
  carries a random per-install path; and `LoopbackHost.servedIPA` tells Wax whether iOS really fetched the IPA from the
  phone (a rebinding trick after the check would leave it false). iOS also still shows its own install prompt and
  requires a valid signature for this device. This does not remove the risk of a targeted attacker who controls the
  network and answers the check honestly once; the fallbacks (own server, bucket) have no such exposure.

## Needs from the owner (accounts only he can create)
1. A new DuckDNS name (the test name `<name>` was exposed in chat; regenerate its token or delete it).
2. A public GitHub repository for Wax (for Pages and Actions), and the DuckDNS token added as an Actions secret
   (typed by the owner on github.com, never pasted in chat).

## Plan (after approval)
- H1: `Sources/InstallKit/LoopbackHost` (listener, TLS identity from PEM/PKCS#12, routes, Range, stop rules) with
  tests against a local TLS client using a throwaway certificate.
- H2: `InstallHost` conformance, certificate fetch/cache/expiry (`CertificateFeed`), tests with a stub feed.
- H3: Settings default host and the fallback messages; simulator check.
- H4: Actions workflow + Pages file (scripts under `.github/`), dry-run locally; real issue needs the two items above.
- H5: device check: install a small app and a large one (the 320 MB test IPA) from "This iPhone".
