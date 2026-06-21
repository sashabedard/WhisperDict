#!/usr/bin/env bash
#
# Package Pith.app into a polished, distributable .dmg with a custom
# window, background image, and drag-to-Applications layout.
#
# Uses dmgbuild (writes the layout directly, no Finder automation needed):
#   python3 -m pip install --user dmgbuild
#
# Usage: ./Scripts/build.sh && ./Scripts/make_dmg.sh
#
set -euo pipefail

# Operate from the repo root regardless of where the script is invoked.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAME="Pith"
APP="${NAME}.app"
BG="Scripts/assets/dmg_background.png"

[[ -d "$APP" ]] || { echo "ERROR: $APP not found -- run ./Scripts/build.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="${NAME}-${VERSION}.dmg"

echo "-> Generating background"
[[ -f "$BG" ]] || python3 Scripts/make_dmg_bg.py

echo "-> Building $DMG with dmgbuild"
rm -f "$DMG"
python3 -m dmgbuild -s Scripts/dmg_settings.py -D app="$APP" -D bg="$BG" "$NAME" "$DMG"

echo ""
echo "OK: built ${DMG} ($(du -h "$DMG" | cut -f1))"
