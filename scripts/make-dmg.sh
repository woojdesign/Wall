#!/bin/sh
# make-dmg.sh — package Wall.app into a drag-install DMG for end users.
#
# This is the real distribution artifact. The user opens Wall.dmg, drags
# Wall.app onto the Applications shortcut, launches it, and approves the
# background helper once in System Settings. No terminal, ever.
#
# Order of operations for a release:
#   1. scripts/build-app.sh      (build + Developer ID sign)
#   2. scripts/notarize.sh       (notarize + staple the .app)
#   3. scripts/make-dmg.sh       (this — wrap the stapled app in a DMG)
#   4. (optional) notarize + staple the DMG itself, below.
#
# The app MUST be notarized+stapled before this runs: a DMG only carries
# whatever ticket is already stapled into the app inside it.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Wall.app"
DMG="$ROOT/build/Wall.dmg"
STAGE="$ROOT/build/dmg-stage"
VOLNAME="Wall"
SIGN_ID="Developer ID Application: Sean Kim (BSPX8X9U4B)"

if [ ! -d "$APP" ]; then
    echo "✗ $APP not found — run scripts/build-app.sh first"
    exit 1
fi

# Warn (don't fail) if the app isn't stapled — useful for dev DMGs, but a
# real release should be notarized so Gatekeeper opens it without warnings.
if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "⚠ $APP is not notarized/stapled — run scripts/notarize.sh for a release build."
fi

echo "→ staging…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Wall.app"
ln -s /Applications "$STAGE/Applications"

echo "→ building compressed DMG…"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"

# Sign the DMG so its own seal is Developer ID (the app inside keeps its
# own signature + stapled ticket). Skips cleanly if the identity is absent.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "→ signing DMG…"
    codesign --sign "$SIGN_ID" --timestamp "$DMG"
fi

echo
echo "✓ Built $DMG"
echo
echo "  For a release, notarize + staple the DMG too:"
echo "    xcrun notarytool submit $DMG --keychain-profile wall-notary --wait"
echo "    xcrun stapler staple $DMG"
echo
echo "  Verify the app inside opens clean:"
echo "    spctl --assess --type open --context context:primary-signature -v $DMG"
