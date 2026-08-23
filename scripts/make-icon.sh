#!/bin/bash
set -euo pipefail

# Regenerates Resources/AppIcon.icns from make-icon.swift. The artwork is drawn
# in code rather than exported from a design file, so every size is rendered as
# vectors at its own resolution instead of downsampled from the 1024 master.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$(mktemp -d)"
ICONSET="$WORK_DIR/AppIcon.iconset"

trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$ICONSET"
swift "$SCRIPT_DIR/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/Resources/AppIcon.icns"

echo ""
echo "Wrote Resources/AppIcon.icns"
ls -lh "$PROJECT_DIR/Resources/AppIcon.icns"
