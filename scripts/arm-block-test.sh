#!/bin/sh
# arm-block-test.sh — exercise the real pf block briefly, with auto-revert.
#
# Mirrors PFBlocker.block() in Sources/Wall/Blocker.swift so we're testing the
# real path. The dead-man's-switch is a launchd job (not nohup) so it survives
# osascript's privileged trampoline tearing down.
#
# Usage: ./scripts/arm-block-test.sh [duration_seconds]   (default 60)
# Escape hatch if anything wedges: sudo ./scripts/disarm-block.sh
set -e

DURATION="${1:-60}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Parse-only check (no root, no kernel change).
RULES_TMP=$(mktemp /tmp/wall.rules.XXXXXX)
cat > "$RULES_TMP" <<'PF'
set block-policy drop
block drop out all
pass out quick on lo0 all
pass out quick inet proto udp from any to any port { 67, 68 }
pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 }
pass out quick inet6 from any to { fe80::/10, fc00::/7, ff00::/8 }
PF
echo "→ Parsing rules (dry run)…"
pfctl -nf "$RULES_TMP" 2>&1 | grep -v "could result in flushing" || true
rm -f "$RULES_TMP"

cat <<EOF

About to arm the real pf block for ${DURATION}s.

What happens next:
  • macOS prompts for your password / Touch ID (osascript admin).
  • Outbound to the public internet → DROPPED for ${DURATION}s.
  • Loopback, LAN, link-local, multicast, DHCP → PASSED.
  • A launchd job (design.wooj.wall.deadman) flushes pf after ${DURATION}s.

Verify during the window (another terminal):
  curl --max-time 3 https://example.com                      # should FAIL
  ping -c1 -t1 127.0.0.1                                     # should SUCCEED
  sudo launchctl print system/design.wooj.wall.deadman | head -3  # deadman visible

Manual escape (if it wedges):
  sudo ${ROOT}/scripts/disarm-block.sh

Press Enter to proceed, Ctrl-C to abort.
EOF
read _

# 2. Build the privileged script — same shape as PFBlocker.block().
PRIV=$(mktemp /tmp/wall.priv.XXXXXX.sh)
cat > "$PRIV" <<EOSPRIV
set -e
ANCHOR_FILE=/etc/pf.anchors/wall.block
MAIN=\$(mktemp /tmp/wall.main.XXXXXX)
LABEL=design.wooj.wall.deadman
PLIST=/tmp/wall-deadman.plist

cat > "\$ANCHOR_FILE" <<'PF'
set block-policy drop
block drop out all
pass out quick on lo0 all
pass out quick inet proto udp from any to any port { 67, 68 }
pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 }
pass out quick inet6 from any to { fe80::/10, fc00::/7, ff00::/8 }
PF

cat > "\$MAIN" <<PFMAIN
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
anchor "wall.block"
load anchor "wall.block" from "\$ANCHOR_FILE"
PFMAIN

pfctl -f "\$MAIN"
pfctl -E

# Dead-man: launchd-owned job, detached from osascript's process tree.
launchctl bootout system/\$LABEL 2>/dev/null || true
cat > "\$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\$LABEL</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>sleep ${DURATION}; pfctl -a wall.block -F all; pfctl -f /etc/pf.conf</string>
  </array>
</dict>
</plist>
PLISTEOF
launchctl bootstrap system "\$PLIST"
echo DEADMAN_LOADED
EOSPRIV

OUT=$(osascript -e "do shell script \"/bin/sh $PRIV\" with administrator privileges" 2>&1)
rm -f "$PRIV"

if echo "$OUT" | grep -q DEADMAN_LOADED; then
  echo "✓ Armed. Dead-man registered in launchd."
else
  echo "⚠ Could not confirm dead-man registration. osascript output:"
  echo "$OUT"
fi

sleep 1

# 3. Smoke check (in the user shell — not the privileged one).
if curl --max-time 3 -s -o /dev/null https://example.com 2>&1; then
  echo "  ⚠ outbound NOT blocked — investigate"
else
  echo "  ✓ outbound to public internet: BLOCKED"
fi
if ping -c1 -t1 127.0.0.1 >/dev/null 2>&1; then
  echo "  ✓ loopback: OK"
else
  echo "  ⚠ loopback fails — investigate"
fi
if launchctl print system/design.wooj.wall.deadman >/dev/null 2>&1; then
  echo "  ✓ dead-man job: registered with launchd"
else
  echo "  ⚠ dead-man job not visible from user shell — try: sudo launchctl print system/design.wooj.wall.deadman"
fi

echo
echo "Auto-revert in ${DURATION}s. Manual escape: sudo ${ROOT}/scripts/disarm-block.sh"
