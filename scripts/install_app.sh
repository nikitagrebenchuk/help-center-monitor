#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/dist/Help Center Monitor.app"
SYSTEM_APP="/Applications/Help Center Monitor.app"
USER_APP="$HOME/Applications/Help Center Monitor.app"
if [[ -d "$SYSTEM_APP" ]]; then
  INSTALL_DIR="/Applications"
elif [[ -d "$USER_APP" ]]; then
  INSTALL_DIR="$HOME/Applications"
else
  INSTALL_DIR="$HOME/Applications"
fi
INSTALLED_APP="$INSTALL_DIR/Help Center Monitor.app"

"$ROOT/scripts/build_app.sh"

# Replacing an application bundle does not replace a process that is already
# running from it. Quit the old process first so reopening always launches the
# newly installed executable and UI.
if pgrep -x "HelpCenterMonitor" >/dev/null 2>&1; then
  osascript -e 'tell application id "io.upwind.help-center-monitor" to quit' >/dev/null 2>&1 || true
  for _ in {1..40}; do
    if ! pgrep -x "HelpCenterMonitor" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi
if pgrep -x "HelpCenterMonitor" >/dev/null 2>&1; then
  pkill -TERM -x "HelpCenterMonitor"
  for _ in {1..40}; do
    if ! pgrep -x "HelpCenterMonitor" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi
if pgrep -x "HelpCenterMonitor" >/dev/null 2>&1; then
  echo "Could not stop the currently running Help Center Monitor." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
BACKUP_APP="$INSTALL_DIR/.Help Center Monitor.previous.app"
rm -rf "$BACKUP_APP"
if [[ -d "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$BACKUP_APP"
fi
if ! ditto "$SOURCE_APP" "$INSTALLED_APP"; then
  rm -rf "$INSTALLED_APP"
  if [[ -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALLED_APP"
  fi
  exit 1
fi
codesign --verify --deep --strict "$INSTALLED_APP"
rm -rf "$BACKUP_APP"
open -n "$INSTALLED_APP"
# A normal launch keeps this menu-bar app unobtrusive. Reopen it once after an
# update so the freshly installed control window is visible for verification.
sleep 0.5
open "$INSTALLED_APP"

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED_APP/Contents/Info.plist")"
echo "Installed: $INSTALLED_APP (version $INSTALLED_VERSION)"

LEGACY_PLIST="$HOME/Library/LaunchAgents/io.upwind.help-center-monitor.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
  echo "Warning: the legacy Python LaunchAgent still exists at:"
  echo "  $LEGACY_PLIST"
  echo "Disable that old job after confirming the native app is monitoring, or both will run."
fi
