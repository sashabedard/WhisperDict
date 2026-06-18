#!/usr/bin/env bash
#
# Package WhisperDict.app into a distributable .dmg
#
# Usage: ./build.sh && ./make_dmg.sh
#
set -euo pipefail

NAME="WhisperDict"
APP="${NAME}.app"

[[ -d "$APP" ]] || { echo "ERROR: $APP not found -- run ./build.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="${NAME}-${VERSION}.dmg"

STAGING="$(mktemp -d)"
echo "-> Staging bundle + Applications alias"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "-> Building ${DMG}"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGING"

echo ""
echo "OK: built ${DMG} ($(du -h "$DMG" | cut -f1))"
echo "Opening it shows WhisperDict.app next to an Applications alias;"
echo "the user drags one onto the other to install."
