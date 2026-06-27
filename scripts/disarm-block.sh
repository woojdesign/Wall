#!/bin/sh
# disarm-block.sh — manual escape hatch.
# Boots out the dead-man launchd job, flushes the wall.block anchor, and
# reloads the default pf config. Safe to run even if no block is active.
exec sudo sh -c '
launchctl bootout system/design.wooj.wall.deadman 2>/dev/null || true
pfctl -a wall.block -F all 2>/dev/null || true
pfctl -f /etc/pf.conf 2>/dev/null || true
echo "✓ Block cleared. pf back to /etc/pf.conf."
'
