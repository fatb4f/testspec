#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/tier0_execution.sh
source "$script_dir/../lib/tier0_execution.sh"

fail() {
  printf 'tier0-execution-synthetic: %s\n' "$*" >&2
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

write_stderr() {
  local path=${1:?path}
  local content=${2:-}
  printf '%s\n' "$content" >"$path"
}

probe_precommit_recipe_missing() {
  local tmp
  tmp="$(mktemp -d)"
  write_stderr "$tmp/stderr.txt" 'Justfile does not contain recipe precommit-lint'
  tier0_classify_execution precommit_lint 1 "$tmp/stdout.txt" "$tmp/stderr.txt"
  assert_eq fixture_gap "${TIER0_EXECUTION_CLASSIFICATION:-}" classification
  assert_eq precommit-lint_recipe "${TIER0_EXECUTION_FAILED_CHECK:-}" failed_check
  assert_eq "precommit-lint recipe missing" "${TIER0_EXECUTION_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_audit_cue_missing() {
  local tmp
  tmp="$(mktemp -d)"
  write_stderr "$tmp/stderr.txt" 'bash: cue: command not found'
  : >"$tmp/stdout.txt"
  tier0_classify_execution audit_gate 127 "$tmp/stdout.txt" "$tmp/stderr.txt"
  assert_eq missing_dependency "${TIER0_EXECUTION_CLASSIFICATION:-}" classification
  assert_eq cue "${TIER0_EXECUTION_FAILED_CHECK:-}" failed_check
  assert_eq "cue missing during audit execution" "${TIER0_EXECUTION_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_doctor_python_missing() {
  local tmp
  tmp="$(mktemp -d)"
  write_stderr "$tmp/stderr.txt" 'python3: not found'
  : >"$tmp/stdout.txt"
  tier0_classify_execution doctor_graph 127 "$tmp/stdout.txt" "$tmp/stderr.txt"
  assert_eq missing_dependency "${TIER0_EXECUTION_CLASSIFICATION:-}" classification
  assert_eq python3 "${TIER0_EXECUTION_FAILED_CHECK:-}" failed_check
  assert_eq "python3 missing during doctor execution" "${TIER0_EXECUTION_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_bootstrap_dry_run_violation() {
  local tmp
  tmp="$(mktemp -d)"
  write_stderr "$tmp/stderr.txt" 'DRY_RUN=1 but attempted apt install'
  : >"$tmp/stdout.txt"
  tier0_classify_execution bootstrap_dry_run 1 "$tmp/stdout.txt" "$tmp/stderr.txt"
  assert_eq dry_run_violation "${TIER0_EXECUTION_CLASSIFICATION:-}" classification
  assert_eq dry_run "${TIER0_EXECUTION_FAILED_CHECK:-}" failed_check
  assert_eq "bootstrap dry run attempted a mutation" "${TIER0_EXECUTION_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_dotctl_check_missing() {
  local tmp
  tmp="$(mktemp -d)"
  write_stderr "$tmp/stderr.txt" 'dotctl: command not found'
  : >"$tmp/stdout.txt"
  tier0_classify_execution dotctl_check 127 "$tmp/stdout.txt" "$tmp/stderr.txt"
  assert_eq missing_tool "${TIER0_EXECUTION_CLASSIFICATION:-}" classification
  assert_eq dotctl "${TIER0_EXECUTION_FAILED_CHECK:-}" failed_check
  assert_eq "dotctl missing during execution" "${TIER0_EXECUTION_REASON:-}" reason
  rm -rf -- "$tmp"
}

probe_precommit_recipe_missing
probe_audit_cue_missing
probe_doctor_python_missing
probe_bootstrap_dry_run_violation
probe_dotctl_check_missing

printf '%s\n' 'tier0-execution-synthetic: ok'
