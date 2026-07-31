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

# The app runs the installer itself on first launch, so the script only needs to
# ship inside the bundle — running setup by hand means running that same copy.
cp scripts/install.sh "$APP_DIR/Contents/Resources/install.sh"
chmod +x "$APP_DIR/Contents/Resources/install.sh"

# Create zip (from inside dist/ so paths aren't prefixed with dist/)
echo "Packaging..."
(cd "$PROJECT_DIR/dist" && zip -r Overhear.zip Overhear.app -x "*.DS_Store" > /dev/null)

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
echo "  3. Open Overhear.app — it installs its Python environment on first launch"
echo "     (to do that step from the terminal instead:"
echo "      ./Overhear.app/Contents/Resources/install.sh)"
