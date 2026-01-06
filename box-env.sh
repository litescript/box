# ~/src/box/box-env.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

DB=/var/lib/box
MAN="$DB/manifests"
META="$DB/meta"
LOGS="$DB/logs"
STATE="$DB/state"

# Prefer the invoking user's home when running under sudo.
USER_HOME=""
if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
USER_HOME="${USER_HOME:-$HOME}"

RECIPE_DIR="${RECIPE_DIR:-$USER_HOME/ls-box/recipes}"
