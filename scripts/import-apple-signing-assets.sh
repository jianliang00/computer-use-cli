#!/usr/bin/env bash
set -euo pipefail

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
KEYCHAIN_PATH="${SIGNING_KEYCHAIN_PATH:-"$RUNNER_TEMP/computer-use-signing.keychain-db"}"
KEYCHAIN_PASSWORD="${SIGNING_KEYCHAIN_PASSWORD:-"$(uuidgen)"}"
APP_CERT_PATH="$RUNNER_TEMP/developer-id-application.p12"
INSTALLER_CERT_PATH="$RUNNER_TEMP/developer-id-installer.p12"
NOTARY_KEY_PATH="$RUNNER_TEMP/AuthKey_${APP_STORE_CONNECT_API_KEY_ID:-missing}.p8"

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "missing required value: $name" >&2
    exit 64
  fi
}

decode_base64_secret() {
  local name="$1"
  local value="$2"
  local output_path="$3"

  require_value "$name" "$value"
  printf '%s' "$value" | /usr/bin/base64 -D > "$output_path"
  chmod 0600 "$output_path"
}

require_value APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD \
  "${APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD:-}"
require_value APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_PASSWORD \
  "${APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_PASSWORD:-}"
require_value APP_STORE_CONNECT_API_KEY_ID "${APP_STORE_CONNECT_API_KEY_ID:-}"
require_value APP_STORE_CONNECT_API_ISSUER_ID "${APP_STORE_CONNECT_API_ISSUER_ID:-}"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::add-mask::$KEYCHAIN_PASSWORD"
fi

decode_base64_secret \
  APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64 \
  "${APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64:-}" \
  "$APP_CERT_PATH"
decode_base64_secret \
  APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_BASE64 \
  "${APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_BASE64:-}" \
  "$INSTALLER_CERT_PATH"
decode_base64_secret \
  APP_STORE_CONNECT_API_KEY_BASE64 \
  "${APP_STORE_CONNECT_API_KEY_BASE64:-}" \
  "$NOTARY_KEY_PATH"

security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

existing_keychains=()
while IFS= read -r keychain; do
  keychain="${keychain#"${keychain%%[![:space:]]*}"}"
  keychain="${keychain#\"}"
  keychain="${keychain%\"}"
  if [[ -n "$keychain" && "$keychain" != "$KEYCHAIN_PATH" ]]; then
    existing_keychains+=("$keychain")
  fi
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN_PATH" "${existing_keychains[@]}"

security import "$APP_CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security import "$INSTALLER_CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -T /usr/bin/pkgbuild \
  -T /usr/bin/productsign \
  -T /usr/bin/security

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "keychain-path=$KEYCHAIN_PATH"
    echo "notary-key-path=$NOTARY_KEY_PATH"
  } >> "$GITHUB_OUTPUT"
fi

echo "Imported Apple signing assets into $KEYCHAIN_PATH"
