#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/.build"
WORKSPACE_MARKER="$BUILD_ROOT/.workspace-path"

if [[ ! -f "$WORKSPACE_MARKER" ]] || [[ "$(<"$WORKSPACE_MARKER")" != "$ROOT" ]]; then
  # Swift's precompiled module cache embeds the absolute checkout path.
  # Clear only generated test artifacts when the repository has moved.
  rm -rf "$BUILD_ROOT"
fi

mkdir -p \
  "$BUILD_ROOT/cache" \
  "$BUILD_ROOT/config" \
  "$BUILD_ROOT/security" \
  "$BUILD_ROOT/clang-module-cache"
print -r -- "$ROOT" > "$WORKSPACE_MARKER"

if [[ -n "${HCM_SDKROOT:-}" ]]; then
  export SDKROOT="$HCM_SDKROOT"
elif [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
  export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"

swift run \
  --disable-sandbox \
  --disable-dependency-cache \
  --manifest-cache local \
  --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" \
  --security-path "$BUILD_ROOT/security" \
  --scratch-path "$BUILD_ROOT" \
  HelpCenterCoreSelfTest
