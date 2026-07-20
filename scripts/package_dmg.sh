#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Help Center Monitor.app"
STAGING="$ROOT/.build/dmg-root"
PRIVACY_SECURITY_SHORTCUT="$ROOT/Resources/Open Privacy & Security.inetloc"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/dist/Help Center Monitor-$VERSION.dmg"

"$ROOT/scripts/build_app.sh"
plutil -lint "$PRIVACY_SECURITY_SHORTCUT"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Help Center Monitor.app"
ln -s /Applications "$STAGING/Applications"
install -m 644 \
  "$PRIVACY_SECURITY_SHORTCUT" \
  "$STAGING/2 - After Warning - Open Privacy & Security.inetloc"
install -m 644 "$ROOT/TEAM_INSTALL.txt" "$STAGING/Read Me First.txt"

rm -f "$DMG" "$DMG.sha256"
hdiutil create \
  -volname "Help Center Monitor" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG"

if [[ -n "${HCM_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$HCM_SIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

if [[ -n "${HCM_NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${HCM_SIGN_IDENTITY:-}" ]]; then
    echo "HCM_NOTARY_PROFILE requires a Developer ID signed app."
    exit 1
  fi
  xcrun notarytool submit "$DMG" --keychain-profile "$HCM_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

# Stapling mutates the disk image, so calculate the published checksum last.
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)

echo "Packaged: $DMG"
if [[ -z "${HCM_SIGN_IDENTITY:-}" ]]; then
  echo "Unsigned internal build: distribute only through a trusted channel; recipients must approve it in Privacy & Security."
fi
