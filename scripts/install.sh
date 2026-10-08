#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
destination="${CLACK_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$destination"
# Quit an existing instance before replacing its executable.
if pgrep -x Clack >/dev/null; then
    pkill -TERM -x Clack
    for attempt in {1..30}; do
        if ! pgrep -x Clack >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x Clack >/dev/null; then
        printf 'Clack is still running. Quit it from the menu bar and retry.\n' >&2
        exit 1
    fi
fi
ditto dist/Clack.app "$destination/Clack.app"
open "$destination/Clack.app"
printf 'Installed and opened %s/Clack.app\n' "$destination"
