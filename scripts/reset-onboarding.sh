#!/usr/bin/env bash
#
# Re-trigger Wall's first-run onboarding for testing: clear the "has begun once"
# flag so the first-session confirmation shows again, then relaunch the dev build.
#
#   scripts/reset-onboarding.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

defaults delete design.wooj.wall hasBegunOnce 2>/dev/null || true
echo "✓ cleared design.wooj.wall hasBegunOnce"

if [ -d build/Wall.app ]; then
  pkill -x Wall 2>/dev/null || true
  open build/Wall.app
  echo "✓ relaunched build/Wall.app — tap Begin to see the first-session confirmation"
else
  echo "  (build/Wall.app not found — build first: SKIP_SIGN=1 scripts/build-app.sh debug)"
fi
