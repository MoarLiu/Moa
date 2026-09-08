#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${MOA_AUTO_BUMP_BUILD:-1}" != "0" ]]; then
  APP_BUILD="$(bash "$ROOT/scripts/bump-build.sh")"
  export APP_BUILD
fi

# shellcheck source=version.env
source "$ROOT/scripts/version.env"
APP_RELEASE_VERSION="${APP_RELEASE_VERSION:-$APP_VERSION}"
APP_NAME="Moa"
APP="$ROOT/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_RELEASE_VERSION-macos-$APP_ARCH.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${MOA_CODE_SIGN_IDENTITY:--}}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${MOA_NOTARY_PROFILE:-}}"

rm -rf "$DMG_ROOT" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

APP_VERSION="$APP_VERSION" \
APP_RELEASE_VERSION="$APP_RELEASE_VERSION" \
APP_BUILD="$APP_BUILD" \
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
bash "$ROOT/scripts/build-menu-bar-app.sh"

/usr/bin/codesign --verify --deep --strict "$APP"
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  if ! /usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | grep -F "Signature=adhoc" >/dev/null; then
    echo "Expected ad-hoc signed app, but the app was signed with another identity." >&2
    exit 1
  fi
else
  if ! /usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | grep -F "Authority=Developer ID Application" >/dev/null; then
    echo "Expected Developer ID Application signature for release packaging." >&2
    exit 1
  fi
fi

/usr/bin/ditto --noextattr --noacl "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
find "$DMG_ROOT" -name ".DS_Store" -delete

SENSITIVE_MATCH="$(find "$DMG_ROOT" \( \
  -name ".moa" -o \
  -name ".codex" -o \
  -name ".env" -o \
  -name ".env.*" -o \
  -name "auth.json" -o \
  -name "profiles.json" -o \
  -name "config.toml" -o \
  -name "*.key" -o \
  -name "*.pem" -o \
  -name "*.p12" -o \
  -name "*.mobileprovision" \
\) -print -quit)"

if [[ -n "$SENSITIVE_MATCH" ]]; then
  echo "Refusing to package sensitive local data: $SENSITIVE_MATCH" >&2
  find "$DMG_ROOT" \( \
    -name ".moa" -o \
    -name ".codex" -o \
    -name ".env" -o \
    -name ".env.*" -o \
    -name "auth.json" -o \
    -name "profiles.json" -o \
    -name "config.toml" -o \
    -name "*.key" -o \
    -name "*.pem" -o \
    -name "*.p12" -o \
    -name "*.mobileprovision" \
  \) -print >&2
  exit 1
fi

SENSITIVE_XATTR_MATCH="$(xattr -lr "$DMG_ROOT" 2>/dev/null | grep -E "com\\.apple\\.(lastuseddate|macl|metadata:kMDItemWhereFroms|quarantine)" | head -n 1 || true)"

if [[ -n "$SENSITIVE_XATTR_MATCH" ]]; then
  echo "Refusing to package sensitive macOS metadata: $SENSITIVE_XATTR_MATCH" >&2
  xattr -lr "$DMG_ROOT" 2>/dev/null | grep -E "com\\.apple\\.(lastuseddate|macl|metadata:kMDItemWhereFroms|quarantine)" >&2 || true
  exit 1
fi

/usr/bin/hdiutil create \
  -volname "$APP_NAME $APP_RELEASE_VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  >/dev/null

if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
  /usr/bin/codesign --verify --strict "$DMG_PATH"
  if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "$NOTARY_PROFILE" ]]; then
      echo "NOTARY_PROFILE or MOA_NOTARY_PROFILE is required when NOTARIZE=1." >&2
      exit 1
    fi
    /usr/bin/xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    /usr/bin/xcrun stapler staple "$DMG_PATH"
    /usr/bin/xcrun stapler validate "$DMG_PATH"
  fi
fi

rm -rf "$DMG_ROOT"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")"
) | tee "$CHECKSUM_PATH"
echo "Built: $DMG_PATH"
