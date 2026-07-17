#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/dist/Help Center Monitor.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Help Center Monitor.app"

"$ROOT/scripts/build_app.sh"
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
rm -rf "$BACKUP_APP"
open "$INSTALLED_APP"

echo "Installed: $INSTALLED_APP"

LEGACY_PLIST="$HOME/Library/LaunchAgents/io.upwind.help-center-monitor.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
  echo "Warning: the legacy Python LaunchAgent still exists at:"
  echo "  $LEGACY_PLIST"
  echo "Disable that old job after confirming the native app is monitoring, or both will run."
fi
