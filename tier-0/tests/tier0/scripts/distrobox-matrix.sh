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
  fi

  summary+=("$distro schema=$schema_status success=$success_status exit=$status failed=$failed_phases log=$log json=$json")
  printf '==> %s result: schema=%s success=%s exit=%s failed=%s\n' "$distro" "$schema_status" "$success_status" "$status" "$failed_phases"
done

printf '\nmatrix summary\n'
for line in "${summary[@]}"; do
  printf '%s\n' "$line"
done
