# Wall — operational guide

Auto-loaded by Claude Code each session. Keep terse; link to scripts/code for detail.

## What it is

Menu-bar macOS app (SwiftUI, macOS 15+) that raises a "wall" — a `pf`-based
network block — for focused writing sessions. Distributed as a direct download
(GitHub Releases + DMG) with **Sparkle** auto-update. Not sandboxed, not on the
App Store.

## Layout

- **Pure SPM package** (`Package.swift`), not an Xcode project. Two executables
  + a shared target:
  - `Sources/Wall` — the app (menu bar + window). Bundle id `design.wooj.wall`.
  - `Sources/WallHelper` — privileged `pf` helper, run as a root launchd daemon
    via `SMAppService.daemon`. Label `design.wooj.wall.helper`.
  - `Sources/WallShared` — the XPC protocol shared by both.
- **wooj-tokens** (`../wooj-tokens`) — design tokens, consumed only.
- **Sparkle** 2.9.x — SPM dependency on the `Wall` target; in-app updater in
  `Sources/Wall/Updater.swift`.

## Release → GitHub + Sparkle auto-update

```sh
./release.sh 0.1.0
```

What it does (see the header of `release.sh`): draft changelog → build +
Developer ID sign → notarize → staple → zip (Sparkle artifact) → notarized DMG
(first install) → EdDSA-sign + `generate_appcast` → `gh release create`. Tag is
`v0.1.0`. **Last shipped: none yet (0.1.0 is the bootstrap).**

The first release is the bootstrap: install it by hand on each Mac (download the
DMG). Every release after that updates installed copies automatically from
`.../releases/latest/download/appcast.xml`.

Flags: `--keep-notes` (reuse `release-notes/<version>.md`), `--no-edit` (don't
open notes in `$EDITOR`).

### The scripts underneath (run individually for dev iteration)

- `scripts/build-app.sh [debug|release]` — build + assemble + embed Sparkle +
  Developer ID sign. `VERSION`/`BUILD` come from the env (release.sh sets them;
  default `0.0.0-dev` / git commit count). `SKIP_SIGN=1` ad-hoc signs for a
  quick local run without keychain/timestamp.
- `scripts/notarize.sh` — notarize + staple `build/Wall.app`, then emit
  `build/Wall-<version>-<build>.zip` (the Sparkle update artifact, version read
  from the built Info.plist).
- `scripts/make-dmg.sh` — wrap the stapled app in a drag-to-Applications DMG.
- `scripts/render-icon.sh` — regenerate `build/AppIcon.icns` from
  `scripts/render-icon.swift`. Run when the icon changes; `build/` is gitignored,
  so run this once on a fresh checkout before the first release build.

## Versioning

- **Marketing version** = the arg to `release.sh` (`0.1.0`) → `CFBundleShortVersionString`.
- **Build number** = `git rev-list --count HEAD` → `CFBundleVersion` and Sparkle's
  `sparkle:version`. Monotonic per commit — Sparkle compares these to decide an
  update is newer, so never reset it.
- **Tag**: `v0.1.0` (unprefixed). The GitHub Release lives at `releases/tag/v0.1.0`.

## Sparkle specifics

- Feed `SUFeedURL` and `SUPublicEDKey` are written into Info.plist by
  `build-app.sh`. Feed = `.../releases/latest/download/appcast.xml`.
- **Signing key is shared with StickySync** — Sparkle stores one EdDSA key in the
  login keychain (account `ed25519`); per its own guidance you use one key across
  all your apps. Public key: `JkYg/JJTp7adKCjdq0EskEAOMwxsd2vJVvRou9hkZ/I=`.
- Because this is a hand-assembled bundle (no Xcode "Embed Frameworks" phase),
  `build-app.sh` embeds `Sparkle.framework` into `Contents/Frameworks`, adds the
  `@executable_path/../Frameworks` rpath, and signs Sparkle's nested helpers
  inside-out (XPC services → Autoupdate → Updater.app → framework). Don't remove
  that ordering — codesign seals the framework last so it references the
  freshly-signed helpers.

## One-time setup (recovery / new machine)

- **Signing**: Developer ID Application cert (Sean Kim, BSPX8X9U4B) in keychain;
  notarytool profile `wall-notary`
  (`xcrun notarytool store-credentials wall-notary --apple-id <email> --team-id BSPX8X9U4B`).
- **Sparkle key**: already in the keychain (shared with StickySync). If truly
  fresh: `generate_keys` and put the printed public key in `build-app.sh`.
- **GitHub**: `gh auth login` for `woojdesign`. Repo: `woojdesign/Wall`.
- `brew install create-dmg` is optional — `make-dmg.sh` works without it.

## Gotchas

- **Helper after an update**: Sparkle replaces the `.app` cleanly, but the
  *running* root daemon keeps the old `WallHelper` binary until it's relaunched.
  `HelperManager.registerIfNeeded()` (called every launch) re-registers the new
  one; launchd reloads it on next start. Not a problem in practice, but don't
  expect a live daemon swap mid-update.
- **No commits = no build number.** `git rev-list --count HEAD` needs at least
  one commit before a release.
