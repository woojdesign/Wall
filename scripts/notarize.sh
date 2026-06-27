#!/bin/sh
# notarize.sh — submit Wall.app to Apple notarization and staple the ticket.
#
# Requires the 'wall-notary' notarytool keychain profile (set up once via
# `xcrun notarytool store-credentials wall-notary --apple-id <email> --team-id BSPX8X9U4B`).
#
# Notarization is separate from build-app.sh because it takes 1–15 minutes —
# you don't want that in your dev iteration loop. Run this when you're ready
# to install the latest build for a real session.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Wall.app"
PROFILE="wall-notary"

if [ ! -d "$APP" ]; then
    echo "✗ $APP not found — run scripts/build-app.sh first"
    exit 1
fi

ZIP="$ROOT/build/Wall-notarize.zip"
rm -f "$ZIP"

echo "→ packaging $APP for submission…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ submitting to Apple (typically 1–10 minutes, blocks until done)…"
SUBMIT_OUT=$(xcrun notarytool submit "$ZIP" \
    --keychain-profile "$PROFILE" \
    --wait 2>&1)
echo "$SUBMIT_OUT"

STATUS=$(echo "$SUBMIT_OUT" | grep -E "^[[:space:]]*status:" | tail -1 | awk -F': *' '{print $2}')
ID=$(echo "$SUBMIT_OUT" | grep -E "^[[:space:]]*id:" | head -1 | awk -F': *' '{print $2}')

if [ "$STATUS" != "Accepted" ]; then
    echo
    echo "✗ Notarization status: $STATUS"
    if [ -n "$ID" ]; then
        echo "  Fetching log for submission $ID …"
        xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>&1
    fi
    rm -f "$ZIP"
    exit 1
fi

echo
echo "→ stapling ticket to $APP …"
xcrun stapler staple "$APP"

rm -f "$ZIP"

# Produce the Sparkle update artifact: a zip of the *stapled* app, named
# Wall-<version>-<build>.zip. Sparkle ships updates as zips (not DMGs), and
# zipping after stapling means the downloaded update carries its own
# notarization ticket — so it passes Gatekeeper even offline. release.sh
# feeds this exact file to generate_appcast.
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
ARTIFACT="$ROOT/build/Wall-$VERSION-$BUILD.zip"
rm -f "$ARTIFACT"
ditto -c -k --keepParent "$APP" "$ARTIFACT"

echo
echo "✓ Notarized and stapled."
echo "  Update artifact: $ARTIFACT"
echo "  Verify with:  spctl --assess --type execute --verbose $APP"
echo "  Install:      cp -R $APP /Applications/   (quit running Wall first)"
