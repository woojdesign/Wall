#!/bin/sh
# render-icon.sh — generate build/AppIcon.icns from render-icon.swift.
# Run manually when the icon design changes; build-app.sh just copies the
# resulting .icns into the bundle.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
swift scripts/render-icon.swift
iconutil --convert icns build/AppIcon.iconset --output build/AppIcon.icns
echo "✓ build/AppIcon.icns"
