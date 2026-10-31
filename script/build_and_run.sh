#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Moa"
BUNDLE_ID="com.moarliu.moa"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

"$ROOT_DIR/scripts/build-menu-bar-app.sh"

open_app() {
  local host_arch app_arch
  host_arch="$(uname -m)"
  app_arch="$(/usr/bin/lipo -archs "$APP_BINARY" 2>/dev/null || true)"
  if [[ "$host_arch" == "arm64" && "$app_arch" != "arm64" ]]; then
    echo "Refusing to open $APP_BUNDLE because it is ${app_arch:-unknown}. macOS would warn that this Intel-only Moa will not open on macOS 28. Rebuild the native arm64 app." >&2
    exit 1
  fi
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
