#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
report="$PWD/.build/input-check-$$.json"
trap 'rm -f "$report"' EXIT
open -n "${CLACK_INSTALL_DIR:-$HOME/Applications}/Clack.app" --args --check-input "$report"
for attempt in {1..50}; do
    if [ -s "$report" ]; then break; fi
    sleep 0.1
done
python3 - "$report" <<'PY'
import json,sys
with open(sys.argv[1]) as f: report=json.load(f)
print(json.dumps(report,sort_keys=True))
if not report['eventTapCreated']:
    print('FAIL: macOS denies the running Clack app keyboard access, regardless of the Settings switch.')
    sys.exit(1)
print('PASS: the installed Clack app can create its keyboard listener.')
PY
