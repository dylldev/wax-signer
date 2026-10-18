# Wax: iOS IPA signer and installer for iPhone

[![CI](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml/badge.svg)](https://github.com/dylldev/wax-signer/actions/workflows/ci.yml)

Wax is a free, open-source (Apache-2.0) iPhone app that inspects IPA files, signs them with **your own** certificate and
provisioning profile, and installs them on the same iPhone. Wax itself charges nothing, shows no ads, has no tracking and
needs no server that you operate and no Mac.

## Before you start
Wax does not provide signing material. You need a `.p12` certificate and a `.mobileprovision` profile that you are
entitled to use and that include this iPhone's UDID (for example from an Apple Developer account). Distribution (Ad Hoc) certificates installed over the air in testing. A Development certificate installed in one test
and failed in an earlier one, so treat it as less certain; the profile must list the device either way.

## What it does
- **Sign on the phone** with your own `.p12` and `.mobileprovision` (kept in the iPhone Keychain, this device only).
- **Install** the signed app with `itms-services`, from one of three places. All are free:
  - **This iPhone** (default, experimental): Wax serves the app to iOS from the phone itself, using a free certificate for a name that points at `127.0.0.1`. No server of yours, no bucket, no account. It does depend on three free public services staying up: GitHub Pages (certificate file), DuckDNS (the name) and Let's Encrypt (the certificate). iOS shows that name in the install prompt.
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
Server and script tests: `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'`, `bash scripts/test_make_install_cert.sh`.

## Security
See [`SECURITY.md`](SECURITY.md). Report problems privately through GitHub's "Report a vulnerability".

## Running the "This iPhone" certificate job (maintainers)
`.github/workflows/renew-install-cert.yml` renews the shared certificate and publishes it on GitHub Pages. In your fork set
Pages source to GitHub Actions, the variable `INSTALL_DOMAIN` (a free DuckDNS name pointing at `127.0.0.1`) and the secret
`DUCKDNS_TOKEN`. Then set both `LoopbackConfig.defaultFeed` (your Pages URL) and `LoopbackConfig.officialNames` (your domain) in
`Sources/InstallKit/CertificateFeed.swift`; the app refuses any other name from the official feed.
GitHub switches off scheduled workflows after 60 days without repository activity. Push any commit now and then, or re-enable
the workflow in the Actions tab. Phones keep working meanwhile: they hold a certificate that still has weeks left.

## License
Apache-2.0. See `LICENSE`, `NOTICE` and `THIRD_PARTY_NOTICES.md`.
