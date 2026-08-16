#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/dist/Overhear.app"
DMG_PATH="$PROJECT_DIR/dist/Overhear.dmg"

cd "$PROJECT_DIR"

echo "=== Packaging Overhear.dmg ==="

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Run ./scripts/build.sh first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist")"

# Stage the disk image contents outside dist/ so nothing else in there — the zip,
# a stale .DS_Store — ends up on the volume.
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_DIR" "$STAGE_DIR/Overhear.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "Overhear $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG_PATH"

echo ""
echo "=== Package complete ==="
echo ""
ls -lh "$DMG_PATH"
echo ""
echo "To install on a new Mac:"
echo "  1. Open Overhear.dmg and drag Overhear to Applications"
echo "  2. Run: xattr -cr /Applications/Overhear.app"
echo "  3. Open Overhear.app — it installs its Python environment on first launch"
