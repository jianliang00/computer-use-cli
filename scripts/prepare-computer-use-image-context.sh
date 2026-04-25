#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-"$ROOT_DIR/.build/computer-use-image-context"}"
CONFIGURATION="${CONFIGURATION:-release}"

swift build -c "$CONFIGURATION" --product bootstrap-agent --package-path "$ROOT_DIR"
"$ROOT_DIR/scripts/package-computer-use-agent-app.sh" "$OUTPUT_DIR/payload/ComputerUseAgent.app" >/dev/null

rm -rf "$OUTPUT_DIR/launchd" "$OUTPUT_DIR/scripts"
mkdir -p "$OUTPUT_DIR/payload" "$OUTPUT_DIR/launchd" "$OUTPUT_DIR/scripts"

cp "$ROOT_DIR/.build/$CONFIGURATION/bootstrap-agent" "$OUTPUT_DIR/payload/bootstrap-agent"
chmod 0755 "$OUTPUT_DIR/payload/bootstrap-agent"

cp "$ROOT_DIR/images/macos/Dockerfile" "$OUTPUT_DIR/Dockerfile"
cp "$ROOT_DIR/images/macos/launchd/"*.plist "$OUTPUT_DIR/launchd/"
cp "$ROOT_DIR/images/macos/scripts/install-computer-use.sh" "$OUTPUT_DIR/scripts/"
cp "$ROOT_DIR/images/macos/scripts/configure-autologin.sh" "$OUTPUT_DIR/scripts/"
chmod 0755 "$OUTPUT_DIR/scripts/"*.sh

echo "$OUTPUT_DIR"
