#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=version.env
source "$ROOT/scripts/version.env"
APP_NAME="Moa"
APP="$ROOT/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$MACOS/$APP_NAME"

if [[ -z "${DEVELOPER_DIR:-}" ]] &&
   [[ "$(/usr/bin/xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]] &&
   [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  echo "Using full Xcode toolchain for SwiftUI macro support: $DEVELOPER_DIR" >&2
fi

fail() {
  echo "smoke-release: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_absent() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

check_mach_o_deployment_target() {
  local executable="$1"
  local minos
  minos="$(/usr/bin/otool -l "$executable" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build = 1; next }
    in_build && $1 == "minos" { print $2; exit }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { in_min = 1; next }
    in_min && $1 == "version" { print $2; exit }
  ')"

  [[ -n "$minos" ]] || fail "missing Mach-O deployment target in $executable"
  [[ "$minos" == "$MACOS_DEPLOYMENT_TARGET" ]] ||
    fail "Mach-O deployment target mismatch in $executable: expected $MACOS_DEPLOYMENT_TARGET, got $minos"
}

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" bash "$ROOT/scripts/build-menu-bar-app.sh"

require_file "$EXECUTABLE"
require_file "$CONTENTS/Info.plist"
require_file "$RESOURCES/AppIcon.icns"
require_file "$RESOURCES/MoaMenuBarIcon.png"
require_file "$RESOURCES/en.lproj/Localizable.strings"
require_file "$RESOURCES/zh-Hans.lproj/Localizable.strings"
require_absent "$MACOS/MoaMCP"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$CONTENTS/Info.plist"
}

[[ "$(plist_value CFBundleDisplayName)" == "$APP_NAME" ]] || fail "CFBundleDisplayName is not $APP_NAME"
[[ "$(plist_value CFBundleName)" == "$APP_NAME" ]] || fail "CFBundleName is not $APP_NAME"
[[ "$(plist_value CFBundleExecutable)" == "$APP_NAME" ]] || fail "CFBundleExecutable is not $APP_NAME"
[[ "$(plist_value CFBundleIdentifier)" == "com.moarliu.moa" ]] || fail "bundle identifier is not com.moarliu.moa"
[[ "$(plist_value LSMinimumSystemVersion)" == "$MACOS_DEPLOYMENT_TARGET" ]] ||
  fail "LSMinimumSystemVersion is not $MACOS_DEPLOYMENT_TARGET"

/usr/bin/codesign --verify --deep --strict "$APP"
check_mach_o_deployment_target "$EXECUTABLE"
/usr/bin/plutil -lint "$RESOURCES/en.lproj/Localizable.strings" "$RESOURCES/zh-Hans.lproj/Localizable.strings"

if find "$APP" \( \
  -name ".moa" -o \
  -name ".codex" -o \
  -name ".workbuddy" -o \
  -name ".workbuddy-ai" -o \
  -name ".dsh" -o \
  -name ".credentials.yaml" -o \
  -name "deepseek-accounts" -o \
  -name "accounts.json" -o \
  -name "codex_official_accounts.json" -o \
  -name "claude_desktop_profiles.json" -o \
  -name "workbuddy-accounts" -o \
  -name "workbuddy-cn-accounts" -o \
  -name "workbuddy-desktop*.info" -o \
  -name "keyblob" -o \
  -name ".env" -o \
  -name ".env.*" -o \
  -name "auth.json" -o \
  -name "profiles.json" -o \
  -name "config.toml" -o \
  -name "*.key" -o \
  -name "*.pem" -o \
  -name "*.p12" -o \
  -name "*.mobileprovision" \
\) -print -quit | grep -q .; then
  fail "app bundle contains sensitive local data"
fi

"$ROOT/scripts/run-tests.sh"
/usr/bin/xcrun swift test --package-path "$ROOT" --scratch-path "$ROOT/build/swift-tests" --no-parallel

echo "Smoke release checks passed for $APP"
