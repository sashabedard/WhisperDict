#!/usr/bin/env bash
#
# Notarize WhisperDict.app and the distributable .dmg with Apple's notary
# service, then staple the tickets so Gatekeeper accepts them with no warning.
#
# One-time prerequisites:
#   1. Apple Developer Program membership (paid) and a "Developer ID Application"
#      certificate (Xcode → Settings → Accounts → Manage Certificates → +).
#   2. Store notary credentials once (creates a keychain profile):
#        xcrun notarytool store-credentials "whisperdict" \
#          --apple-id "sasha.touille@hotmail.fr" --team-id 7CN9557P92 \
#          --password "<app-specific-password from appleid.apple.com>"
#
# Usage:
#   ./Scripts/build.sh && ./Scripts/notarize.sh
#   NOTARY_PROFILE=whisperdict ./Scripts/notarize.sh   # override profile name
#
set -euo pipefail

# Operate from the repo root regardless of where the script is invoked.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

NAME="WhisperDict"
APP="${NAME}.app"
PROFILE="${NOTARY_PROFILE:-whisperdict}"

[[ -d "$APP" ]] || { echo "ERROR: $APP not found — run ./Scripts/build.sh first"; exit 1; }

# The app must be Developer-ID signed WITH the hardened runtime, or the notary
# service rejects it. ./Scripts/build.sh does this automatically when a
# "Developer ID Application" certificate is present.
SIGN_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
if ! grep -q "Developer ID Application" <<<"$SIGN_INFO"; then
    echo "ERROR: $APP is not signed with a Developer ID Application certificate."
    echo "       Create the cert, then re-run ./Scripts/build.sh (it will sign"
    echo "       with Developer ID + hardened runtime automatically)."
    exit 1
fi
if ! grep -Eq "flags=.*runtime" <<<"$SIGN_INFO"; then
    echo "ERROR: $APP is not signed with the hardened runtime (--options runtime)."
    echo "       Re-run ./Scripts/build.sh with a Developer ID cert present."
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="${NAME}-${VERSION}.dmg"
ZIP="${NAME}.zip"

# ── 1. Notarize the app ────────────────────────────────────────────
echo "→ Zipping $APP and submitting to the notary service (profile: $PROFILE)…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$ZIP"

echo "→ Stapling the notarization ticket into ${APP}…"
xcrun stapler staple "$APP"

# ── 2. Build the DMG from the stapled app, then notarize the DMG ───
echo "→ Building $DMG from the stapled app…"
./Scripts/make_dmg.sh

echo "→ Submitting $DMG to the notary service…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "→ Stapling the notarization ticket into $DMG…"
xcrun stapler staple "$DMG"

echo ""
echo "✓ Notarized & stapled: $DMG"
echo "  Verify the app:  xcrun stapler validate \"$APP\""
echo "  Verify the dmg:  xcrun stapler validate \"$DMG\""
echo "  Gatekeeper sim:  spctl -a -vvv \"$APP\"   (expect: source=Notarized Developer ID)"
echo ""
echo "  Once this passes you can drop the \"Open Anyway\" steps from the release notes."
