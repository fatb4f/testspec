#!/usr/bin/env bats

# shellcheck source=../lib/tier0_kitty.sh
source "$BATS_TEST_DIRNAME/../lib/tier0_kitty.sh"

write_status() {
  local path=${1:?path}
  local exit_code=${2:?exit_code}
  local stderr_excerpt=${3:-}
  local stdout_excerpt=${4:-}

  python3 - "$path" "$exit_code" "$stderr_excerpt" "$stdout_excerpt" <<'PY'
import json, os, sys
path = sys.argv[1]
exit_code = int(sys.argv[2])
stderr_excerpt = sys.argv[3]
stdout_excerpt = sys.argv[4]
data = {
    "event": "status",
    "exit": exit_code,
    "valid": True,
    "stderr_excerpt": stderr_excerpt,
    "stdout_excerpt": stdout_excerpt,
    "stderr_path": os.path.join(os.path.dirname(path), "stderr.txt"),
    "stdout_path": os.path.join(os.path.dirname(path), "stdout.txt"),
}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
os.replace(tmp, path)
PY
}

@test "kite child wrapper publishes exit status and done sentinel" {
  status_dir="$(mktemp -d)"

  run env -i HOME="$HOME" PATH="$PATH" \
    TIER0_KITTY_STATUS_DIR="$status_dir" \
    bash "$BATS_TEST_DIRNAME/../scripts/kitty-child-wrapper.sh" bash -lc 'exit 7'

  [ "$status" -eq 7 ]
  [ -s "$status_dir/status.json" ]
  [ -e "$status_dir/done" ]

  run jq -r '.exit' "$status_dir/status.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 7 ]
}

@test "classifies cue missing from synthetic status" {
  tmp="$(mktemp -d)"
  printf '%s\n' 'bash: cue: command not found' >"$tmp/stderr.txt"
  : >"$tmp/stdout.txt"
  : >"$tmp/done"
  write_status "$tmp/status.json" 127 'bash: cue: command not found' ''

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  rc=$?
  set -e

  [ "$rc" -eq 0 ]
  [ "$TIER0_KITTY_CHILD_CLASSIFICATION" = "missing_dependency" ]
  [ "$TIER0_KITTY_CHILD_FAILED_CHECK" = "cue" ]
  [ "$TIER0_KITTY_CHILD_REASON" = "cue not found inside kitty-run-shell child environment" ]
  [ "$TIER0_KITTY_CHILD_EXIT" = "127" ]
}

@test "classifies missing status from synthetic files" {
  tmp="$(mktemp -d)"
  : >"$tmp/done"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  rc=$?
  set -e

  [ "$rc" -eq 65 ]
  [ "$TIER0_KITTY_CHILD_CLASSIFICATION" = "missing_status" ]
  [ "$TIER0_KITTY_CHILD_REASON" = "done sentinel appeared but status.json was missing" ]
}

@test "classifies invalid status from synthetic files" {
  tmp="$(mktemp -d)"
  : >"$tmp/done"
  printf '{not json\n' >"$tmp/status.json"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  rc=$?
  set -e

  [ "$rc" -eq 0 ]
  [ "$TIER0_KITTY_CHILD_CLASSIFICATION" = "invalid_status" ]
}

@test "classifies timeout from synthetic files" {
  tmp="$(mktemp -d)"
  printf '%s\n' '{"event":"started"}' >"$tmp/started.json"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  rc=$?
  set -e

  [ "$rc" -eq 124 ]
  [ "$TIER0_KITTY_CHILD_CLASSIFICATION" = "timeout" ]
  [ "$TIER0_KITTY_CHILD_REASON" = "timed out waiting for child done sentinel" ]
}

@test "classifies transport failed when outer exit is known and no status is published" {
  tmp="$(mktemp -d)"
  printf '%s\n' '{"event":"started"}' >"$tmp/started.json"

  export TIER0_KITTY_KNOWN_OUTER_EXIT=127
  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  rc=$?
  set -e

  [ "$rc" -eq 1 ]
  [ "$TIER0_KITTY_CHILD_CLASSIFICATION" = "transport_failed" ]
  [ "$TIER0_KITTY_CHILD_REASON" = "kitty transport failed before child status was published" ]
}
