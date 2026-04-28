#!/usr/bin/env bash
set -u

status_dir="${TIER0_KITTY_STATUS_DIR:?missing TIER0_KITTY_STATUS_DIR}"
status_path="$status_dir/status.json"
done_path="$status_dir/done"
started_path="$status_dir/started.json"
stdout_path="$status_dir/stdout.txt"
stderr_path="$status_dir/stderr.txt"

mkdir -p -- "$status_dir"
export TIER0_KITTY_CHILD_STDOUT_PATH="$stdout_path"
export TIER0_KITTY_CHILD_STDERR_PATH="$stderr_path"

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
"$@" >"$stdout_path" 2>"$stderr_path"
code=$?
set -e

python3 - "$status_path" "$code" <<'PY'
import json
import os
import sys
import time

path = sys.argv[1]
code = int(sys.argv[2])
stdout_path = os.environ.get("TIER0_KITTY_CHILD_STDOUT_PATH", "")
stderr_path = os.environ.get("TIER0_KITTY_CHILD_STDERR_PATH", "")
tmp = path + ".tmp"

def excerpt(p, limit=2000):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except FileNotFoundError:
        return ""

data = {
    "event": "status",
    "exit": code,
    "valid": 0 <= code <= 255,
    "time": time.time(),
    "stdout_path": stdout_path,
    "stderr_path": stderr_path,
    "stdout_excerpt": excerpt(stdout_path),
    "stderr_excerpt": excerpt(stderr_path),
}
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
os.replace(tmp, path)
PY

: > "$done_path"

exit "$code"
