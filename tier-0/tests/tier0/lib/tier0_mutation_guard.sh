#!/usr/bin/env bash
# shellcheck shell=bash

tier0_mutation_guard_allowed_root() {
  local path=${1:?path}

  case "$path" in
    "$TIER0_FIXTURE_HOME"/*|"$TIER0_REPORT_DIR"/*|"$TIER0_WORKDIR"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tier0_mutation_guard_command_forbidden() {
  case "$*" in
    *"apt install"*|*"apt-get install"*|*"pacman -S"*|*"dnf install"*|*"zypper install"*|*"apk add"*)
      printf '%s\n' "package installation command observed"
      return 0
      ;;
    *"systemctl restart"*|*"systemctl enable"*|*"systemctl disable"*)
      printf '%s\n' "systemctl mutation command observed"
      return 0
      ;;
    *"loginctl"*)
      printf '%s\n' "loginctl mutation candidate observed"
      return 0
      ;;
    *"git commit"*|*"git push"*|*"git pull"*)
      printf '%s\n' "forbidden git mutation observed"
      return 0
      ;;
  esac

  return 1
}

tier0_mutation_guard_git_status() {
  local repo=${1:?repo}
  git -C "$repo" status --short --branch 2>/dev/null || true
}

tier0_mutation_guard_build_report_json() {
  local repo=${1:?repo}
  local before_status=${2:-}
  local after_status=${3:-}
  local allowed_roots_json
  local ok=true

  if [[ "$before_status" != "$after_status" ]]; then
    ok=false
  fi

  allowed_roots_json="$(jq -n \
    --arg fixture "${TIER0_FIXTURE_HOME:-}" \
    --arg report "${TIER0_REPORT_DIR:-}" \
    --arg work "${TIER0_WORKDIR:-}" \
    --arg repo "$repo" \
    '[ $fixture, $report, $work, $repo ] | map(select(length > 0)) | unique')"

  jq -n \
    --argjson ok "$ok" \
    --arg before "$before_status" \
    --arg after "$after_status" \
    --argjson allowed_roots "$allowed_roots_json" \
    '{
      ok: $ok,
      allowed_roots: $allowed_roots,
      forbidden_patterns: [
        "apt install",
        "apt-get install",
        "pacman -S",
        "dnf install",
        "zypper install",
        "apk add",
        "systemctl restart",
        "systemctl enable",
        "systemctl disable",
        "loginctl",
        "git commit",
        "git push",
        "git pull"
      ],
      before: {
        git_status: $before
      },
      after: {
        git_status: $after
      },
      events: [],
      violations: []
    }'
}
