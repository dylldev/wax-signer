# Wax: iOS IPA signer and installer for iPhone

[![CI](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml/badge.svg)](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml)

Wax is a free, open-source (Apache-2.0) iPhone app that inspects IPA files, signs them with **your own** certificate and
provisioning profile, and installs them on the same iPhone. Wax itself charges nothing, shows no ads, has no tracking and
needs no server that you operate and no Mac.

## Downloads

Choose the standard **Wax-<version>.ipa** from the [latest release](https://github.com/dylldev/wax-signer/releases/latest) for everyday signing and installation. It includes saved apps and sources. Optional app edits sit under Options; additional edits are collapsed under More options.

**Wax-Dev-<version>.ipa** is the developer build. It retains the built-in test app, import logs, compression tuning and technical signing controls. Look for that asset on the [release downloads page](https://github.com/dylldev/wax-signer/releases) when a developer build is published. Both downloads are unsigned.

Wax Dev has its own app identity and appears as **Wax Dev** on your home screen, so it can sit beside Wax. Its files and settings are separate: import your signing files into each app you use. Installing Wax Dev does not transfer or repair another copy's credentials.

## Before you start
Wax does not provide signing material. You need a `.p12` certificate and a `.mobileprovision` profile that you are
entitled to use and that include this iPhone's UDID (for example from an Apple Developer account). Signing with a
Distribution (Ad Hoc) certificate has installed over the air in a device test. A Development certificate signed in
one test but failed to install in an earlier one, so treat it as less certain; the profile must list the device either way.

## Your first install

Have your `.p12` or `.pfx` certificate, its password, a matching `.mobileprovision` profile, and an IPA you are entitled to install ready in Files. Wax does not issue certificates or provide apps.

1. **Install Wax.** Download the IPA from the [latest release](https://github.com/dylldev/wax-signer/releases/latest) and sideload it with the signer you already use. The download is unsigned; opening it in Files does not install it.
2. **Import both signing files.** Open Wax, go to **Settings → Certificates & profiles**, and choose **Import a certificate**. Pick your `.p12` or `.pfx` and enter its password. Then choose **Import a provisioning profile** and pick the matching `.mobileprovision` file.
3. **Choose an app.** Return to **Sign**, tap **Choose an app**, and pick your IPA. Tap the signing identity row and choose the certificate you imported.
4. **Check the install host.** Use **This iPhone** for an on-phone install. If the host needs setup, open **Settings → Install host**. Official releases include a default certificate feed; a build without one needs its own feed or another host. [Host setup and limits](#what-it-does) explains the choices.
5. **Sign and install.** Tap **Sign & Install**, review Wax's checks, then tap **Continue to install** if the checks allow it. Accept the iOS install prompt and keep Wax on screen while iOS takes the file. Open the installed app to confirm it works; Wax handing the file to iOS does not confirm installation or launch.

If installation stops, keep your original IPA. Export any signed copy Wax retained, or retry delivery if an install action is available. You do not need to delete your signing files to retry.

### Where did you get stuck?

[Open a first-install report](https://github.com/dylldev/wax-signer/issues/new?template=bug_report.md&title=First%20install%3A%20) with the step number above, the exact error, your Wax version, and your iPhone model/iOS version. A cancelled prompt or an app that will not launch is useful feedback too. Do not attach certificates, profiles, passwords, tokens, or private IPA files.

## What it does
- **Sign on the phone** with your own `.p12` and `.mobileprovision`. The certificate and its private key are kept in the iPhone Keychain, this device only; the profile is stored in app-private storage, excluded from iCloud backups.
- **Install** the signed app with `itms-services`, from one of three places. All are free:
  - **This iPhone** (default, experimental): Wax serves the app to iOS from the phone itself, using a certificate for a name that points at `127.0.0.1`. No server of yours, no bucket, no account. This repository ships no official feed: the owner builds the app with `WAX_DEFAULT_FEED` (the published certificate file) and `WAX_INSTALL_DOMAIN` (the name it may publish), and anyone else points Settings at a feed of their own choice, which Wax then chain-checks. The feed's two free public services (wherever `cert.json` sits — for this project GitHub Pages — and Let's Encrypt) need to stay up for renewals. iOS shows the certificate's name in the install prompt.
  - **My server**: any small HTTPS server you run. `Server/wax-ota/install.sh` sets one up on a fresh Ubuntu VPS (Oracle Always Free works).
  - **Bucket** (experimental): any S3-compatible bucket you own. Tested only against the AWS signing examples, not yet against a real provider.
- **Sources**: add AltStore/Feather-style source links, or a direct IPA link, and download apps to sign. Wax ships with no sources and does not choose what you load.
- Signing options: bundle ID, name, version, icon, entitlements, per-app profile, plist edits, library injection (`.dylib`, `.deb`), and more.

## Honest limits
- Wax signs what you give it. It cannot tell you whether an app is safe, and you are responsible for what you load.
- Apps signed with a free developer account expire after 7 days; paid and ad hoc profiles last longer.
- "This iPhone" relies on a shared public certificate key; read [`SECURITY.md`](SECURITY.md) for what that means. If the certificate is revoked or the maintainer's job stops, use the other hosts or Export the signed IPA until it is fixed.
- If the install prompt never fetches the app, some networks rewrite DNS answers for the install name; switch network or host.
- Verified so far on one iPhone 17 (iOS 27.2). Other devices and iOS versions are untested.

## Build
```bash
brew install xcodegen
xcodegen generate
swift test                       # package tests
xcodebuild -scheme LocalIPASigner -destination 'generic/platform=iOS Simulator' build
```
Server and script tests: `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`, `bash scripts/test_make_install_cert.sh`, `bash scripts/test_publish_prep.sh`.

## Building a release
The official install feed is not stored in the source. A release build injects it:
```bash
WAX_DEFAULT_FEED=https://<you>.github.io/<repo>/cert.json WAX_INSTALL_DOMAIN=<name>.duckdns.org scripts/build-release-ipa.sh dist
```
This builds the standard app and writes an unsigned `Wax-<version>.ipa` and its `.sha256`. It excludes the bundled probe and developer UI. To build Wax Dev instead, add `dev`:
```bash
WAX_DEFAULT_FEED=https://<you>.github.io/<repo>/cert.json WAX_INSTALL_DOMAIN=<name>.duckdns.org scripts/build-release-ipa.sh dist dev
```
This writes `Wax-Dev-<version>.ipa` and its `.sha256`. In Xcode, choose the `WaxDev` scheme, which uses the `Development` configuration. App-hosted test schemes also use this configuration to exercise the developer tools.

Without the two variables the build has no official feed and
"This iPhone" needs a feed address typed in Settings.

## Security
See [`SECURITY.md`](SECURITY.md). Report problems privately through GitHub's "Report a vulnerability".

## Running the "This iPhone" certificate job (maintainers)
`.github/workflows/renew-install-cert.yml` renews the shared certificate and publishes it on GitHub Pages. In your fork set
Pages source to GitHub Actions, the variable `INSTALL_DOMAIN` (a free DuckDNS name pointing at `127.0.0.1`), the variable
`CERT_FEED_URL` (the Pages URL where `cert.json` is served), and the secret `DUCKDNS_TOKEN`. The feed URL is read from that
variable — not derived from the repository path — so a fork or rename cannot make a job renew a feed it does not own.
Build the app with the same two facts injected: `xcodebuild ... WAX_INSTALL_DOMAIN='<your duckdns name>' WAX_DEFAULT_FEED='<your pages url>'`
(the app then refuses any other name from the official feed), or ship without them and use your own host's feed string in
Settings; phones keep a certificate that still has weeks left.
GitHub switches off scheduled workflows after 60 days without repository activity. Push any commit now and then, or re-enable
the workflow in the Actions tab. Phones keep working meanwhile: they hold a certificate that still has weeks left.

## License
Apache-2.0. See `LICENSE`, `NOTICE` and `THIRD_PARTY_NOTICES.md`.
