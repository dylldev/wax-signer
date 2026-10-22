#!/bin/sh
# Builds the tiny test app UNSIGNED for a physical device, under a bundle identifier you choose.
# usage: Prototype/build-minimal-app.sh <bundle-id> <output-dir>
# The bundle identifier must be one your Apple team can use (a registered explicit App ID).
set -eu
BUNDLE_ID="${1:?bundle id}"
OUT="${2:?output dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
cp -R "$HERE/MinimalApp/." "$WORK/"
( cd "$WORK" && xcodegen generate >/dev/null && \
  xcodebuild -project MinimalApp.xcodeproj -scheme MinimalApp -sdk iphoneos -configuration Release \
    -derivedDataPath "$WORK/dd" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGNING_ALLOWED=NO build >/dev/null )
mkdir -p "$OUT/Payload"
rm -rf "$OUT/Payload/MinimalApp.app"
cp -R "$WORK/dd/Build/Products/Release-iphoneos/MinimalApp.app" "$OUT/Payload/"
( cd "$OUT" && rm -f MinimalApp-unsigned.ipa && zip -q -r -y MinimalApp-unsigned.ipa Payload )
rm -rf "$WORK"
echo "unsigned app: $OUT/Payload/MinimalApp.app"
echo "unsigned ipa: $OUT/MinimalApp-unsigned.ipa"
codesign -dv "$OUT/Payload/MinimalApp.app" 2>&1 | tail -1
