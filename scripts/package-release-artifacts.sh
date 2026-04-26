#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${RELEASE_VERSION:-}}"
OUTPUT_DIR="${2:-"$ROOT_DIR/.build/release-artifacts"}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUILD="${APP_BUILD:-1}"
MACOS_APP_BUNDLE_ID="${MACOS_APP_BUNDLE_ID:-com.jianliang00.computer-use-cli}"
MACOS_CODE_SIGN_IDENTIFIER_PREFIX="${MACOS_CODE_SIGN_IDENTIFIER_PREFIX:-$MACOS_APP_BUNDLE_ID}"
MACOS_SIGNING_ENABLED="${MACOS_SIGNING_ENABLED:-0}"
CREATE_INSTALLER_PKGS="${CREATE_INSTALLER_PKGS:-$MACOS_SIGNING_ENABLED}"
MACOS_NOTARIZATION_ENABLED="${MACOS_NOTARIZATION_ENABLED:-0}"
MACOS_CODE_SIGN_IDENTITY="${MACOS_CODE_SIGN_IDENTITY:-}"
MACOS_INSTALLER_SIGN_IDENTITY="${MACOS_INSTALLER_SIGN_IDENTITY:-}"
MACOS_CODE_SIGN_KEYCHAIN="${MACOS_CODE_SIGN_KEYCHAIN:-}"
NOTARYTOOL_KEYCHAIN_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"
NOTARYTOOL_KEY_PATH="${NOTARYTOOL_KEY_PATH:-}"
NOTARYTOOL_KEY_ID="${NOTARYTOOL_KEY_ID:-}"
NOTARYTOOL_ISSUER_ID="${NOTARYTOOL_ISSUER_ID:-}"
NOTARYTOOL_TIMEOUT="${NOTARYTOOL_TIMEOUT:-30m}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version> [output-dir]" >&2
  exit 64
fi

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "missing required value: $name" >&2
    exit 64
  fi
}

codesign_keychain_args=()
pkgbuild_keychain_args=()
notarytool_auth_args=()

if [[ -n "$MACOS_CODE_SIGN_KEYCHAIN" ]]; then
  codesign_keychain_args=(--keychain "$MACOS_CODE_SIGN_KEYCHAIN")
  pkgbuild_keychain_args=(--keychain "$MACOS_CODE_SIGN_KEYCHAIN")
fi

if truthy "$MACOS_SIGNING_ENABLED"; then
  require_value MACOS_CODE_SIGN_IDENTITY "$MACOS_CODE_SIGN_IDENTITY"
fi

if truthy "$CREATE_INSTALLER_PKGS" && truthy "$MACOS_SIGNING_ENABLED"; then
  require_value MACOS_INSTALLER_SIGN_IDENTITY "$MACOS_INSTALLER_SIGN_IDENTITY"
fi

if truthy "$MACOS_NOTARIZATION_ENABLED"; then
  if ! truthy "$MACOS_SIGNING_ENABLED"; then
    echo "MACOS_NOTARIZATION_ENABLED requires MACOS_SIGNING_ENABLED" >&2
    exit 64
  fi

  if [[ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]]; then
    notarytool_auth_args=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
    if [[ -n "$MACOS_CODE_SIGN_KEYCHAIN" ]]; then
      notarytool_auth_args+=(--keychain "$MACOS_CODE_SIGN_KEYCHAIN")
    fi
  else
    require_value NOTARYTOOL_KEY_PATH "$NOTARYTOOL_KEY_PATH"
    require_value NOTARYTOOL_KEY_ID "$NOTARYTOOL_KEY_ID"
    notarytool_auth_args=(--key "$NOTARYTOOL_KEY_PATH" --key-id "$NOTARYTOOL_KEY_ID")
    if [[ -n "$NOTARYTOOL_ISSUER_ID" ]]; then
      notarytool_auth_args+=(--issuer "$NOTARYTOOL_ISSUER_ID")
    fi
  fi
fi

CLI_ARCHIVE_BASENAME="computer-use-${VERSION}-macos-arm64"
GUEST_KIT_BASENAME="computer-use-guest-kit-${VERSION}-macos-arm64"
CLI_STAGING_DIR="$OUTPUT_DIR/$CLI_ARCHIVE_BASENAME"
GUEST_KIT_DIR="$OUTPUT_DIR/$GUEST_KIT_BASENAME"
APP_DIR="$OUTPUT_DIR/ComputerUseAgent.app"
PKG_ROOT_DIR="$OUTPUT_DIR/pkg-roots"
PKG_SCRIPTS_DIR="$OUTPUT_DIR/pkg-scripts"
CLI_PKG_PATH="$OUTPUT_DIR/${CLI_ARCHIVE_BASENAME}.pkg"
GUEST_KIT_PKG_PATH="$OUTPUT_DIR/${GUEST_KIT_BASENAME}.pkg"
CLI_PKG_IDENTIFIER="${MACOS_APP_BUNDLE_ID}.pkg.cli"
GUEST_KIT_PKG_IDENTIFIER="${MACOS_APP_BUNDLE_ID}.pkg.guest-kit"

