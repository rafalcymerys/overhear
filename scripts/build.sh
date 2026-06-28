#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/dist/Overhear.app"

cd "$PROJECT_DIR"

echo "=== Building Overhear ==="

# Clean previous build
rm -rf "$PROJECT_DIR/dist"

# Build release binary
echo "Compiling..."
swift build -c release 2>&1

# Create app bundle
echo "Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/Engine"

cp .build/release/Overhear "$APP_DIR/Contents/MacOS/Overhear"
cp Engine/dictation_engine.py "$APP_DIR/Contents/Resources/Engine/"
cp Engine/requirements.txt "$APP_DIR/Contents/Resources/Engine/"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy install script alongside the app
cp scripts/install.sh "$PROJECT_DIR/dist/"

# Create zip
echo "Packaging..."
cd "$PROJECT_DIR"
zip -r dist/Overhear.zip dist/Overhear.app dist/install.sh -x "*.DS_Store" > /dev/null

echo ""
echo "=== Build complete ==="
echo ""
ls -lh dist/Overhear.zip
echo ""
echo "Distribution contents:"
ls -lh dist/
echo ""
echo "To install on a new Mac:"
echo "  1. Unzip Overhear.zip"
echo "  2. Run: xattr -cr Overhear.app"
echo "  3. Run: ./install.sh"
echo "  4. Open Overhear.app"
