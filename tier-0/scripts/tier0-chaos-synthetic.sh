#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
# shellcheck source=tier-0/tests/tier0/lib/tier0_chaos.sh
source "$repo_root/tier-0/tests/tier0/lib/tier0_chaos.sh"

work="$(mktemp -d)"
summary="$work/chaos-summary.json"
cases_json="$work/cases.json"

clone_repo() {
  local dest=${1:?dest}
  mkdir -p "$dest"
  tar -C "$repo_root" -cf - . | tar -C "$dest" -xf -
}

stage_host_control_plane() {
  local dest=${1:?dest}
  local source_home="${HOME:?HOME}"
  local rel

  for rel in \
    .config/shell \
    .config/dotctl \
    .config/yadm \
    .config/dotfiles-audit \
    Justfile
  do
    if [[ -e "$source_home/$rel" || -L "$source_home/$rel" ]]; then
      mkdir -p "$dest/$(dirname -- "$rel")"
      cp -a -- "$source_home/$rel" "$dest/$rel"
    fi
  done
}

case_report_path() {
  local case_name=${1:?case}
  printf '%s/results/tier0-robustness-%s.json' "$work/$case_name" "$case_name"
}

observed_cases=()

for case_name in $(tier0_chaos_cases); do
  case_root="$work/$case_name"
  clone_repo "$case_root"
  stage_host_control_plane "$case_root"

  expected="$(tier0_chaos_case_json "$case_name")"
  expected_phase="$(jq -r '.expected_phase' <<<"$expected")"
  expected_classification="$(jq -r '.expected_classification' <<<"$expected")"
  expected_failed_check="$(jq -r '.expected_failed_check // empty' <<<"$expected")"

  export TIER0_CHAOS_CASE="$case_name"
  export TIER0_CHAOS_STRICT=1
  export TIER0_MODE="unit"
  export TIER0_HOST_CLASS="debian-base"
  export TIER0_DISTRO="$case_name"
  export TIER0_REPORT_DIR="$case_root/results"

  mkdir -p "$TIER0_REPORT_DIR"

  if bash "$case_root/tier-0/tests/tier0/run.sh" --phase "$expected_phase" --repo "$case_root" >"$case_root/run.log" 2>&1; then
    :
  fi

  report="$(case_report_path "$case_name")"
  if [[ ! -r "$report" ]]; then
    printf 'missing chaos report: %s\n' "$report" >&2
    exit 1
  fi

  observed="$(jq -n \
    --arg case "$case_name" \
    --arg expected_phase "$expected_phase" \
    --arg expected_classification "$expected_classification" \
    --arg expected_failed_check "$expected_failed_check" \
    --slurpfile report "$report" \
    '($report[0].phases | map(select(.name == $expected_phase)) | .[0]) as $phase
     | {
         name: $case,
         expected: {
           phase: $expected_phase,
           classification: $expected_classification,
           failed_check: ($expected_failed_check | select(length > 0))
         },
         observed: {
           phase: $phase.name,
           classification: ($phase.classification // "unknown"),
           failed_check: ($phase.failed_check // $phase.preflight_failed_check // $phase.execution.failed_check // ""),
           reason: ($phase.reason // $phase.preflight_failed_reason // $phase.execution.reason // "")
         },
         ok: (
           ($report[0].chaos.enabled == true)
           and ($phase.classification == $expected_classification)
           and (($phase.failed_check // $phase.preflight_failed_check // $phase.execution.failed_check // "") == ($expected_failed_check // ""))
         )
       }')"

  observed_cases+=("$observed")
done

jq -n \
  --argjson cases "$(printf '%s\n' "${observed_cases[@]}" | jq -s '.')" \
  '{
    schema: "tier0.chaos.report.v0",
    ok: (all($cases[]; .ok == true)),
    cases: $cases
  }' >"$summary"

jq -e '.ok == true' "$summary" >/dev/null

printf 'tier0 chaos synthetic ok: %s\n' "$summary"
