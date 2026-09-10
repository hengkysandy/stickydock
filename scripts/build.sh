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
# Whichever Apple Development certificate is in the keychain. Override with
# STICKYDOCK_IDENTITY to pick a specific one. Deliberately not hardcoded: the
# certificate name contains the owner's Apple ID email address.
IDENTITY="${STICKYDOCK_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development/ { print $2; exit }')}"

# Universal by default. An arm64-only build does not merely warn on an Intel
# Mac, it fails to launch, sometimes with no dialog at all, which looks exactly
# like the app being broken. Set STICKYDOCK_ARCHS="arm64" for a faster local
# build when you only care about this machine.
ARCHS="${STICKYDOCK_ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done

echo "==> swift build -c $CONFIG (${ARCHS})"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product StickyDock

BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product StickyDock --show-bin-path)/StickyDock"
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

# SPM emits each target's resources as a separate .bundle next to the binary.
# Bundle.module finds them through Bundle.main.resourceURL, which is
# Contents/Resources, so they have to be copied in. Forgetting this produces an
# app that builds, launches, looks fine, and never syncs, because the Notes
# bridge script is not there. Hence the hard check below.
BINDIR="$(dirname "$BIN")"
for bundle in "$BINDIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Searched, not hardcoded: a plain `swift build` emits a flat resource bundle
# while a multi-arch build emits a proper Contents/Resources layout. Bundle.module
# reads both, so the check has to look in both.
if ! find "$APP/Contents/Resources" -name notes_bridge.js -print -quit | grep -q .; then
  echo "FAILED: the Notes bridge script is not in the app bundle."
  echo "        without it StickyDock launches but never syncs."
  exit 1
fi
echo "==> bridge script present"

echo "==> codesign"
if [ -n "$IDENTITY" ] && security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  codesign --force --options runtime --timestamp=none \
           --sign "$IDENTITY" "$APP"
else
  echo "!! no Apple Development certificate found, falling back to ad-hoc."
  echo "!! macOS will re-ask for Automation permission after every build."
  codesign --force --sign - "$APP"
fi

codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Authority|Signature' || true
echo "==> architectures: $(lipo -info "$APP/Contents/MacOS/StickyDock" | sed 's/^.*: //')"
echo "==> built $APP"
