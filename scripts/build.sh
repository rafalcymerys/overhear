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
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/Overhear "$APP_DIR/Contents/MacOS/Overhear"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Resource bundles the dependencies expect beside the binary. SwiftPM leaves
# them in .build/release; `Bundle.module` looks for them next to the executable
# or in Contents/Resources, and a package that reaches for one it cannot find
# traps — in the packaged app only, never in `swift run` or the tests.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

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
echo "  3. Open Overhear.app — it downloads its models on first launch"
