#!/bin/bash
# Builds the release archive for the version in Resources/Info.plist.
#
# The archive is made with ditto, not zip: the in-app updater verifies the
# downloaded bundle against this app's designated requirement, and only ditto
# round-trips a signed bundle's symlinks and metadata faithfully enough for
# that check to pass. A zip(1) archive would ship ._ AppleDouble stubs and
# fail verification on the user's machine.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
ZIP="build/TouchGuard-$VERSION.zip"

./build.sh

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/TouchGuard.app "$ZIP"

# Unpack into a scratch copy and re-verify it exactly as the updater will,
# so a broken archive is caught here rather than on someone's machine.
REQUIREMENT=$(codesign -d -r- build/TouchGuard.app 2>/dev/null | sed -n 's/^designated => //p')
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict --all-architectures \
  -R="$REQUIREMENT" "$CHECK/TouchGuard.app"

echo
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1)), signature verifies against:"
echo "  $REQUIREMENT"
echo
echo "To publish:"
echo "  git tag -a $TAG -m 'TouchGuard $VERSION' && git push origin main $TAG"
echo "  gh release create $TAG $ZIP --title 'TouchGuard $VERSION' --notes-file <notes>"
