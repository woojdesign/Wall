# Wall

A menu-bar app for macOS that raises a **wall** — a network block — for focused
writing sessions. The wall stays up until you've hit your word target (and,
optionally, a time floor), then comes back down on its own.

## Install

Requires **macOS 15 or later**.

1. Download the latest **[Wall.dmg](https://github.com/woojdesign/Wall/releases/latest/download/Wall.dmg)**.
2. Open it and drag **Wall** into **Applications**.
3. First launch: macOS guards apps from outside the App Store. Double-click Wall,
   click **Done** on the warning, then open **System Settings → Privacy &
   Security → Open Anyway**. (Wall is notarized by Apple — this is a one-time
   step.)
4. Approve the background helper once in **System Settings → General → Login
   Items & Extensions → Background**. It lets Wall raise the block without a
   password prompt each session.

Updates install themselves automatically (via [Sparkle](https://sparkle-project.org)).

## Build from source

```sh
swift build
./scripts/render-icon.sh        # once, to generate the app icon
SKIP_SIGN=1 ./scripts/build-app.sh release   # unsigned local bundle in build/
```

Releases (Developer ID signed, notarized, with a Sparkle appcast) are cut with
`./release.sh <version>`. See [CLAUDE.md](CLAUDE.md) for the full pipeline.

## How it works

Wall talks over XPC to a small privileged helper (`WallHelper`) that drives the
system packet filter (`pf`). The helper runs as a root launchd daemon, installed
on first launch via `SMAppService`. The app itself is sandbox-free SwiftUI; the
design system comes from [wooj-tokens](https://github.com/woojdesign).
