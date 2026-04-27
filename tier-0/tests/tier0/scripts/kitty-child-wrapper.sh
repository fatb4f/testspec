#!/usr/bin/env bash
set -u

status_dir="${TIER0_KITTY_STATUS_DIR:?missing TIER0_KITTY_STATUS_DIR}"
status_path="$status_dir/status.json"
done_path="$status_dir/done"
started_path="$status_dir/started.json"

mkdir -p -- "$status_dir"

python3 - "$started_path" <<'PY'
import json
import os
import sys
import time

path = sys.argv[1]
tmp = path + ".tmp"
data = {
    "event": "started",
    "pid": os.getpid(),
    "time": time.time(),
}
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
os.replace(tmp, path)
PY

set +e
"$@"
code=$?
set -e

python3 - "$status_path" "$code" <<'PY'
import json
import os
import sys
import time

path = sys.argv[1]
code = int(sys.argv[2])
tmp = path + ".tmp"
data = {
    "event": "status",
    "exit": code,
    "valid": 0 <= code <= 255,
    "time": time.time(),
}
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
os.replace(tmp, path)
PY

: > "$done_path"

exit "$code"
