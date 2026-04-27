#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
# shellcheck source=tests/tier0/lib/tier0_harness.sh
source "$script_dir/../lib/tier0_harness.sh"

while (($# > 0)); do
  case "$1" in
    --repo)
      shift
      repo_root="${1:?missing --repo value}"
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: tests/tier0/scripts/kitty-run-shell.sh [--repo PATH]

Runs the loader-transition contract through the optional kitty run-shell backend.
USAGE
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

export TIER0_REPO_ROOT="$repo_root"
if [[ -z "${TIER0_HOST_CLASS:-}" ]]; then
  TIER0_HOST_CLASS="$(tier0_detect_host_class)"
fi
export TIER0_SHELL_BACKEND="kitty-run-shell"

tier0_prepare_home "$repo_root" "${TMPDIR:-/tmp}"
trap tier0_cleanup_home EXIT

if tier0_phase_loader_transition_contract; then
  printf '%s\n' 'kitty-run-shell loader transition passed'
  tier0_cleanup_home
  trap - EXIT
else
  status=$?
  printf '%s\n' "kitty-run-shell loader transition failed: $status" >&2
  exit "$status"
fi
