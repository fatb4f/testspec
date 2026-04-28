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

stage_fixture_root() {
  local distro=${1:?distro}
  local source_home="${TIER0_SOURCE_HOME:-$HOME}"
  local stage_root

  stage_root="$(mktemp -d "/tmp/tier0-stage-${distro}.XXXXXX")"
  tar -C "$repo_root" -cf - . | tar -C "$stage_root" -xf -

  for rel in \
    .config/shell \
    .config/dotctl \
    .config/yadm \
    .config/dotfiles-audit \
    Justfile
  do
    if [[ -e "$source_home/$rel" || -L "$source_home/$rel" ]]; then
      mkdir -p "$stage_root/$(dirname -- "$rel")"
      cp -a -- "$source_home/$rel" "$stage_root/$rel"
    fi
  done

  printf '%s\n' "$stage_root"
}

for item in "${containers[@]}"; do
  name=${item%%:*}
  host_class=${item#*:}
  distro=${host_class%%-*}
  json="$report_dir/tier0-robustness-$distro.json"
  log="$report_dir/tier0-robustness-$distro.log"
  distro_summary="$report_dir/tier0-matrix-$distro.json"
  container_repo="/tmp/tier0-src-$distro"
  container_report_dir="/tmp/tier0-state-$distro/dotctl/tier0/robustness"
  run_output="$report_dir/tier0-distrobox-$distro.out"
  host_stage=""
  status=0
  run_cmd="$(printf 'cd %q && TIER0_MODE=unit TIER0_HOST_CLASS=%q TIER0_DISTRO=%q TIER0_REPORT_DIR=%q bash ./tier-0/tests/tier0/run.sh --all --repo %q' \
    "$container_repo" "$host_class" "$distro" "$container_report_dir" "$container_repo")"

  printf '==> %s [%s]\n' "$name" "$host_class"
  mkdir -p "$report_dir"
  host_stage="$(stage_fixture_root "$distro")"

  set +e
    tar -C "$host_stage" -cf - . \
    | distrobox enter "$name" -- bash --noprofile --norc -lc "repo_stage=$(printf '%q' "$container_repo"); report_stage=$(printf '%q' "$container_report_dir"); rm -rf \"\$repo_stage\" \"\$report_stage\"; mkdir -p \"\$repo_stage\" \"\$report_stage\"; tar -xf - -C \"\$repo_stage\"; $run_cmd" \
    >"$run_output" 2>&1
  status=$?
  set -e
  rm -rf -- "$host_stage"

  cat "$run_output"

  if distrobox enter "$name" -- bash --noprofile --norc -lc "cat $(printf '%q' "$container_report_dir/tier0-robustness-$distro.log")" >"$log" 2>/dev/null; then
    :
  fi
  if distrobox enter "$name" -- bash --noprofile --norc -lc "cat $(printf '%q' "$container_report_dir/tier0-robustness-$distro.json")" >"$json" 2>/dev/null; then
    :
  fi

  schema_status="fail"
  success_status="fail"
  mutation_guard_status="fail"
  failed_phases="[]"
  missing_substrate="[]"
  missing_command_surface="[]"

  if [[ -r "$json" ]]; then
    mutation_guard_status="$(jq -r '.mutation_guard.ok // false | if . then "pass" else "fail" end' "$json" 2>/dev/null || printf 'fail')"
    schema_status="$(jq -r '.schema_ok // false | if . then "pass" else "fail" end' "$json" 2>/dev/null || printf 'fail')"
    success_status="$(jq -r '.success_ok // false | if . then "pass" else "fail" end' "$json" 2>/dev/null || printf 'fail')"
    if [[ "$schema_status" != pass && "$success_status" != pass ]]; then
      :
    fi
    failed_phases="$(jq -rc '.summary.failed // []' "$json" 2>/dev/null || printf '[]')"
    failures_json="$(jq -c '
      reduce (.phases[] | select(.ok == false)) as $phase ({};
        .[$phase.name] = {
          classification: ($phase.execution.classification // $phase.classification // "unknown"),
          reason: ($phase.execution.reason // $phase.reason // ""),
          exit: ($phase.execution.exit // $phase.exit),
          command: $phase.command,
          stderr_excerpt: ($phase.execution.stderr_excerpt // $phase.stderr_excerpt // ""),
          stdout_excerpt: ($phase.execution.stdout_excerpt // ""),
          execution: ($phase.execution // {}),
          preflight_failed_check: ($phase.preflight_failed_check // ""),
          preflight_failed_reason: ($phase.preflight_failed_reason // ""),
          preflight: ($phase.preflight // {})
        }
      )
    ' "$json" 2>/dev/null || printf '{}')"
    missing_substrate="$(jq -rc '
      reduce (
        .phases[]
        | select(.ok == false)
        | (
            (.preflight_failed_check // empty),
            (if (.execution.classification // "") == "dry_run_violation" then empty else (.execution.failed_check // empty) end)
          )
      ) as $k
        ([]; if ($k != "" and (["bash","zsh","python3","git","jq","cue","just","gh","shellcheck","shellharden","shfmt","bats","shellspec"] | index($k))) then . + [$k] else . end)
      | unique
    ' "$json" 2>/dev/null || printf '[]')"
    missing_command_surface="$(jq -rc '
      reduce (
        .phases[]
        | select(.ok == false)
        | (.preflight_failed_check // empty), (.execution.failed_check // empty)
      ) as $k
        ([]; if ($k != "" and (["just.precommit-lint","dotctl.audit.run","dotctl.doctor.check","dotctl.git.refresh","dotctl.check","yadm.bootstrap.dry-run"] | index($k))) then . + [$k] else . end)
      | unique
    ' "$json" 2>/dev/null || printf '[]')"
  else
    failures_json='{}'
  fi

  if [[ -r "$log" ]]; then
    log_missing_tools='[]'
    if log_tools_raw="$(grep -Eo '^missing required Tier-0 test tools: .*$' "$run_output" 2>/dev/null | sed 's/^missing required Tier-0 test tools: //; s/[[:space:]]\+/\n/g')"; then
      if [[ -n "$log_tools_raw" ]]; then
        log_missing_tools="$(printf '%s\n' "$log_tools_raw" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique' 2>/dev/null || printf '[]')"
      fi
    fi
    missing_substrate="$(jq -nc --argjson base "${missing_substrate:-[]}" --argjson log_tools "${log_missing_tools:-[]}" '$base + $log_tools | unique')"
  fi

  jq -n \
    --arg distro "$distro" \
    --arg host_class "$host_class" \
    --arg json "$json" \
    --arg log "$log" \
    --arg schema_result "$schema_status" \
    --arg success_result "$success_status" \
    --arg mutation_guard_result "$mutation_guard_status" \
    --argjson failed_phases "$failed_phases" \
    --argjson missing_substrate "$missing_substrate" \
    --argjson missing_command_surface "$missing_command_surface" \
    --argjson failures "$failures_json" \
    '{
      distro:$distro,
      host_class:$host_class,
      report:{json:$json, log:$log},
      robustness: ($schema_result == "pass"),
      schema_result:$schema_result,
      success_result:$success_result,
      mutation_guard_result:$mutation_guard_result,
      failed_phases:$failed_phases,
      missing_substrate:$missing_substrate,
      missing_command_surface:$missing_command_surface,
      failures:$failures
    }' >"$distro_summary"

  summary+=("$distro schema=$schema_status success=$success_status exit=$status failed=$failed_phases log=$log json=$json")
  printf '==> %s result: schema=%s success=%s mutation_guard=%s exit=%s failed=%s missing_substrate=%s missing_command_surface=%s\n' "$distro" "$schema_status" "$success_status" "$mutation_guard_status" "$status" "$failed_phases" "$missing_substrate" "$missing_command_surface"
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
      printf '%s\n' "- mutation_guard_result: $(jq -r '.mutation_guard_result // "fail"' "$distro_summary")"
      printf '%s\n\n' "- failed_phases: $(jq -cr '.failed_phases' "$distro_summary")"
      printf '%s\n\n' "- missing_substrate: $(jq -cr '.missing_substrate' "$distro_summary")"
      printf '%s\n\n' "- missing_command_surface: $(jq -cr '.missing_command_surface' "$distro_summary")"
      while IFS=$'\t' read -r phase classification reason preflight_failed_check preflight_failed_reason exit_code command; do
      [[ -n "$phase" ]] || continue
      printf '%s\n' "- $phase: $classification | $reason | preflight=$preflight_failed_check | preflight_reason=$preflight_failed_reason | exit=$exit_code | command=$command"
    done < <(
      jq -r '
        .failures
        | to_entries[]
        | [
            .key,
            (.value.classification // "unknown"),
            ((.value.reason // "") | gsub("\n"; " ")),
            (.value.preflight_failed_check // ""),
            (.value.preflight_failed_reason // ""),
            ((.value.exit // 0) | tostring),
            .value.command
          ]
        | @tsv
      ' "$distro_summary" 2>/dev/null || true
    )
    printf '\n'
  done
} >"$summary_md"

printf '\nmatrix summary\n'
for line in "${summary[@]}"; do
  printf '%s\n' "$line"
done

printf 'summary json: %s\n' "$summary_json"
printf 'summary md: %s\n' "$summary_md"
