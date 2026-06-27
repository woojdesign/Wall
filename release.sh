#!/usr/bin/env bash
#
# Cut a Wall release AND publish it for Sparkle auto-update:
#   changelog → build → Developer ID sign → notarize → staple → zip →
#   notarized DMG → EdDSA-sign + appcast → GitHub Release.
#
# Installed copies (>= the bootstrap build) update themselves from the
# appcast at .../releases/latest/download/appcast.xml. The DMG is the
# friend-facing first-install download.
#
# Prerequisites (all one-time, already set up):
#   • Developer ID Application cert in the keychain.
#   • notarytool keychain profile "wall-notary".
#   • Sparkle EdDSA private key in the keychain (shared with StickySync).
#   • gh authenticated for the woojdesign account.
#   • brew install create-dmg  (optional — falls back to scripts/make-dmg.sh).
#
# Usage:
#   ./release.sh 0.1.0
#
# Flags:
#   --keep-notes   use the existing release-notes/<version>.md as-is
#   --no-edit      don't open the generated notes in $EDITOR
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:?usage: ./release.sh <version>   e.g. ./release.sh 0.1.0}"; shift || true
TAG="v$VERSION"
REPO="woojdesign/Wall"
PROFILE="wall-notary"
BUILD="$(git rev-list --count HEAD)"

KEEP_NOTES=0
EDIT_NOTES=1
for arg in "$@"; do
    case "$arg" in
        --keep-notes) KEEP_NOTES=1 ;;
        --no-edit)    EDIT_NOTES=0 ;;
        *) echo "warn: unknown flag $arg" ;;
    esac
done

# ── 1. Release notes ────────────────────────────────────────────────────────
# Auto-draft user-facing bullets from git log via `claude -p`, then (unless
# --no-edit) open for a final pass. Falls back to a raw commit list if the
# claude CLI is unavailable. Tracked under release-notes/<version>.md.
mkdir -p release-notes
CHANGELOG="release-notes/$VERSION.md"
# `gh release create` makes the version tag server-side, so a local clone won't
# have it until fetched. Pull tags first or the changelog range can't scope to
# since-last-release (it would fall back to the whole history).
git fetch --tags --quiet 2>/dev/null || true
LAST_TAG="$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"

if [ -f "$CHANGELOG" ] && [ "$KEEP_NOTES" = "1" ]; then
    echo "==> Using existing $CHANGELOG"
else
    echo "==> Drafting release notes for $VERSION (commits: $RANGE)"
    LOG="$(git log --no-merges --pretty='- %s' "$RANGE" 2>/dev/null || true)"
    [ -n "$LOG" ] || LOG="- Initial release."
    if command -v claude >/dev/null && [ -n "$LAST_TAG" ]; then
        # claude tends to wrap output in preamble / trailing questions even when
        # told not to, and that prose would land verbatim in the GitHub release
        # and the Sparkle update dialog. So keep only bullet lines, and fall back
        # to the raw commit list if filtering leaves nothing.
        DRAFT="$(printf 'Rewrite these git commits as concise, user-facing release-note bullets for the macOS app "Wall" (a focus/writing app). Output ONLY the bullet lines, each starting with "- ". No preamble, no commentary, no trailing questions.\n\n%s\n' "$LOG" \
            | claude -p 2>/dev/null | grep -E '^[[:space:]]*-' || true)"
        if [ -n "$DRAFT" ]; then printf '%s\n' "$DRAFT" > "$CHANGELOG"
        else printf '%s\n' "$LOG" > "$CHANGELOG"; fi
    else
        printf '%s\n' "$LOG" > "$CHANGELOG"
    fi
    [ "$EDIT_NOTES" = "1" ] && [ -t 0 ] && "${EDITOR:-vi}" "$CHANGELOG" || true
fi
[ -s "$CHANGELOG" ] || { echo "error: $CHANGELOG is empty"; exit 1; }

# ── 2. Build + Developer ID sign (versioned) ────────────────────────────────
echo "==> Build + sign Wall $VERSION ($BUILD)"
VERSION="$VERSION" BUILD="$BUILD" ./scripts/build-app.sh release

