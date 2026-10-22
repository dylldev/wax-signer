#!/usr/bin/env bash
# Builds the unsigned release IPA and its SHA-256, with the official install feed injected (it is not stored in the source).
#   WAX_DEFAULT_FEED=https://you.github.io/repo/cert.json WAX_INSTALL_DOMAIN=name.duckdns.org scripts/build-release-ipa.sh <output-dir>
# Leave both variables unset for a build with no official feed (every feed is then chosen by the person).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: build-release-ipa.sh <output-dir>}"
FEED="${WAX_DEFAULT_FEED:-}"; DOMAIN="${WAX_INSTALL_DOMAIN:-}"
if [ -n "$FEED" ] && [ -z "$DOMAIN" ]; then echo "error: WAX_DEFAULT_FEED needs WAX_INSTALL_DOMAIN too (the names the feed may publish)" >&2; exit 1; fi
command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
xcodegen generate >/dev/null
xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$work/derived" CODE_SIGNING_ALLOWED=NO WAX_DEFAULT_FEED="$FEED" WAX_INSTALL_DOMAIN="$DOMAIN" build >"$work/build.log" 2>&1 \
  || { tail -20 "$work/build.log" >&2; exit 1; }
app="$work/derived/Build/Products/Release-iphoneos/LocalIPASigner.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")"
if [ -n "$FEED" ]; then   # the feed must really be inside the build
  [ "$(/usr/libexec/PlistBuddy -c 'Print WAX_DEFAULT_FEED' "$app/Info.plist")" = "$FEED" ] || { echo "error: the feed did not reach the build" >&2; exit 1; }
fi
mkdir -p "$work/Payload" "$OUT"; cp -R "$app" "$work/Payload/"
(cd "$work" && zip -qry "Wax-$version.ipa" Payload)
mv "$work/Wax-$version.ipa" "$OUT/"
(cd "$OUT" && shasum -a 256 "Wax-$version.ipa" > "Wax-$version.ipa.sha256" && cat "Wax-$version.ipa.sha256")
