#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-/Volumes/My Shared Files/seed}"
DESTROOT="${DESTROOT:-}"
BOOTSTRAP_LAUNCHD="${BOOTSTRAP_LAUNCHD:-auto}"
APP_SOURCE="$SOURCE_DIR/ComputerUseAgent.app"
BOOTSTRAP_SOURCE="$SOURCE_DIR/bootstrap-agent"
AGENT_PLIST_SOURCE="$SOURCE_DIR/io.github.jianliang00.computer-use.agent.plist"
BOOTSTRAP_PLIST_SOURCE="$SOURCE_DIR/io.github.jianliang00.computer-use.bootstrap.plist"
AGENT_LABEL="io.github.jianliang00.computer-use.agent"
BOOTSTRAP_LABEL="io.github.jianliang00.computer-use.bootstrap"

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "missing required path: $path" >&2
    exit 1
  fi
}

require_path "$APP_SOURCE"
require_path "$BOOTSTRAP_SOURCE"
require_path "$AGENT_PLIST_SOURCE"
require_path "$BOOTSTRAP_PLIST_SOURCE"

target() {
  printf '%s%s\n' "$DESTROOT" "$1"
}

ensure_directory() {
  local mode="$1"
  local path="$2"
  if [[ ! -d "$path" ]]; then
    install -d -m "$mode" "$path"
  fi
}

chown_required_live() {
  if [[ -z "$DESTROOT" ]]; then
    chown "$@"
  else
    chown "$@" 2>/dev/null || true
  fi
}

verify_root_wheel() {
  local path="$1"
  local owner
  owner="$(stat -f '%Su:%Sg' "$path")"
  if [[ "$owner" == "root:wheel" ]]; then
    return
  fi

  if [[ -z "$DESTROOT" ]]; then
    echo "expected root:wheel ownership for $path, got $owner" >&2
    exit 1
  fi

  echo "warning: $path reports $owner; mount the offline target with ownership enabled or install from inside the guest before boot validation" >&2
}

ensure_directory 0755 "$(target /Applications)"
ensure_directory 0755 "$(target /usr/local/libexec/computer-use)"
ensure_directory 0755 "$(target /Library/LaunchDaemons)"
ensure_directory 0755 "$(target /Library/LaunchAgents)"
ensure_directory 0755 "$(target /var/run/computer-use)"
ensure_directory 0755 "$(target /Users/admin/Library/Logs)"

rm -rf "$(target /Applications/ComputerUseAgent.app)"
cp -R "$APP_SOURCE" "$(target /Applications/ComputerUseAgent.app)"
chown_required_live -R root:wheel "$(target /Applications/ComputerUseAgent.app)"
chmod -R go-w "$(target /Applications/ComputerUseAgent.app)"
chmod 0755 "$(target /Applications/ComputerUseAgent.app/Contents/MacOS/computer-use-agent)"

install -m 0755 "$BOOTSTRAP_SOURCE" "$(target /usr/local/libexec/computer-use/bootstrap-agent)"
install -m 0644 "$BOOTSTRAP_PLIST_SOURCE" "$(target /Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist)"
install -m 0644 "$AGENT_PLIST_SOURCE" "$(target /Library/LaunchAgents/${AGENT_LABEL}.plist)"
chown_required_live root:wheel \
  "$(target /usr/local/libexec/computer-use/bootstrap-agent)" \
  "$(target /Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist)" \
  "$(target /Library/LaunchAgents/${AGENT_LABEL}.plist)"

verify_root_wheel "$(target /Applications/ComputerUseAgent.app/Contents/MacOS/computer-use-agent)"
verify_root_wheel "$(target /usr/local/libexec/computer-use/bootstrap-agent)"
verify_root_wheel "$(target /Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist)"
verify_root_wheel "$(target /Library/LaunchAgents/${AGENT_LABEL}.plist)"

/usr/bin/plutil -lint "$(target /Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist)"
/usr/bin/plutil -lint "$(target /Library/LaunchAgents/${AGENT_LABEL}.plist)"

if [[ -z "$DESTROOT" && "$BOOTSTRAP_LAUNCHD" != "0" ]]; then
  if /bin/launchctl print "system/${BOOTSTRAP_LABEL}" >/dev/null 2>&1; then
    /bin/launchctl bootout system "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist" || true
  fi
  /bin/launchctl bootstrap system "/Library/LaunchDaemons/${BOOTSTRAP_LABEL}.plist"
  /bin/launchctl kickstart -k "system/${BOOTSTRAP_LABEL}" || true

  console_user="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
  console_uid="$(stat -f '%u' /dev/console 2>/dev/null || true)"
  if [[ "$console_user" == "admin" && "$console_uid" =~ ^[0-9]+$ && "$console_uid" != "0" ]]; then
    if /bin/launchctl print "gui/${console_uid}/${AGENT_LABEL}" >/dev/null 2>&1; then
      /bin/launchctl bootout "gui/${console_uid}" "/Library/LaunchAgents/${AGENT_LABEL}.plist" || true
    fi
    /bin/launchctl bootstrap "gui/${console_uid}" "/Library/LaunchAgents/${AGENT_LABEL}.plist"
    /bin/launchctl kickstart -k "gui/${console_uid}/${AGENT_LABEL}" || true
  else
    echo "note: no active admin GUI session found; ${AGENT_LABEL} will load on the next admin login"
  fi
fi

echo "ComputerUseAgent installed at $(target /Applications/ComputerUseAgent.app)"
echo "bootstrap-agent installed at $(target /usr/local/libexec/computer-use/bootstrap-agent)"
