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

# Signing strategy, in order of preference:
#   1. "Developer ID Application" cert  → release builds: hardened runtime +
#      secure timestamp + entitlements, so the app can be NOTARIZED
#      (./Scripts/notarize.sh). This is what removes the Gatekeeper warning.
#   2. "WhisperDict Self-Signed"        → local dev: a stable identity
#      (./Scripts/setup_signing.sh) so macOS keeps the Accessibility/Microphone
#      grants across rebuilds.
#   3. ad-hoc                           → last resort.
SELF_IDENTITY="WhisperDict Self-Signed"
ENTITLEMENTS="WhisperDict.entitlements"
# `|| true` so a no-match grep doesn't trip `set -e`/`pipefail` when no
# Developer ID cert is installed (the common local-dev case).
DEVID="$(security find-identity -p codesigning -v 2>/dev/null \
          | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)"

if [[ -n "$DEVID" ]]; then
    echo "→ Signing with '$DEVID' (hardened runtime + timestamp — notarizable)…"
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$APP"
    echo "  Next: ./Scripts/notarize.sh"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$SELF_IDENTITY"; then
    echo "→ Signing with '$SELF_IDENTITY' (local dev — not notarizable)…"
    codesign --force --deep --sign "$SELF_IDENTITY" "$APP"
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
