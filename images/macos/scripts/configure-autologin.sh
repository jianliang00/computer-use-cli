#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

USER_NAME="${1:-admin}"
PASSWORD="${2:-${AUTOLOGIN_PASSWORD:-}}"
DESTROOT="${DESTROOT:-}"

target() {
  printf '%s%s\n' "$DESTROOT" "$1"
}

write_kcpassword() {
  local password="$1"
  local output="$2"
  local output_dir
  local key=(125 137 82 35 210 188 221 234 163 185 31)
  local bytes=()
  local byte

  for byte in $(/usr/bin/printf "%s" "$password" | /usr/bin/od -An -v -t u1); do
    bytes+=("$byte")
  done

  local padded_length=$(( ((${#bytes[@]} + 11) / 12) * 12 ))
  while ((${#bytes[@]} < padded_length)); do
    bytes+=(0)
  done

  output_dir="$(/usr/bin/dirname "$output")"
  /bin/mkdir -p "$output_dir"
  : > "$output"
  local index value octal
  for index in "${!bytes[@]}"; do
    value=$(( bytes[index] ^ key[index % ${#key[@]}] ))
    octal="$(/usr/bin/printf '%03o' "$value")"
    /usr/bin/printf "\\$octal" >> "$output"
  done

  if [[ -z "$DESTROOT" ]]; then
    /usr/sbin/chown root:wheel "$output"
  else
    /usr/sbin/chown root:wheel "$output" 2>/dev/null || true
  fi
  /bin/chmod 600 "$output"
}

write_autologin_user() {
  local user_name="$1"
  local plist

  plist="$(target /Library/Preferences/com.apple.loginwindow.plist)"
  /bin/mkdir -p "$(/usr/bin/dirname "$plist")"
  if [[ ! -f "$plist" ]]; then
    /usr/bin/plutil -create xml1 "$plist"
  fi
  if /usr/bin/plutil -extract autoLoginUser raw "$plist" >/dev/null 2>&1; then
    /usr/bin/plutil -replace autoLoginUser -string "$user_name" "$plist"
  else
    /usr/bin/plutil -insert autoLoginUser -string "$user_name" "$plist"
  fi

  if [[ -z "$DESTROOT" ]]; then
    /usr/sbin/chown root:wheel "$plist"
  else
    /usr/sbin/chown root:wheel "$plist" 2>/dev/null || true
  fi
  /bin/chmod 644 "$plist"
}

write_autologin_user "$USER_NAME"

echo "configured autoLoginUser=$USER_NAME"
if [[ -n "$PASSWORD" ]]; then
  write_kcpassword "$PASSWORD" "$(target /etc/kcpassword)"
  echo "seeded /etc/kcpassword for $USER_NAME"
else
  echo "note: /etc/kcpassword was not seeded; pass a password as the second argument or AUTOLOGIN_PASSWORD"
fi
