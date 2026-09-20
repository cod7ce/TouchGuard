#!/bin/bash
# Builds TouchGuard.app into ./build.
# A stable code signature matters here: macOS ties the Accessibility grant to the
# signature, so an ad-hoc rebuild would make you re-approve the app every time.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/TouchGuard.app"

BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
swift build "${BUILD_FLAGS[@]}"

# Ask SwiftPM where it put the product rather than hardcoding a path: the
# output directory has moved between toolchains, and a stale copy left behind
# by an older one will happily be picked up and shipped.
PRODUCT="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/TouchGuard"
NEWEST_SOURCE=$(find Sources -name '*.swift' -newer "$PRODUCT" -print -quit)
if [ -n "$NEWEST_SOURCE" ]; then
  echo "Build product is older than $NEWEST_SOURCE - refusing to package a stale binary." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCT" "$APP/Contents/MacOS/TouchGuard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
  echo "No signing identity found, falling back to ad-hoc (permissions will reset on each build)."
  IDENTITY="-"
fi

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP  (signed with: $IDENTITY)"
