#!/bin/bash
# Builds StickyDock.app and wraps it in a .dmg for the Releases page.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
OUT="build/StickyDock-$VERSION.dmg"
STAGE="build/dmg"

./scripts/build.sh

rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R build/StickyDock.app "$STAGE/"
# The usual drag-to-install layout.
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "StickyDock" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"
echo "==> $OUT  ($(du -h "$OUT" | cut -f1))"
