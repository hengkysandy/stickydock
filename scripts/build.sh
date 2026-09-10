#!/bin/bash
# Builds StickyDock.app.
#
# Signed with a real Apple Development certificate, never ad-hoc. macOS keys the
# TCC Automation grant ("StickyDock wants to control Notes") to the code
# signature, and an ad-hoc signature gets a new hash on every build, so ad-hoc
# would re-prompt every single time. A stable certificate means one approval.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/StickyDock.app"
CONFIG="${CONFIG:-release}"
IDENTITY="${STICKYDOCK_IDENTITY:-Apple Development: <your Apple ID> (<team>)}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product StickyDock

BIN="$(swift build -c "$CONFIG" --product StickyDock --show-bin-path)/StickyDock"
[ -f "$BIN" ] || { echo "no binary at $BIN"; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StickyDock"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi

echo "==> codesign"
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  codesign --force --options runtime --timestamp=none \
           --sign "$IDENTITY" "$APP"
else
  echo "!! identity not found, falling back to ad-hoc."
  echo "!! macOS will re-ask for Automation permission after every build."
  codesign --force --sign - "$APP"
fi

codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Authority|Signature' || true
echo "==> built $APP"
