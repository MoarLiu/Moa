#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${MOA_CODE_SIGN_IDENTITY:-Moa Local Development Code Signing}"
KEYCHAIN="${MOA_CODE_SIGN_KEYCHAIN:-$(/usr/bin/security default-keychain | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}"
CERT_DAYS="${MOA_CODE_SIGN_CERT_DAYS:-3650}"

if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Code signing identity already exists: $IDENTITY_NAME"
  exit 0
fi

if /usr/bin/security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "The certificate '$IDENTITY_NAME' already exists but is not a usable signing identity." >&2
  echo "Restore its original private key or Code Signing trust instead of creating a new same-name certificate." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

P12_PASSWORD="$(/usr/bin/openssl rand -hex 24)"

/usr/bin/openssl req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$TMP_DIR/key.pem" \
  -x509 \
  -days "$CERT_DAYS" \
  -out "$TMP_DIR/cert.pem" \
  -subj "/CN=$IDENTITY_NAME/O=Moa Local Development/OU=Local Development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -out "$TMP_DIR/identity.p12" \
  -inkey "$TMP_DIR/key.pem" \
  -in "$TMP_DIR/cert.pem" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$P12_PASSWORD" \
  >/dev/null 2>&1

/usr/bin/security import "$TMP_DIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$TMP_DIR/cert.pem" \
  >/dev/null

if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Created the certificate, but macOS does not report it as a valid code signing identity." >&2
  echo "Open Keychain Access and set '$IDENTITY_NAME' to Always Trust for Code Signing, then rerun this script." >&2
  exit 1
fi

echo "Created code signing identity: $IDENTITY_NAME"