# ── 3. Notarize + staple + zip (the Sparkle update artifact) ────────────────
echo "==> Notarize + staple"
./scripts/notarize.sh
ZIP="build/Wall-$VERSION-$BUILD.zip"
[ -f "$ZIP" ] || { echo "error: expected $ZIP from notarize.sh"; exit 1; }

# ── 4. First-install DMG (notarized + stapled) ──────────────────────────────
echo "==> Build DMG"
./scripts/make-dmg.sh
DMG="build/Wall.dmg"
if [ -f "$DMG" ]; then
    echo "==> Notarize DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

# ── 5. EdDSA-sign the update + generate the appcast ─────────────────────────
GEN_APPCAST="$(find "$ROOT/.build/artifacts" -type f -name generate_appcast \
    -path '*sparkle*' 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || { echo "error: Sparkle's generate_appcast not found (run swift build)"; exit 1; }

RELEASES="build/releases"
rm -rf "$RELEASES"; mkdir -p "$RELEASES"
cp "$ZIP" "$RELEASES/"
# Drop the changelog next to the archive under the SAME basename — generate_appcast
# picks up a same-named .md/.html/.txt and embeds it as the update's release notes,
# so Sparkle's "A new version is available" dialog shows what changed.
cp "$CHANGELOG" "$RELEASES/$(basename "${ZIP%.zip}").md"
echo "==> Sign update + generate appcast"
"$GEN_APPCAST" "$RELEASES" \
    --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
[ -f "$RELEASES/appcast.xml" ] || { echo "error: appcast.xml not generated"; exit 1; }

# Keep only the appcast + archives as release assets; the loose .md was just
# input for generate_appcast (its content now lives inside appcast.xml).
rm -f "$RELEASES/$(basename "${ZIP%.zip}").md"

# Stable-named copies so the "latest" redirect is a permanent share link.
# Made AFTER generate_appcast so they aren't picked up as extra appcast items.
cp "$RELEASES/$(basename "$ZIP")" "$RELEASES/Wall.zip"
[ -f "$DMG" ] && cp "$DMG" "$RELEASES/Wall.dmg"

# ── 6. Friend-facing release notes + install guide ──────────────────────────
cat > "$RELEASES/NOTES.md" <<EOF
## What's new in $VERSION

$(cat "$CHANGELOG")

---

## Install Wall $VERSION

Requires macOS 15 or later.

1. **Download:** [Wall.dmg](https://github.com/$REPO/releases/latest/download/Wall.dmg) — always the newest version.
2. **Open the DMG** and drag **Wall** into the **Applications** folder shortcut.
3. **First launch.** macOS is cautious about apps from outside the App Store, so the first open takes a couple of extra clicks:
   - Double-click Wall from Applications. You'll see *"Apple could not verify…"* — click **Done** (not Move to Trash).
   - Open **System Settings → Privacy & Security**, scroll to **Security**, and next to *"Wall was blocked…"* click **Open Anyway**, then confirm with your password or Touch ID.
   - The app is notarized by Apple — this is just macOS's standard caution for non-App-Store apps, and you only do it once.
4. **Approve the background helper once.** Wall asks to install a small helper that lets it raise the wall without a password prompt every time. Approve it in **System Settings → General → Login Items & Extensions → Background**.

**Updates** install themselves automatically — no need to come back here.
EOF

# ── 7. Publish the GitHub Release ───────────────────────────────────────────
echo "==> Publishing GitHub release $TAG"
ASSETS=("$RELEASES/$(basename "$ZIP")" "$RELEASES/Wall.zip" "$RELEASES/appcast.xml")
[ -f "$RELEASES/Wall.dmg" ] && ASSETS+=("$RELEASES/Wall.dmg")

gh release create "$TAG" \
    "${ASSETS[@]}" \
    --repo "$REPO" \
    --title "Wall $VERSION" \
    --notes-file "$RELEASES/NOTES.md"

echo
echo "Released $TAG."
echo "  Feed:  https://github.com/$REPO/releases/latest/download/appcast.xml"
echo "  Share: https://github.com/$REPO/releases/latest/download/Wall.dmg"
echo "  Installed copies will now auto-update to $VERSION."
