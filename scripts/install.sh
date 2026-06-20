#!/bin/bash
set -euo pipefail

# Overhear — portable installer
# Run this on any Mac to set up the Python dependencies.
# The venv is created in ~/Library/Application Support/Overhear/.venv

APP_SUPPORT="$HOME/Library/Application Support/Overhear"
VENV_DIR="$APP_SUPPORT/.venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find requirements.txt — could be next to this script, or inside the .app bundle
REQ=""
for candidate in \
    "$SCRIPT_DIR/Engine/requirements.txt" \
    "$SCRIPT_DIR/../Resources/Engine/requirements.txt" \
    "$SCRIPT_DIR/requirements.txt"; do
    if [ -f "$candidate" ]; then
        REQ="$candidate"
        break
    fi
done

if [ -z "$REQ" ]; then
    echo "Error: Could not find requirements.txt"
    exit 1
fi

echo "=== Overhear Setup ==="

# Check for python3
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found. Install with: brew install python3"
    exit 1
fi

echo "Python: $(python3 --version)"

# Create app support directory
mkdir -p "$APP_SUPPORT"

# Create venv
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

echo "Installing Python dependencies..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$REQ"

# Download openwakeword models
echo "Downloading wake word models..."
"$VENV_DIR/bin/python" -c "
import openwakeword
openwakeword.utils.download_models()
print('Wake word models ready.')
"

# Pre-download whisper model
echo "Downloading Whisper model..."
"$VENV_DIR/bin/python" -c "
from faster_whisper import WhisperModel
WhisperModel('base', device='cpu', compute_type='int8')
print('Whisper model ready.')
"

echo ""
echo "=== Setup complete ==="
echo ""
echo "You can now run Overhear.app."
echo "The app will appear as a microphone icon in your menu bar."
echo ""
echo "Required permissions:"
echo "  - Microphone access (will be prompted)"
echo "  - Accessibility access (System Settings > Privacy > Accessibility)"
