#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=version.env
source "$ROOT/scripts/version.env"
APP_RELEASE_VERSION="${APP_RELEASE_VERSION:-$APP_VERSION}"
# shellcheck source=sources.env
source "$ROOT/scripts/sources.env"

APP_NAME="Moa"
APP="$ROOT/$APP_NAME.app"
# Build into a staging bundle and swap it in only after a successful compile and
# codesign. Compiling straight into $APP required deleting it first, so any
# failure (missing toolchain, SwiftUI macro plugin error, signature problem)
# left the workspace with an empty or missing Moa.app.
BUILD_WORKSPACE="$(mktemp -d "$ROOT/.moa-build.XXXXXX")"
STAGING="$BUILD_WORKSPACE/$APP_NAME.app"
BACKUP="$BUILD_WORKSPACE/previous.app"
cleanup() {
  local result=$?
  trap - EXIT
  if [[ -e "$BACKUP" ]]; then
    if [[ ! -e "$APP" ]] && mv "$BACKUP" "$APP"; then
      echo "Restored previous $APP_NAME.app after failed replacement." >&2
    else
      echo "Previous app preserved at $BACKUP; automatic restore could not complete." >&2
      exit 1
    fi
  fi
  rm -rf "$BUILD_WORKSPACE"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
CONTENTS="$STAGING/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$MACOS/$APP_NAME"
BUNDLE_ID="com.moarliu.moa"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Moa Local Development Code Signing}"

resolve_swiftc() {
  if [[ -n "${SWIFTC:-}" ]]; then
    if [[ ! -x "$SWIFTC" ]]; then
      echo "SWIFTC is not executable: $SWIFTC" >&2
      exit 1
    fi
    SWIFTC_BIN="$SWIFTC"
    SDKROOT="${SDKROOT:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
    if [[ -z "$SDKROOT" || ! -d "$SDKROOT" ]]; then
      echo "Unable to locate the macOS SDK. Set SDKROOT or DEVELOPER_DIR to a full Xcode toolchain." >&2
      exit 1
    fi
    return
  fi

  local selected_developer_dir
  selected_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ -z "${DEVELOPER_DIR:-}" ]] &&
     [[ "$selected_developer_dir" == "/Library/Developer/CommandLineTools" ]] &&
     [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "Using full Xcode toolchain for SwiftUI macro support: $DEVELOPER_DIR" >&2
  fi

  SWIFTC_BIN="$(/usr/bin/xcrun --find swiftc 2>/dev/null || true)"
  if [[ -z "$SWIFTC_BIN" || ! -x "$SWIFTC_BIN" ]]; then
    echo "Unable to locate swiftc. Set SWIFTC or DEVELOPER_DIR to a full Xcode toolchain." >&2
    exit 1
  fi
  SDKROOT="${SDKROOT:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
  if [[ -z "$SDKROOT" || ! -d "$SDKROOT" ]]; then
    echo "Unable to locate the macOS SDK. Set SDKROOT or DEVELOPER_DIR to a full Xcode toolchain." >&2
    exit 1
  fi
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

  if [[ -z "$minos" ]]; then
    echo "Missing Mach-O deployment target in $executable" >&2
    exit 1
  fi

  if [[ "$minos" != "$MACOS_DEPLOYMENT_TARGET" ]]; then
    echo "Mach-O deployment target mismatch in $executable: expected $MACOS_DEPLOYMENT_TARGET, got $minos" >&2
    exit 1
  fi

  return 0
}

MOA_APP_ABS_SOURCES=()
for source in "${MOA_APP_SOURCES[@]}"; do
  MOA_APP_ABS_SOURCES+=("$ROOT/$source")
done

resolve_swiftc

mkdir -p "$MACOS" "$RESOURCES"

MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" "$SWIFTC_BIN" \
  -target "$SWIFTC_TARGET" \
  -sdk "$SDKROOT" \
  -O \
  -framework ApplicationServices \
  -framework AppKit \
  -framework AVFoundation \
  -framework Combine \
  -framework CryptoKit \
  -framework Foundation \
  -framework ImageIO \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  "${MOA_APP_ABS_SOURCES[@]}" \
  -o "$EXECUTABLE"

chmod 755 "$EXECUTABLE"
check_mach_o_deployment_target "$EXECUTABLE"

if [[ -f "$ROOT/assets/moa-icon.icns" ]]; then
  /bin/cp -X "$ROOT/assets/moa-icon.icns" "$RESOURCES/AppIcon.icns"
fi

if [[ -f "$ROOT/assets/moa-menubar-template.png" ]]; then
  /bin/cp -X "$ROOT/assets/moa-menubar-template.png" "$RESOURCES/MoaMenuBarIcon.png"
fi

if [[ -d "$ROOT/assets/Localization" ]]; then
  while IFS= read -r -d '' lproj; do
    /bin/cp -R -X "$lproj" "$RESOURCES/$(basename "$lproj")"
  done < <(find "$ROOT/assets/Localization" -maxdepth 1 -name "*.lproj" -type d -print0)
fi

find "$RESOURCES" -name ".DS_Store" -delete

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>MoaReleaseVersion</key>
  <string>$APP_RELEASE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MACOS_DEPLOYMENT_TARGET</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$CONTENTS/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  if [[ "$CODE_SIGN_IDENTITY" != "-" ]] &&
     ! /usr/bin/security find-identity -v -p codesigning | grep -F "\"$CODE_SIGN_IDENTITY\"" >/dev/null; then
    echo "Missing code signing identity: $CODE_SIGN_IDENTITY" >&2
    echo "Run ./scripts/setup-local-code-signing.sh, or set CODE_SIGN_IDENTITY=- for ad-hoc signing." >&2
    exit 1
  fi

  if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --deep --timestamp=none --sign "$CODE_SIGN_IDENTITY" "$STAGING" >/dev/null
  else
    /usr/bin/codesign --force --deep --timestamp --options runtime --sign "$CODE_SIGN_IDENTITY" "$STAGING" >/dev/null
  fi
  /usr/bin/codesign --verify --deep --strict "$STAGING"
fi

# Keep the previous bundle until promotion succeeds. The EXIT trap restores it
# on a failed move or interruption, and preserves the backup if restore fails.
if [[ -e "$APP" ]]; then mv "$APP" "$BACKUP"; fi
mv "$STAGING" "$APP"
rm -rf "$BACKUP"

echo "Built: $APP"
