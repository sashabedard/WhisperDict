#!/usr/bin/env bash
#
# Build WhisperDict.app from Swift Package
#
# Usage: ./Scripts/build.sh   (works from anywhere — cd's to the repo root)
#

set -euo pipefail

# Operate from the repo root regardless of where the script is invoked.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAME="WhisperDict"
APP="${NAME}.app"
ARCH="$(uname -m)"  # arm64 sur Apple Silicon

echo "→ Building release binary for ${ARCH}..."
swift build -c release --arch "$ARCH" || true

BIN_PATH=".build/release/$NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "✗ Binary not found at $BIN_PATH — build failed"
    exit 1
fi
echo "✓ Binary OK ($(du -sh "$BIN_PATH" | cut -f1))"

echo "→ Assembling $APP bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/$NAME"
cp Info.plist "$APP/Contents/Info.plist"
ICON="Scripts/assets/AppIcon.icns"
[[ -f "$ICON" ]] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Prefer a stable self-signed identity (./Scripts/setup_signing.sh) so macOS
# keeps the Accessibility/Microphone grants across rebuilds. Fall back to ad-hoc.
IDENTITY="WhisperDict Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "→ Signing with '$IDENTITY'…"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "→ Ad-hoc signing (run ./Scripts/setup_signing.sh for a stable identity)…"
    codesign --force --deep --sign - "$APP"
fi

echo ""
echo "✓ Built $APP"
echo ""
echo "  Run:        open $APP"
echo "  Install:    mv $APP /Applications/"
echo ""
echo "  Au premier lancement, accorde:"
echo "    - Microphone (prompt automatique)"
echo "    - Accessibility (System Settings > Privacy & Security)"
