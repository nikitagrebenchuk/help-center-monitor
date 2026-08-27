#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Help Center Monitor"
APP="$ROOT/dist/$APP_NAME.app"
ICON_FILE="$ROOT/Resources/AppIcon.icns"

if [[ -n "${HCM_SDKROOT:-}" ]]; then
  export SDKROOT="$HCM_SDKROOT"
elif [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
  # Targeting the older installed SDK keeps the binary compatible with macOS
  # 13+ and avoids a partially-updated Command Line Tools default SDK.
  export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

BINARIES=()
for ARCH in arm64 x86_64; do
  BUILD_ROOT="$ROOT/.build-$ARCH"
  WORKSPACE_MARKER="$BUILD_ROOT/.workspace-path"
  if [[ ! -f "$WORKSPACE_MARKER" ]] || [[ "$(<"$WORKSPACE_MARKER")" != "$ROOT" ]]; then
    # Swift's precompiled module cache embeds the absolute workspace path.
    # Discard only build artifacts when a checkout has moved; otherwise the
    # compiler fails before it can rebuild the manifest.
    rm -rf "$BUILD_ROOT"
  fi
  mkdir -p \
    "$BUILD_ROOT/cache" \
    "$BUILD_ROOT/config" \
    "$BUILD_ROOT/security" \
    "$BUILD_ROOT/clang-module-cache"
  print -r -- "$ROOT" > "$WORKSPACE_MARKER"
  export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"

  SWIFT_ARGS=(
    --disable-sandbox
    --disable-dependency-cache
    --manifest-cache local
    --cache-path "$BUILD_ROOT/cache"
    --config-path "$BUILD_ROOT/config"
    --security-path "$BUILD_ROOT/security"
    --scratch-path "$BUILD_ROOT"
    --arch "$ARCH"
  )

  swift build "${SWIFT_ARGS[@]}" -c release --product HelpCenterMonitor
  BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" -c release --show-bin-path)"
  BINARIES+=("$BIN_DIR/HelpCenterMonitor")
done

UNIVERSAL_DIR="$ROOT/.build/universal"
UNIVERSAL_BIN="$UNIVERSAL_DIR/HelpCenterMonitor"
mkdir -p "$UNIVERSAL_DIR"
lipo -create "${BINARIES[@]}" -output "$UNIVERSAL_BIN"
lipo "$UNIVERSAL_BIN" -verify_arch arm64 x86_64

rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Library/LaunchAgents" \
  "$APP/Contents/Resources"

install -m 755 "$UNIVERSAL_BIN" "$APP/Contents/MacOS/HelpCenterMonitor"
install -m 644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
install -m 644 "$ICON_FILE" "$APP/Contents/Resources/AppIcon.icns"
if [[ -d "$ROOT/Resources/TeamVoices" ]]; then
  ditto "$ROOT/Resources/TeamVoices" "$APP/Contents/Resources/TeamVoices"
fi
install -m 644 \
  "$ROOT/Resources/io.upwind.help-center-monitor.agent.plist" \
  "$APP/Contents/Library/LaunchAgents/io.upwind.help-center-monitor.agent.plist"

plutil -lint "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Library/LaunchAgents/io.upwind.help-center-monitor.agent.plist"

SIGN_IDENTITY="${HCM_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "Built: $APP"
