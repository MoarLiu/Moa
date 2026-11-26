#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=version.env
source "$ROOT/scripts/version.env"

VERSION="${APP_RELEASE_VERSION:-$APP_VERSION}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
OUT_PATH="${1:-$ROOT/Casks/moa.rb}"

fail() {
  echo "generate-homebrew-cask: $*" >&2
  exit 1
}

read_verified_sha() {
  local file="$1"
  [[ -f "$file" ]] || fail "missing checksum file: $file (package both arm64 and x86_64 DMGs first)"
  local sha
  sha="$(awk '{print tolower($1); exit}' "$file")"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA-256 digest in $file: '${sha:-<empty>}'"
  printf '%s\n' "$sha"
}

ARM64_SHA="$(read_verified_sha "$DIST_DIR/Moa-${VERSION}-macos-arm64.dmg.sha256")"
INTEL_SHA="$(read_verified_sha "$DIST_DIR/Moa-${VERSION}-macos-x86_64.dmg.sha256")"

TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/moa-cask.XXXXXX")"
trap 'rm -f "$TMP_OUT"' EXIT

cat >"$TMP_OUT" <<RUBY
cask "moa" do
  arch arm: "arm64", intel: "x86_64"

  version "${VERSION}"
  sha256 arm:   "${ARM64_SHA}",
         intel: "${INTEL_SHA}"

  url "https://github.com/MoarLiu/Moa/releases/download/v#{version}/Moa-#{version}-macos-#{arch}.dmg"
  name "Moa"
  desc "Local macOS menu bar control plane for multi-AI-agent accounts, providers, and usage"
  homepage "https://github.com/MoarLiu/Moa"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :monterey"

  app "Moa.app"
  binary "#{appdir}/Moa.app/Contents/MacOS/Moa", target: "moa"

  zap trash: [
    "~/Library/Application Support/Moa",
    "~/Library/Preferences/com.moarliu.moa.plist",
  ]
end
RUBY

if command -v ruby >/dev/null 2>&1; then
  ruby -c "$TMP_OUT" >/dev/null
fi

mkdir -p "$(dirname "$OUT_PATH")"
mv "$TMP_OUT" "$OUT_PATH"
echo "Generated Homebrew Cask: $OUT_PATH"
