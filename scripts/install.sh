#!/bin/bash
set -euo pipefail

# Overhear — dependency installer.
#
# Builds the Python environment the dictation engine runs in. Overhear.app runs
# this itself on first launch (see EngineInstaller.swift), passing explicit
# --venv/--requirements/--python paths; running it by hand from the distribution
# folder works too, and the defaults below cover that case.
#
# Lines prefixed with ">>> " are what the app shows in its setup window.
# Everything else is detail that only lands in the install log.

APP_SUPPORT="$HOME/Library/Application Support/Overhear"
VENV_DIR="$APP_SUPPORT/.venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ=""
PYTHON_BIN=""

usage() {
    echo "Usage: $(basename "$0") [--venv DIR] [--requirements FILE] [--python PATH]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --venv) VENV_DIR="$2"; shift 2 ;;
        --requirements) REQ="$2"; shift 2 ;;
        --python) PYTHON_BIN="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

progress() { echo ">>> $1"; }

# Find requirements.txt. Two layouts matter: inside the app bundle
# (Resources/Engine, which is where both the app and a by-hand run start from),
# and a source checkout, where this script sits in scripts/.
if [ -z "$REQ" ]; then
    for candidate in \
        "$SCRIPT_DIR/Engine/requirements.txt" \
        "$SCRIPT_DIR/../Engine/requirements.txt"; do
        if [ -f "$candidate" ]; then
            REQ="$candidate"
            break
        fi
    done
fi

if [ -z "$REQ" ] || [ ! -f "$REQ" ]; then
    echo "Error: could not find requirements.txt" >&2
    exit 1
fi

# Pick an interpreter. Prefer the ones a user is likely to have installed
# deliberately; /usr/bin/python3 is the Command Line Tools stub and comes last.
if [ -z "$PYTHON_BIN" ]; then
    for candidate in \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        "$(command -v python3 || true)" \
        /usr/bin/python3; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "$PYTHON_BIN" ] || ! "$PYTHON_BIN" --version >/dev/null 2>&1; then
    echo "Error: python3 not found. Install it with: brew install python3" >&2
    exit 1
fi

echo "=== Overhear Setup ==="
echo "Python: $("$PYTHON_BIN" --version 2>&1) ($PYTHON_BIN)"
echo "Requirements: $REQ"
echo "Environment: $VENV_DIR"

mkdir -p "$(dirname "$VENV_DIR")"

if [ ! -d "$VENV_DIR" ]; then
    progress "Creating the Python environment…"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

progress "Installing Python dependencies…"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$REQ"

progress "Downloading wake word models…"
"$VENV_DIR/bin/python" -c "
import openwakeword
openwakeword.utils.download_models()
print('Wake word models ready.')
"

progress "Downloading the Whisper model…"
"$VENV_DIR/bin/python" -c "
from faster_whisper import WhisperModel
WhisperModel('base', device='cpu', compute_type='int8')
print('Whisper model ready.')
"

# Stamp the environment with the requirements it was built from. The app reads
# this to decide whether it can skip setup on the next launch — no stamp means
# an interrupted install, a different digest means the dependencies moved on.
shasum -a 256 "$REQ" | awk '{print $1}' > "$VENV_DIR/.overhear-requirements"

progress "Setup complete."
echo ""
echo "=== Setup complete ==="
echo ""
echo "You can now run Overhear.app."
echo "The app will appear as a microphone icon in your menu bar."
echo ""
echo "Required permissions:"
echo "  - Microphone access (will be prompted)"
echo "  - Accessibility access (System Settings > Privacy > Accessibility)"
