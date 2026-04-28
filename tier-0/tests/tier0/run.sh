#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
# shellcheck source=tests/tier0/lib/tier0_harness.sh
source "$script_dir/lib/tier0_harness.sh"

usage() {
  cat <<'USAGE'
Usage: tests/tier0/run.sh [--all|--phases|--bats|--shellspec] [--repo PATH]
       tests/tier0/run.sh [--phase NAME] [--repo PATH]

Modes:
  --all        run phase harness, Bats, and ShellSpec
  --phases    run the direct phase harness
  --bats      run Bats tests only
  --shellspec run ShellSpec tests only

Environment:
  TIER0_MODE=unit|integration      default: unit
  TIER0_HOST_CLASS=debian-base|arch-base
USAGE
}

run_phases=false
run_bats=false
run_shellspec=false
single_phase=""

if (($# == 0)); then
  run_phases=true
fi

while (($# > 0)); do
  case "$1" in
    --all)
      run_phases=true
      run_bats=true
      run_shellspec=true
      ;;
    --phases)
      run_phases=true
      ;;
    --bats)
      run_bats=true
      ;;
    --shellspec)
      run_shellspec=true
      ;;
    --repo)
      shift
      repo_root="${1:?missing --repo value}"
      ;;
    --phase)
      shift
      single_phase="${1:?missing --phase value}"
      run_phases=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

export TIER0_REPO_ROOT="$repo_root"
if [[ -n "$single_phase" ]]; then
  export TIER0_PHASE_FILTER="$single_phase"
fi

if [[ "${TIER0_MODE:-unit}" != unit ]]; then
  if ! tier0_require_tools; then
    printf 'warn: continuing Tier-0 report generation despite missing tools\n' >&2
  fi
fi
overall_status=0

if [[ -z "${TIER0_HOST_CLASS:-}" ]]; then
  TIER0_HOST_CLASS="$(tier0_detect_host_class)"
fi

report_dir="${TIER0_REPORT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotctl/tier0/robustness}"
report_distro="${TIER0_DISTRO:-$TIER0_HOST_CLASS}"
report_base="tier0-robustness-${report_distro}"
report_json="$report_dir/$report_base.json"
report_log="$report_dir/$report_base.log"

mkdir -p "$report_dir"
exec > >(tee "$report_log") 2>&1

if [[ "$run_phases" == true ]]; then
  tier0_prepare_home "$repo_root" "${TMPDIR:-/tmp}"
  trap tier0_cleanup_home EXIT
  if tier0_run_all_phases; then
    run_phases_status=0
  else
    run_phases_status=$?
  fi
  cp -a -- "$TIER0_HOME/.local/state/tier0-robustness-report.json" "$report_json"
  printf 'report: %s\n' "$report_json"
  tier0_cleanup_home
  trap - EXIT
  if [[ "$run_phases_status" -ne 0 ]]; then
    overall_status="$run_phases_status"
  fi
fi

if [[ "$run_bats" == true ]]; then
  if command -v bats >/dev/null 2>&1; then
    if TIER0_REPO_ROOT="$repo_root" bats "$script_dir/bats"; then
      :
    else
      printf 'warn: Bats runner failed; continuing because it is optional\n' >&2
    fi
  else
    printf 'warn: Bats runner unavailable; skipping optional Bats suite\n' >&2
  fi
fi

if [[ "$run_shellspec" == true ]]; then
  if command -v shellspec >/dev/null 2>&1; then
    (
      cd "$repo_root"
      if TIER0_REPO_ROOT="$repo_root" shellspec -s bash "$script_dir/shellspec"; then
        :
      else
        printf 'warn: ShellSpec runner failed; continuing because it is optional\n' >&2
      fi
    )
  else
    printf 'warn: ShellSpec runner unavailable; skipping optional ShellSpec suite\n' >&2
  fi
fi

exit "$overall_status"
