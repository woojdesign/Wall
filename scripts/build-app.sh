#!/bin/sh
# Build Wall and assemble a Developer ID-signed .app bundle.
#
#   • Builds Wall + WallHelper from the SPM package
#   • Embeds the helper binary + its launchd daemon plist
#     (registered later via SMAppService.daemon on first launch)
#   • Embeds Sparkle.framework (auto-update) into Contents/Frameworks and
#     adds the @executable_path/../Frameworks rpath the SPM build omits
#   • Writes the Sparkle feed URL + EdDSA public key into Info.plist
#   • Signs everything Developer ID (Sean Kim, BSPX8X9U4B), inside-out:
#     Sparkle's nested XPC services / Autoupdate / Updater.app → framework →
#     helper → app. Hardened runtime + secure timestamp throughout.
#   • Verifies with codesign --verify --deep --strict
#
# Version + build number come from the environment so release.sh can drive
# them; both default to dev-friendly values for local iteration:
#   VERSION  marketing version  → CFBundleShortVersionString  (default 0.0.0-dev)
#   BUILD    monotonic build #  → CFBundleVersion / sparkle:version
#            (default: git commit count, else 1)
#
# Usage:  ./scripts/build-app.sh [debug|release]
# Dev iteration without keychain/timestamp: SKIP_SIGN=1 ./scripts/build-app.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="Wall"
HELPER_NAME="WallHelper"
HELPER_LABEL="design.wooj.wall.helper"
APP_BUNDLE_ID="design.wooj.wall"
CONFIG="${1:-debug}"
SIGN_ID="Developer ID Application: Sean Kim (BSPX8X9U4B)"

# Sparkle auto-update config. The feed is the newest release's appcast, served
# from GitHub's stable "latest" redirect; the EdDSA public key validates every
# downloaded update against the private key in the keychain (shared with
# StickySync — Sparkle uses one signing key across all your apps).
SU_FEED_URL="https://github.com/woojdesign/Wall/releases/latest/download/appcast.xml"
SU_PUBLIC_ED_KEY="JkYg/JJTp7adKCjdq0EskEAOMwxsd2vJVvRou9hkZ/I="

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# 1. Build both executables.
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# Locate the universal (arm64+x86_64) Sparkle.framework from the resolved
# binary artifact — NOT the per-arch copy SPM drops next to the build products.
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -type d \
    -path '*Sparkle.xcframework/macos*/Sparkle.framework' 2>/dev/null | head -1)"
[ -n "$SPARKLE_FW" ] || { echo "✗ Sparkle.framework not found — run 'swift build' first"; exit 1; }

# 2. Assemble bundle.
APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources" \
         "$APP/Contents/Frameworks" \
         "$APP/Contents/Library/LaunchDaemons"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$HELPER_NAME" "$APP/Contents/MacOS/$HELPER_NAME"

# Embed Sparkle. ditto preserves the framework's symlink/version layout.
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# The Wall binary loads @rpath/Sparkle.framework/... but the SPM link only
# leaves an @loader_path rpath. Point it at the embedded Frameworks dir.
# (Must happen before signing — install_name_tool invalidates signatures.)
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# 3. Main app Info.plist.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wall</string>
  <key>CFBundleDisplayName</key><string>Wall</string>
  <key>CFBundleIdentifier</key><string>$APP_BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><false/>
  <!-- Sparkle: appcast feed + EdDSA public key. SUEnableAutomaticChecks is
       deliberately omitted so Sparkle asks on first launch. -->
  <key>SUFeedURL</key><string>$SU_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SU_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

# 4. Daemon plist for SMAppService. Mach service name matches the helper's
#    NSXPCListener; AssociatedBundleIdentifiers groups this under "Wall"
#    in Login Items & Extensions → Background.
cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_LABEL</string>
  <key>BundleProgram</key>
  <string>Contents/MacOS/$HELPER_NAME</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_LABEL</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$APP_BUNDLE_ID</string>
  </array>
</dict>
</plist>
PLIST

# 5. App icon, if rendered.
if [ -f "$ROOT/build/AppIcon.icns" ]; then
    cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

# 6. Sign — unless SKIP_SIGN=1 (dev iteration without keychain access).
if [ "$SKIP_SIGN" = "1" ]; then
    # Ad-hoc sign Sparkle inside-out so the bundle at least loads locally.
    codesign --force --sign - "$FW/XPCServices/Installer.xpc" >/dev/null 2>&1 || true
    codesign --force --sign - "$FW/XPCServices/Downloader.xpc" >/dev/null 2>&1 || true
    codesign --force --sign - "$FW/Autoupdate" >/dev/null 2>&1 || true
    codesign --force --sign - "$FW/Updater.app" >/dev/null 2>&1 || true
    codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1 || true
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    echo "Built (ad-hoc, unsigned) $APP — v$VERSION ($BUILD)"
    exit 0
fi

# Empty entitlements — hardened runtime defaults are correct for us.
# (No sandbox, no network grants needed; XPC over Mach ports requires none.)
APP_ENT=$(mktemp /tmp/wall.app.entitlements.XXXXXX.plist)
HELPER_ENT=$(mktemp /tmp/wall.helper.entitlements.XXXXXX.plist)
EMPTY='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>'
printf '%s' "$EMPTY" > "$APP_ENT"
printf '%s' "$EMPTY" > "$HELPER_ENT"

sign() {
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"
}

# Sparkle, deepest first. Each nested executable needs its own hardened-runtime
# Developer ID signature for notarization; the framework seal is recomputed last
# so it references the freshly-signed helpers.
sign "$FW/XPCServices/Installer.xpc"
sign "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"

# Helper (nested). --identifier sets the signing identifier to match the daemon
# Label; default would be derived from the filename.
sign --identifier "$HELPER_LABEL" --entitlements "$HELPER_ENT" \
    "$APP/Contents/MacOS/$HELPER_NAME"

# Main app last so its seal covers all nested content. Identifier comes from
# CFBundleIdentifier automatically.
sign --entitlements "$APP_ENT" "$APP"

rm -f "$APP_ENT" "$HELPER_ENT"

# 7. Verify.
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✓ Built and signed $APP — v$VERSION ($BUILD)"
