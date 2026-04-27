#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
debian_container="${TIER0_DEBIAN_CONTAINER:-tier0-debian}"
arch_container="${TIER0_ARCH_CONTAINER:-tier0-arch}"
containers=("$debian_container:debian-base" "$arch_container:arch-base")

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

for item in "${containers[@]}"; do
  name=${item%%:*}
  host_class=${item#*:}
  printf '==> %s [%s]\n' "$name" "$host_class"
  distrobox-enter "$name" -- bash -lc "cd $(printf '%q' "$repo_root") && TIER0_HOST_CLASS=$(printf '%q' "$host_class") ./tests/tier0/run.sh --all"
done
