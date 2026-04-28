#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/tier0_kitty.sh
source "$script_dir/../lib/tier0_kitty.sh"

fail() {
  printf 'kitty-status-synthetic: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected=${1:?expected}
  local actual=${2:?actual}
  local label=${3:-value}

  if [[ "$expected" != "$actual" ]]; then
    fail "$label: expected '$expected' got '$actual'"
  fi
}

write_json() {
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

probe_cue_missing() {
  local tmp
  tmp="$(mktemp -d)"
  printf '%s\n' 'bash: cue: command not found' >"$tmp/stderr.txt"
  : >"$tmp/stdout.txt"
  : >"$tmp/done"
  write_json "$tmp/status.json" 127 'bash: cue: command not found' ''

  if ! tier0_wait_for_kitty_child_status "$tmp" 1; then
    fail "cue-missing probe returned nonzero: $?"
  fi

  assert_eq missing_dependency "${TIER0_KITTY_CHILD_CLASSIFICATION:-}" classification
  assert_eq cue "${TIER0_KITTY_CHILD_FAILED_CHECK:-}" failed_check
  assert_eq "cue not found inside kitty-run-shell child environment" "${TIER0_KITTY_CHILD_REASON:-}" reason
  assert_eq 127 "${TIER0_KITTY_CHILD_EXIT:-}" exit
  rm -rf -- "$tmp"
}

probe_missing_status() {
  local tmp
  tmp="$(mktemp -d)"
  : >"$tmp/done"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  local rc=$?
  set -e

  assert_eq 65 "$rc" wait_rc
  assert_eq missing_status "${TIER0_KITTY_CHILD_CLASSIFICATION:-}" classification
  assert_eq "done sentinel appeared but status.json was missing" "${TIER0_KITTY_CHILD_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_invalid_status() {
  local tmp
  tmp="$(mktemp -d)"
  : >"$tmp/done"
  printf '{not json\n' >"$tmp/status.json"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  local rc=$?
  set -e

  assert_eq 0 "$rc" wait_rc
  assert_eq invalid_status "${TIER0_KITTY_CHILD_CLASSIFICATION:-}" classification
  rm -rf -- "$tmp"
}

probe_timeout() {
  local tmp
  tmp="$(mktemp -d)"
  printf '%s\n' '{"event":"started"}' >"$tmp/started.json"

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  local rc=$?
  set -e

  assert_eq 124 "$rc" wait_rc
  assert_eq timeout "${TIER0_KITTY_CHILD_CLASSIFICATION:-}" classification
  assert_eq "timed out waiting for child done sentinel" "${TIER0_KITTY_CHILD_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_transport_failed() {
  local tmp
  tmp="$(mktemp -d)"
  printf '%s\n' '{"event":"started"}' >"$tmp/started.json"
  export TIER0_KITTY_KNOWN_OUTER_EXIT=127

  set +e
  tier0_wait_for_kitty_child_status "$tmp" 1
  local rc=$?
  set -e

  assert_eq 1 "$rc" wait_rc
  assert_eq transport_failed "${TIER0_KITTY_CHILD_CLASSIFICATION:-}" classification
  assert_eq "kitty transport failed before child status was published" "${TIER0_KITTY_CHILD_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_cue_missing
probe_missing_status
probe_invalid_status
probe_timeout
probe_transport_failed

printf '%s\n' 'kitty-status-synthetic: ok'
