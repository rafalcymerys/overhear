#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/dist/Overhear.app"
ZIP_PATH="$PROJECT_DIR/dist/Overhear.zip"
DMG_PATH="$PROJECT_DIR/dist/Overhear.dmg"
ENTITLEMENTS="$PROJECT_DIR/Resources/Overhear.entitlements"

# The certificate and the notary credentials are the caller's, never this
# repository's: a Developer ID in here would be wrong for anyone who forks it
# and worthless the day it is rotated.
IDENTITY="${SIGNING_IDENTITY:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEY="${NOTARY_KEY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"

usage() {
    cat <<'USAGE'
Usage: ./scripts/notarize.sh [options]

Signs, notarizes and staples the app bundle left in dist/ by build.sh, then
does the same for a disk image built from the stapled app.

Signing identity (required, one of):
  --identity NAME           e.g. "Developer ID Application: Jane Doe (AB12CD34EF)"
  SIGNING_IDENTITY=NAME     same, as an environment variable

  `security find-identity -v -p codesigning` lists what is available.

Notary credentials (required, one of):
  --keychain-profile NAME   a profile stored with `notarytool store-credentials`
  --key PATH --key-id ID --issuer UUID
                            an App Store Connect API key, for CI
  NOTARY_KEYCHAIN_PROFILE, NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID
                            the same two forms, as environment variables
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --identity)         IDENTITY="$2"; shift 2 ;;
        --keychain-profile) KEYCHAIN_PROFILE="$2"; shift 2 ;;
        --key)              NOTARY_KEY="$2"; shift 2 ;;
        --key-id)           NOTARY_KEY_ID="$2"; shift 2 ;;
        --issuer)           NOTARY_ISSUER_ID="$2"; shift 2 ;;
        -h|--help)          usage; exit 0 ;;
        *)                  echo "Error: unknown option $1" >&2; echo >&2; usage >&2; exit 1 ;;
    esac
done

if [ -z "$IDENTITY" ]; then
    echo "Error: no signing identity. Pass --identity or set SIGNING_IDENTITY." >&2
    echo >&2
    usage >&2
    exit 1
fi

if [ -n "$NOTARY_KEY" ]; then
    if [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER_ID" ]; then
        echo "Error: --key also needs --key-id and --issuer." >&2
        exit 1
    fi
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif [ -n "$KEYCHAIN_PROFILE" ]; then
    NOTARY_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
else
    echo "Error: no notary credentials. Pass --keychain-profile or --key/--key-id/--issuer." >&2
    echo >&2
    usage >&2
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Run ./scripts/build.sh first." >&2
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "Error: $ENTITLEMENTS not found." >&2
    exit 1
fi

cd "$PROJECT_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# notarytool has exited 0 on a rejected submission in some versions, so the
# status is read back from the output rather than inferred from the exit code.
notarize() {
    local path="$1"
    local status id log
    log="$WORK_DIR/notarytool-$(basename "$path").txt"

    if ! xcrun notarytool submit "$path" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee "$log"; then
        : # fall through to the status check, which reports it better
    fi

    status="$(sed -n 's/^ *status: *//p' "$log" | tail -1)"
    id="$(sed -n 's/^ *id: *//p' "$log" | head -1)"

    if [ "$status" != "Accepted" ]; then
        echo "" >&2
        echo "Notarization failed for $(basename "$path") (status: ${status:-unknown})." >&2
        if [ -n "$id" ]; then
            echo "" >&2
            echo "Apple's reasons:" >&2
            xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" >&2 || true
        fi
        exit 1
    fi
}

echo "=== Signing Overhear.app ==="
echo "Identity: $IDENTITY"

# --options runtime is what notarization requires; --timestamp is what keeps
# already-shipped builds valid if the certificate is ever revoked.
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo ""
echo "=== Notarizing Overhear.app ==="

# ditto rather than zip(1): the submission has to carry the bundle's metadata,
# and the zip build.sh makes for distribution does not.
ditto -c -k --keepParent "$APP_DIR" "$WORK_DIR/submission.zip"
notarize "$WORK_DIR/submission.zip"

# The ticket goes on the .app — a zip cannot hold one — so the distributable
# zip is repacked from the stapled bundle. Same for the disk image below, which
# is why make-dmg.sh runs here rather than before notarization.
xcrun stapler staple "$APP_DIR"
rm -f "$ZIP_PATH"
(cd "$PROJECT_DIR/dist" && ditto -c -k --keepParent Overhear.app Overhear.zip)

echo ""
echo "=== Notarizing Overhear.dmg ==="
"$SCRIPT_DIR/make-dmg.sh" > /dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"

echo ""
echo "=== Verifying ==="
spctl --assess --verbose=4 --type install "$APP_DIR"
stapler validate "$APP_DIR"
stapler validate "$DMG_PATH"

echo ""
echo "=== Notarization complete ==="
echo ""
ls -lh "$ZIP_PATH" "$DMG_PATH"
echo ""
echo "Both are ready to publish. On a Mac that has never seen the app, download"
echo "one through a browser and open it — no xattr, no Gatekeeper dialog."
