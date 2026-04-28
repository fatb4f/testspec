#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd -P)"
# shellcheck source=tier0_mutation_guard.sh
source "$script_dir/../lib/tier0_mutation_guard.sh"

tmp="$(mktemp -d)"
fixture_home="$tmp/fixture-home"
report_dir="$tmp/reports"
workdir="$tmp/workdir"
mkdir -p "$fixture_home" "$report_dir" "$workdir"

export TIER0_FIXTURE_HOME="$fixture_home"
export TIER0_REPORT_DIR="$report_dir"
export TIER0_WORKDIR="$workdir"

allowed_root="$fixture_home/allowed/file.txt"
mkdir -p "$(dirname -- "$allowed_root")"
if ! tier0_mutation_guard_allowed_root "$allowed_root"; then
  printf 'allowed root rejected\n' >&2
  exit 1
fi

if tier0_mutation_guard_allowed_root "/etc/passwd"; then
  printf 'forbidden root accepted\n' >&2
  exit 1
fi

if ! reason="$(tier0_mutation_guard_command_forbidden 'apt install cue')"; then
  printf 'apt install command was not flagged\n' >&2
  exit 1
fi

if ! reason="$(tier0_mutation_guard_command_forbidden 'git push origin main')"; then
  printf 'git push command was not flagged\n' >&2
  exit 1
fi

before="$(tier0_mutation_guard_git_status "$repo_root")"
after="$before"
json="$(tier0_mutation_guard_build_report_json "$repo_root" "$before" "$after")"

if [[ "$(jq -r '.ok' <<<"$json")" != true ]]; then
  printf 'mutation guard unexpectedly failed\n' >&2
  exit 1
fi

if [[ "$(jq -r '.allowed_roots | length' <<<"$json")" -lt 3 ]]; then
  printf 'mutation guard allowed roots incomplete\n' >&2
  exit 1
fi

printf 'tier0-mutation-synthetic: ok\n'
