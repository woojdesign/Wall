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

# Notary auth. Prefer the App Store Connect API key (a .p8 *file*) over the
# keychain profile: the keychain notary item kept vanishing on this machine
# (while the Developer ID cert + Sparkle key persisted), and a file doesn't.
# Shared with StickySync. Values default to the active key; ASC_* env overrides.
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_R2874DGSGN.p8}"
ASC_KEY_ID="${ASC_KEY_ID:-R2874DGSGN}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-aaea5e06-a424-4055-81b4-49f47d252adb}"
if [ -f "$ASC_KEY_PATH" ]; then
    NOTARY_AUTH="--key $ASC_KEY_PATH --key-id $ASC_KEY_ID --issuer $ASC_ISSUER_ID"
elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    NOTARY_AUTH="--keychain-profile $PROFILE"
else
    echo "✗ No notary credentials: ASC key not at $ASC_KEY_PATH, and no '$PROFILE' keychain profile."
    echo "  Drop the .p8 there, or: xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id BSPX8X9U4B"
    exit 1
fi

if [ ! -d "$APP" ]; then
    echo "✗ $APP not found — run scripts/build-app.sh first"
    exit 1
fi

ZIP="$ROOT/build/Wall-notarize.zip"
rm -f "$ZIP"

echo "→ packaging $APP for submission…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ submitting to Apple (typically 1–10 minutes, blocks until done)…"
# Capture the exit code explicitly — otherwise `set -e` aborts on a non-zero
# notarytool *before* the output is echoed, swallowing the real error behind a
# bare exit code (e.g. the keychain-profile-missing case that bit us once).
set +e
SUBMIT_OUT=$(xcrun notarytool submit "$ZIP" $NOTARY_AUTH --wait 2>&1)
SUBMIT_RC=$?
set -e
echo "$SUBMIT_OUT"

if [ "$SUBMIT_RC" -ne 0 ]; then
    echo
    echo "✗ notarytool submit failed (exit $SUBMIT_RC)."
    case "$SUBMIT_OUT" in
        *"Invalid credentials"*|*401*|*"No Keychain password item"*)
            echo "  Auth rejected. Using: $NOTARY_AUTH"
            echo "  Check the ASC key file/id/issuer, or re-store the keychain profile."
            ;;
        *)
            echo "  Often transient (Apple notary service). Try again in a minute."
            ;;
    esac
    rm -f "$ZIP"
    exit 1
fi

STATUS=$(echo "$SUBMIT_OUT" | grep -E "^[[:space:]]*status:" | tail -1 | awk -F': *' '{print $2}')
ID=$(echo "$SUBMIT_OUT" | grep -E "^[[:space:]]*id:" | head -1 | awk -F': *' '{print $2}')

if [ "$STATUS" != "Accepted" ]; then
    echo
    echo "✗ Notarization status: $STATUS"
    if [ -n "$ID" ]; then
        echo "  Fetching log for submission $ID …"
        xcrun notarytool log "$ID" $NOTARY_AUTH 2>&1
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
