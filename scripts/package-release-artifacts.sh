#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${RELEASE_VERSION:-}}"
OUTPUT_DIR="${2:-"$ROOT_DIR/.build/release-artifacts"}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUILD="${APP_BUILD:-1}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version> [output-dir]" >&2
  exit 64
fi

CLI_ARCHIVE_BASENAME="computer-use-${VERSION}-macos-arm64"
GUEST_KIT_BASENAME="computer-use-guest-kit-${VERSION}-macos-arm64"
CLI_STAGING_DIR="$OUTPUT_DIR/$CLI_ARCHIVE_BASENAME"
GUEST_KIT_DIR="$OUTPUT_DIR/$GUEST_KIT_BASENAME"
APP_DIR="$OUTPUT_DIR/ComputerUseAgent.app"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

swift build -c "$CONFIGURATION" --product computer-use --package-path "$ROOT_DIR"
swift build -c "$CONFIGURATION" --product bootstrap-agent --package-path "$ROOT_DIR"
APP_VERSION="$VERSION" APP_BUILD="$APP_BUILD" CONFIGURATION="$CONFIGURATION" \
  "$ROOT_DIR/scripts/package-computer-use-agent-app.sh" "$APP_DIR" >/dev/null

mkdir -p "$CLI_STAGING_DIR/bin"
cp "$ROOT_DIR/.build/$CONFIGURATION/computer-use" "$CLI_STAGING_DIR/bin/computer-use"
chmod 0755 "$CLI_STAGING_DIR/bin/computer-use"
cp "$ROOT_DIR/README.md" "$CLI_STAGING_DIR/README.md"

mkdir -p "$GUEST_KIT_DIR/payload" "$GUEST_KIT_DIR/launchd" "$GUEST_KIT_DIR/scripts"
cp -R "$APP_DIR" "$GUEST_KIT_DIR/payload/ComputerUseAgent.app"
cp "$ROOT_DIR/.build/$CONFIGURATION/bootstrap-agent" "$GUEST_KIT_DIR/payload/bootstrap-agent"
chmod 0755 "$GUEST_KIT_DIR/payload/bootstrap-agent"
cp "$ROOT_DIR/images/macos/launchd/"*.plist "$GUEST_KIT_DIR/launchd/"
cp "$ROOT_DIR/images/macos/scripts/install-computer-use.sh" "$GUEST_KIT_DIR/scripts/"
cp "$ROOT_DIR/images/macos/scripts/configure-autologin.sh" "$GUEST_KIT_DIR/scripts/"
chmod 0755 "$GUEST_KIT_DIR/scripts/"*.sh
cp "$ROOT_DIR/README.md" "$GUEST_KIT_DIR/README.md"

tar -C "$OUTPUT_DIR" -czf "$OUTPUT_DIR/${CLI_ARCHIVE_BASENAME}.tar.gz" "$CLI_ARCHIVE_BASENAME"
tar -C "$OUTPUT_DIR" -czf "$OUTPUT_DIR/${GUEST_KIT_BASENAME}.tar.gz" "$GUEST_KIT_BASENAME"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 \
    "${CLI_ARCHIVE_BASENAME}.tar.gz" \
    "${GUEST_KIT_BASENAME}.tar.gz" \
    > SHA256SUMS.txt
)

rm -rf "$APP_DIR" "$CLI_STAGING_DIR" "$GUEST_KIT_DIR"

printf '%s\n' "$OUTPUT_DIR"
