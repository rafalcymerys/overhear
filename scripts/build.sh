#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/dist/Overhear.app"
ENTITLEMENTS="$PROJECT_DIR/Resources/Overhear.entitlements"

# The certificate is the caller's, never this repository's. Given none, the
# first Developer ID in the keychain is used, so a build on the machine that
# ships the app needs no arguments.
IDENTITY="${SIGNING_IDENTITY:-}"

usage() {
    cat <<'USAGE'
Usage: ./scripts/build.sh [options]

Builds the release binary and wraps it in dist/Overhear.app.

Signing identity (optional):
  --identity NAME           e.g. "Developer ID Application: Jane Doe (AB12CD34EF)"
  SIGNING_IDENTITY=NAME     same, as an environment variable

Given neither, the first Developer ID Application certificate in the keychain
is used; with no certificate at all the bundle is left unsigned.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --identity) IDENTITY="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Error: unknown option $1" >&2; echo >&2; usage >&2; exit 1 ;;
    esac
done

if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

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

# Signing is what makes the accessibility grant survive a rebuild. TCC
# remembers the permission against the app's signing identity, and the ad-hoc
# signature the linker leaves has none — only the hash of the binary, which
# every build changes. The grant then belongs to the build that asked for it,
# the switch in System Settings stays on for a bundle that no longer exists,
# and the new build is told it has no permission. A Developer ID keeps the
# identity the same from one build to the next, so the grant keeps applying.
#
# The hardened runtime, which needs the entitlements beside it, is here so
# builds behave the way the notarized one will. No --timestamp: that is
# notarization's business, and it would make this build need the network.
if [ -n "$IDENTITY" ]; then
    echo "Signing..."
    echo "Identity: $IDENTITY"
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" \
        "$APP_DIR"
    codesign --verify --strict "$APP_DIR"
else
    echo ""
    echo "Warning: no Developer ID Application certificate found — leaving the"
    echo "bundle unsigned. macOS will forget the accessibility permission every"
    echo "time you rebuild, and granting it again means first deleting the stale"
    echo "Overhear row from System Settings > Privacy & Security > Accessibility."
    echo "Pass --identity to sign with a certificate of your own."
    echo ""
fi

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
