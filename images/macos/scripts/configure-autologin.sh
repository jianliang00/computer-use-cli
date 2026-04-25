#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

USER_NAME="${1:-admin}"

# This records the intended login user. Creating /etc/kcpassword still requires
# a deployment-specific password seed and is intentionally left to the image
# authorization step.
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$USER_NAME"

echo "configured autoLoginUser=$USER_NAME"
echo "note: /etc/kcpassword must be seeded during authorized image preparation"
