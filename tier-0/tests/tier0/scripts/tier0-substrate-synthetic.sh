#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tier0_execution.sh
source "$script_dir/../lib/tier0_execution.sh"
# shellcheck source=tier0_harness.sh
source "$script_dir/../lib/tier0_harness.sh"

assert_eq() {
  local expected=${1:?expected}
  local actual=${2:?actual}
  local label=${3:?label}

  if [[ "$expected" != "$actual" ]]; then
    printf 'assertion failed: %s expected=%s actual=%s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi
}

assert_rc() {
  local expected=${1:?expected}
  local label=${2:?label}
  shift 2

  set +e
  "$@"
  local actual=$?
  set -e

  assert_eq "$expected" "$actual" "$label"
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

assert_rc 0 "tool key cue" tier0_known_tool_key cue
assert_rc 0 "command key dotctl.audit.run" tier0_known_command_key dotctl.audit.run
assert_rc 1 "tool key banana" tier0_known_tool_key banana
assert_rc 1 "command key banana" tier0_known_command_key banana

printf 'bash: cue: command not found\n' >"$tmp/cue.stderr"
assert_eq cue "$(tier0_extract_missing_dependency "$tmp/cue.stderr")" "extract cue"

printf 'bash: gh: not found\n' >"$tmp/gh.stderr"
assert_eq gh "$(tier0_extract_missing_dependency "$tmp/gh.stderr")" "extract gh"

cat >"$tmp/preflight.json" <<'JSON'
{
  "ok": false,
  "checks": [
    { "name": "just.precommit-lint", "ok": false, "reason": "precommit-lint recipe missing" }
  ]
}
JSON

classification_reason="$(tier0_classify_phase_failure precommit_lint 1 "$tmp/cue.stderr" "$tmp/preflight.json")"
classification="$(printf '%s\n' "$classification_reason" | sed -n '1p')"
reason="$(printf '%s\n' "$classification_reason" | sed -n '2p')"
assert_eq missing_command_surface "$classification" "preflight command surface classification"
assert_eq 'precommit-lint recipe missing' "$reason" "preflight recipe reason"

for needle in \
  'key: "cue"' \
  'key: "gh"' \
  'key: "just.precommit-lint"' \
  'key: "dotctl.audit.run"' \
  'key: "yadm.bootstrap.dry-run"'
do
  if ! grep -qF "$needle" "$script_dir/../policy/substrate.cue"; then
    printf 'missing substrate declaration: %s\n' "$needle" >&2
    exit 1
  fi
done

if command -v cue >/dev/null 2>&1; then
  cue eval "$script_dir/../policy/substrate.cue" -e '#DefaultTier0Substrate' >/dev/null
fi

printf '%s\n' "substrate synthetic ok"