sign_executable() {
  local executable_path="$1"
  local identifier="$2"

  codesign \
    --force \
    --timestamp \
    --options runtime \
    --identifier "$identifier" \
    --sign "$MACOS_CODE_SIGN_IDENTITY" \
    "${codesign_keychain_args[@]}" \
    "$executable_path"
  codesign --verify --strict --verbose=2 "$executable_path"
}

sign_app() {
  local app_path="$1"

  codesign \
    --force \
    --timestamp \
    --options runtime \
    --sign "$MACOS_CODE_SIGN_IDENTITY" \
    "${codesign_keychain_args[@]}" \
    "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
}

notarize_archive() {
  local archive_path="$1"

  xcrun notarytool submit \
    "$archive_path" \
    "${notarytool_auth_args[@]}" \
    --wait \
    --timeout "$NOTARYTOOL_TIMEOUT"
}

notarize_and_staple_app() {
  local app_path="$1"
  local notary_zip="$OUTPUT_DIR/ComputerUseAgent-${VERSION}-notary.zip"

  rm -f "$notary_zip"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_zip"
  notarize_archive "$notary_zip"
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
  rm -f "$notary_zip"
}

build_pkg() {
  local root_path="$1"
  local identifier="$2"
  local output_path="$3"
  local scripts_path="${4:-}"
  local pkgbuild_args=(
    --root "$root_path"
    --identifier "$identifier"
    --version "$VERSION"
    --install-location /
    --ownership recommended
  )

  if [[ -n "$scripts_path" ]]; then
    pkgbuild_args+=(--scripts "$scripts_path")
  fi

  if truthy "$MACOS_SIGNING_ENABLED"; then
    pkgbuild_args+=(
      --sign "$MACOS_INSTALLER_SIGN_IDENTITY"
      --timestamp
      "${pkgbuild_keychain_args[@]}"
    )
  fi

  xattr -cr "$root_path" 2>/dev/null || true
  pkgbuild "${pkgbuild_args[@]}" "$output_path"

  if truthy "$MACOS_SIGNING_ENABLED"; then
    pkgutil --check-signature "$output_path"
  fi

  if truthy "$MACOS_NOTARIZATION_ENABLED"; then
    notarize_archive "$output_path"
    xcrun stapler staple "$output_path"
    xcrun stapler validate "$output_path"
    spctl -a -vv --type install "$output_path"
  fi
}

build_cli_pkg() {
  local root_path="$PKG_ROOT_DIR/cli"

  rm -rf "$root_path"
  mkdir -p "$root_path/usr/local/bin"
  cp "$ROOT_DIR/.build/$CONFIGURATION/computer-use" "$root_path/usr/local/bin/computer-use"
  chmod 0755 "$root_path/usr/local/bin/computer-use"

  build_pkg "$root_path" "$CLI_PKG_IDENTIFIER" "$CLI_PKG_PATH"
}

write_guest_kit_postinstall() {
  local scripts_path="$1"

  mkdir -p "$scripts_path"
  cat > "$scripts_path/postinstall" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

AGENT_LABEL="io.github.jianliang00.computer-use.agent"
BOOTSTRAP_LABEL="io.github.jianliang00.computer-use.bootstrap"

ensure_directory() {
  local mode="$1"
  local path="$2"
  if [[ ! -d "$path" ]]; then
    install -d -m "$mode" "$path"
  fi
}

ensure_directory 0755 /Applications
ensure_directory 0755 /usr/local/libexec/computer-use
ensure_directory 0755 /Library/LaunchDaemons
ensure_directory 0755 /Library/LaunchAgents
ensure_directory 0755 /var/run/computer-use
ensure_directory 0755 /Users/admin/Library/Logs

chown -R root:wheel /Applications/ComputerUseAgent.app
chown root:wheel \
  /usr/local/libexec/computer-use \
  /usr/local/libexec/computer-use/bootstrap-agent \
  "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist" \
  "/Library/LaunchAgents/${AGENT_LABEL}.plist" \
  /var/run/computer-use
chmod -R go-w /Applications/ComputerUseAgent.app
chmod 0755 /Applications/ComputerUseAgent.app/Contents/MacOS/computer-use-agent
chmod 0755 /usr/local/libexec/computer-use /usr/local/libexec/computer-use/bootstrap-agent /var/run/computer-use
chmod 0644 "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist" "/Library/LaunchAgents/${AGENT_LABEL}.plist"

/usr/bin/plutil -lint "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist"
/usr/bin/plutil -lint "/Library/LaunchAgents/${AGENT_LABEL}.plist"

if /bin/launchctl print "system/${BOOTSTRAP_LABEL}" >/dev/null 2>&1; then
  /bin/launchctl bootout system "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist" || true
fi
/bin/launchctl bootstrap system "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist" || true
/bin/launchctl kickstart -k "system/${BOOTSTRAP_LABEL}" || true

console_user="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
console_uid="$(stat -f '%u' /dev/console 2>/dev/null || true)"
if [[ "$console_user" == "admin" && "$console_uid" =~ ^[0-9]+$ && "$console_uid" != "0" ]]; then
  if /bin/launchctl print "gui/${console_uid}/${AGENT_LABEL}" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/${console_uid}" "/Library/LaunchAgents/${AGENT_LABEL}.plist" || true
  fi
  /bin/launchctl bootstrap "gui/${console_uid}" "/Library/LaunchAgents/${AGENT_LABEL}.plist" || true
  /bin/launchctl kickstart -k "gui/${console_uid}/${AGENT_LABEL}" || true
fi
SCRIPT
  chmod 0755 "$scripts_path/postinstall"
}

