#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="com.moarliu.moa.release-manifest-signing"
ACCOUNT="ed25519-private-key"
ENV_FILE="$ROOT/scripts/release-manifest.env"

if [[ -z "${DEVELOPER_DIR:-}" ]] &&
   [[ "$(/usr/bin/xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]] &&
   [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if /usr/bin/security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
  PUB_LINE="$(swift "$ROOT/scripts/sign-release-manifest.swift" pubkey --keychain)"
  PUB_KEY="${PUB_LINE#PUBLIC_KEY_BASE64=}"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=release-manifest.env
    source "$ENV_FILE"
    if [[ "${MOA_MANIFEST_PUBLIC_KEY:-}" != "$PUB_KEY" ]]; then
      echo "Keychain Ed25519 key does not match scripts/release-manifest.env." >&2
      echo "Keychain public key: $PUB_KEY" >&2
      echo "Env file public key: ${MOA_MANIFEST_PUBLIC_KEY:-<empty>}" >&2
      exit 1
    fi
  fi
  echo "Release manifest Ed25519 key already exists in Keychain: $PUB_KEY"
  exit 0
fi

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=release-manifest.env
  source "$ENV_FILE"
  if [[ -n "${MOA_MANIFEST_PUBLIC_KEY:-}" ]]; then
    echo "scripts/release-manifest.env already pins a public key ($MOA_MANIFEST_PUBLIC_KEY), but the matching private key is missing from Keychain ($SERVICE / $ACCOUNT)." >&2
    echo "Restore the original private key into Keychain instead of silently rotating keys." >&2
    exit 1
  fi
fi

KEYS="$(swift "$ROOT/scripts/sign-release-manifest.swift" keygen)"
PRIV_KEY="$(printf '%s\n' "$KEYS" | sed -n 's/^PRIVATE_KEY_BASE64=//p')"
PUB_KEY="$(printf '%s\n' "$KEYS" | sed -n 's/^PUBLIC_KEY_BASE64=//p')"

if [[ -z "$PRIV_KEY" || -z "$PUB_KEY" ]]; then
  echo "Failed to generate Ed25519 release manifest keypair." >&2
  exit 1
fi

/usr/bin/security add-generic-password \
  -s "$SERVICE" \
  -a "$ACCOUNT" \
  -l "Moa Release Manifest Ed25519 Private Key" \
  -w "$PRIV_KEY" \
  >/dev/null

cat >"$ENV_FILE" <<ENV
# Ed25519 public key (base64 raw 32 bytes) embedded into Moa.app/Contents/Info.plist
# as MoaReleaseManifestPublicKey for verifying signed GitHub Release manifests.
# The matching private key is stored locally in macOS Keychain
# (service: $SERVICE, account: $ACCOUNT) and is never committed to git.
: "\${MOA_MANIFEST_PUBLIC_KEY:=$PUB_KEY}"
ENV

echo "Created Ed25519 release manifest key in Keychain and pinned public key in scripts/release-manifest.env:"
echo "  MOA_MANIFEST_PUBLIC_KEY=$PUB_KEY"
