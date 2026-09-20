#!/bin/bash
# Builds TouchGuard.app into ./build.
# A stable code signature matters here: macOS ties the Accessibility grant to the
# signature, so an ad-hoc rebuild would make you re-approve the app every time.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/TouchGuard.app"

swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/TouchGuard "$APP/Contents/MacOS/TouchGuard"
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
