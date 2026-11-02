#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/code-signing.env"

PREVIEW="$ROOT/build/workspace-preview/Moa Preview.app"
SOURCE_APP="${MOA_PREVIEW_SOURCE_APP:-$ROOT/Moa.app}"
if [[ ! -x "$SOURCE_APP/Contents/MacOS/Moa" ]]; then
  echo "Build Moa.app with scripts/build-menu-bar-app.sh before previewing." >&2
  exit 1
fi

# A separate bundle identity lets UI tools distinguish this read-only preview
# from a normal Moa instance the user may already be running.
mkdir -p "$(dirname "$PREVIEW")"
/usr/bin/ditto "$SOURCE_APP" "$PREVIEW"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.moarliu.moa.workspace-preview" "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Moa Preview" "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Moa Preview" "$PREVIEW/Contents/Info.plist"
moa_resolve_signing_identity
moa_codesign "$PREVIEW" --deep --options runtime
/usr/bin/codesign --verify --deep --strict "$PREVIEW"
exec "$PREVIEW/Contents/MacOS/Moa" --workspace-preview "$@"
