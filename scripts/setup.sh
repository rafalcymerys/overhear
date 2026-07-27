#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_DIR/.venv"

echo "=== Overhear Setup ==="

# Check for python3
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found. Install with: brew install python3"
    exit 1
fi

echo "Python: $(python3 --version)"

# Create venv
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "Installing Python dependencies..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
# Dev setup, so this pulls in the test dependencies too. The shipped app installs
# from requirements.txt via scripts/install.sh and stays lean.
"$VENV_DIR/bin/pip" install --quiet -r "$PROJECT_DIR/Engine/requirements-dev.txt"

# Download openwakeword models
echo "Downloading wake word models..."
"$VENV_DIR/bin/python" -c "
import openwakeword
openwakeword.utils.download_models()
print('Wake word models ready.')
"

echo ""
echo "=== Setup complete ==="
echo ""
echo "To build and run:"
echo "  cd $PROJECT_DIR"
echo "  swift build"
echo "  .build/debug/Overhear"
echo ""
echo "To run the engine tests:"
echo "  .venv/bin/python -m pytest Engine"
echo ""
echo "The app will appear as a microphone icon in your menu bar."
echo "Default wake word: 'hey jarvis' (from openwakeword)"
echo ""
echo "Required permissions:"
echo "  - Microphone access (will be prompted)"
echo "  - Accessibility access (System Settings > Privacy > Accessibility)"
echo "    Needed to paste text into other apps"