build_guest_kit_pkg() {
  local root_path="$PKG_ROOT_DIR/guest-kit"
  local scripts_path="$PKG_SCRIPTS_DIR/guest-kit"

  rm -rf "$root_path" "$scripts_path"
  mkdir -p \
    "$root_path/Applications" \
    "$root_path/usr/local/libexec/computer-use" \
    "$root_path/Library/LaunchDaemons" \
    "$root_path/Library/LaunchAgents" \
    "$root_path/var/run/computer-use" \
    "$root_path/Users/admin/Library/Logs"

  cp -R "$APP_DIR" "$root_path/Applications/ComputerUseAgent.app"
  cp "$ROOT_DIR/.build/$CONFIGURATION/bootstrap-agent" "$root_path/usr/local/libexec/computer-use/bootstrap-agent"
  cp "$ROOT_DIR/images/macos/launchd/io.github.jianliang00.computer-use.bootstrap.plist" \
    "$root_path/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist"
  cp "$ROOT_DIR/images/macos/launchd/io.github.jianliang00.computer-use.agent.plist" \
    "$root_path/Library/LaunchAgents/io.github.jianliang00.computer-use.agent.plist"

  chmod 0755 "$root_path/usr/local/libexec/computer-use/bootstrap-agent"
  chmod 0644 "$root_path/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist"
  chmod 0644 "$root_path/Library/LaunchAgents/io.github.jianliang00.computer-use.agent.plist"

  write_guest_kit_postinstall "$scripts_path"
  build_pkg "$root_path" "$GUEST_KIT_PKG_IDENTIFIER" "$GUEST_KIT_PKG_PATH" "$scripts_path"
}

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

swift build -c "$CONFIGURATION" --product computer-use --package-path "$ROOT_DIR"
swift build -c "$CONFIGURATION" --product bootstrap-agent --package-path "$ROOT_DIR"
APP_VERSION="$VERSION" APP_BUILD="$APP_BUILD" CONFIGURATION="$CONFIGURATION" MACOS_APP_BUNDLE_ID="$MACOS_APP_BUNDLE_ID" \
  "$ROOT_DIR/scripts/package-computer-use-agent-app.sh" "$APP_DIR" >/dev/null

if truthy "$MACOS_SIGNING_ENABLED"; then
  sign_executable "$ROOT_DIR/.build/$CONFIGURATION/computer-use" "${MACOS_CODE_SIGN_IDENTIFIER_PREFIX}.cli"
  sign_executable "$ROOT_DIR/.build/$CONFIGURATION/bootstrap-agent" "${MACOS_CODE_SIGN_IDENTIFIER_PREFIX}.bootstrap-agent"
  sign_app "$APP_DIR"
fi

if truthy "$MACOS_NOTARIZATION_ENABLED"; then
  notarize_and_staple_app "$APP_DIR"
fi

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

release_files=(
  "${CLI_ARCHIVE_BASENAME}.tar.gz"
  "${GUEST_KIT_BASENAME}.tar.gz"
)

if truthy "$CREATE_INSTALLER_PKGS"; then
  build_cli_pkg
  build_guest_kit_pkg
  release_files+=(
    "${CLI_ARCHIVE_BASENAME}.pkg"
    "${GUEST_KIT_BASENAME}.pkg"
  )
fi

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "${release_files[@]}" > SHA256SUMS.txt
)

rm -rf "$APP_DIR" "$CLI_STAGING_DIR" "$GUEST_KIT_DIR" "$PKG_ROOT_DIR" "$PKG_SCRIPTS_DIR"

printf '%s\n' "$OUTPUT_DIR"
