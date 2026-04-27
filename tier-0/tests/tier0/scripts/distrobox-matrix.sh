#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
debian_container="${TIER0_DEBIAN_CONTAINER:-tier0-debian}"
arch_container="${TIER0_ARCH_CONTAINER:-tier0-arch}"
containers=("$debian_container:debian-base" "$arch_container:arch-base")
report_dir="${TIER0_REPORT_DIR:-$repo_root/.tier0-results}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    return 1
  }
}

container_exists() {
  local name=${1:?name}
  distrobox list --no-color 2>/dev/null | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | grep -Fx -- "$name" >/dev/null
}

require_cmd distrobox

for item in "${containers[@]}"; do
  name=${item%%:*}
  host_class=${item#*:}

  if ! container_exists "$name"; then
    printf 'missing distrobox container: %s\n' "$name" >&2
    printf 'create outside this test workflow, then rerun. suggested image class: %s\n' "$host_class" >&2
    exit 1
  fi

done

summary=()

for item in "${containers[@]}"; do
  name=${item%%:*}
  host_class=${item#*:}
  distro=${host_class%%-*}
  json="$report_dir/tier0-robustness-$distro.json"
  log="$report_dir/tier0-robustness-$distro.log"
  distro_summary="$report_dir/tier0-matrix-$distro.json"
  container_repo="/tmp/tier0-src-$distro"
  container_report_dir="/tmp/tier0-results-$distro"
  status=0
  run_cmd="$(printf 'cd %q && TIER0_MODE=unit TIER0_HOST_CLASS=%q TIER0_DISTRO=%q TIER0_REPORT_DIR=%q bash ./tier-0/tests/tier0/run.sh --all --repo %q' \
    "$container_repo" "$host_class" "$distro" "$container_report_dir" "$container_repo")"

  printf '==> %s [%s]\n' "$name" "$host_class"
  mkdir -p "$report_dir"

  if tar -C "$repo_root" -cf - . \
    | distrobox enter "$name" -- bash --noprofile --norc -lc "repo_stage=$(printf '%q' "$container_repo"); report_stage=$(printf '%q' "$container_report_dir"); rm -rf \"\$repo_stage\" \"\$report_stage\"; mkdir -p \"\$repo_stage\" \"\$report_stage\"; tar -xf - -C \"\$repo_stage\"; $run_cmd"; then
    status=0
  else
    status=$?
  fi

  if distrobox enter "$name" -- bash --noprofile --norc -lc "cat $(printf '%q' "$container_report_dir/tier0-robustness-$distro.log")" >"$log" 2>/dev/null; then
    :
  fi
  if distrobox enter "$name" -- bash --noprofile --norc -lc "cat $(printf '%q' "$container_report_dir/tier0-robustness-$distro.json")" >"$json" 2>/dev/null; then
    :
  fi

  schema_status="fail"
  success_status="fail"
  failed_phases="[]"

  if [[ -r "$json" ]]; then
    if cue vet "$repo_root/tier-0/tests/tier0/policy/robustness.cue" "$json" -d '#RobustnessReport' >/dev/null 2>&1; then
      schema_status="pass"
    fi
    if cue vet "$repo_root/tier-0/tests/tier0/policy/robustness.cue" "$repo_root/tier-0/tests/tier0/policy/success.cue" "$json" -d '#SuccessfulRobustnessReport' >/dev/null 2>&1; then
      success_status="pass"
    fi
    failed_phases="$(jq -rc '.summary.failed // []' "$json" 2>/dev/null || printf '[]')"
    failures_json="$(jq -c '
      reduce (.phases[] | select(.ok == false)) as $phase ({};
        .[$phase.name] = {
          classification: ($phase.classification // "unknown"),
          reason: ($phase.reason // ""),
          exit: $phase.exit,
          command: $phase.command,
          stderr_excerpt: ($phase.stderr_excerpt // "")
        }
      )
    ' "$json" 2>/dev/null || printf '{}')"
  else
    failures_json='{}'
  fi

  jq -n \
    --arg distro "$distro" \
    --arg host_class "$host_class" \
    --arg json "$json" \
    --arg log "$log" \
    --arg schema_result "$schema_status" \
    --arg success_result "$success_status" \
    --argjson failed_phases "$failed_phases" \
    --argjson failures "$failures_json" \
    '{
      distro:$distro,
      host_class:$host_class,
      report:{json:$json, log:$log},
      robustness: ($schema_result == "pass"),
      schema_result:$schema_result,
      success_result:$success_result,
      failed_phases:$failed_phases,
      failures:$failures
    }' >"$distro_summary"

  summary+=("$distro schema=$schema_status success=$success_status exit=$status failed=$failed_phases log=$log json=$json")
  printf '==> %s result: schema=%s success=%s exit=%s failed=%s\n' "$distro" "$schema_status" "$success_status" "$status" "$failed_phases"
done

summary_json="$report_dir/tier0-matrix-summary.json"
summary_md="$report_dir/tier0-matrix-summary.md"

jq -n \
  --slurpfile debian "$report_dir/tier0-matrix-debian.json" \
  --slurpfile arch "$report_dir/tier0-matrix-arch.json" \
  '{
    schema:"tier0.matrix.summary.v0",
    ok:(($debian[0].schema_result == "pass") and ($arch[0].schema_result == "pass") and ($debian[0].success_result == "pass") and ($arch[0].success_result == "pass")),
    distros:{debian:$debian[0], arch:$arch[0]}
  }' >"$summary_json"

{
  printf '# Tier-0 Matrix Summary\n\n'
  for distro in debian arch; do
    distro_summary="$report_dir/tier0-matrix-$distro.json"
    printf '## %s\n\n' "$distro"
    printf '%s\n' "- schema_result: $(jq -r '.schema_result' "$distro_summary")"
    printf '%s\n' "- success_result: $(jq -r '.success_result' "$distro_summary")"
    printf '%s\n\n' "- failed_phases: $(jq -cr '.failed_phases' "$distro_summary")"
    jq -r '
      .failures
      | to_entries[]
      | "- \(.key): \(.value.classification) | \(.value.reason) | exit=\(.value.exit) | command=\(.value.command) | stderr=\(.value.stderr_excerpt)"
    ' "$distro_summary" 2>/dev/null || true
    printf '\n'
  done
} >"$summary_md"

printf '\nmatrix summary\n'
for line in "${summary[@]}"; do
  printf '%s\n' "$line"
done

printf 'summary json: %s\n' "$summary_json"
printf 'summary md: %s\n' "$summary_md"
