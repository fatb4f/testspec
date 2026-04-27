#!/usr/bin/env bash
# shellcheck shell=bash

tier0_kitty_prepare_status_dir() {
  local status_dir

  status_dir="$(mktemp -d "${TIER0_HOME}/.local/state/tier0-kitty-run-shell.XXXXXX")"
  printf '%s\n' "$status_dir"
}

tier0_kitty_publish_child_state() {
  local status_dir=${1:?status_dir}
  local classification=${2:-}
  local reason=${3:-}
  local exit_code=${4:-}

  export TIER0_KITTY_CHILD_STATUS_DIR="$status_dir"
  export TIER0_KITTY_CHILD_STATUS_PATH="$status_dir/status.json"
  export TIER0_KITTY_CHILD_DONE_PATH="$status_dir/done"
  export TIER0_KITTY_CHILD_STARTED_PATH="$status_dir/started.json"

  case "$classification" in
    ok)
      export TIER0_KITTY_CHILD_VISIBLE=true
      export TIER0_KITTY_CHILD_DONE=true
      export TIER0_KITTY_CHILD_VALID=true
      export TIER0_KITTY_CHILD_CLASSIFICATION="ok"
      export TIER0_KITTY_CHILD_REASON="${reason:-child command exited 0}"
      export TIER0_KITTY_CHILD_EXIT="${exit_code:-0}"
      export TIER0_KITTY_TRANSPORT_OK=true
      export TIER0_KITTY_TRANSPORT_REASON="child status published"
      ;;
    command_failed|timeout|missing_status|invalid_status|child_launch_failed|terminal_substrate_unavailable)
      export TIER0_KITTY_CHILD_VISIBLE=true
      export TIER0_KITTY_CHILD_DONE=true
      export TIER0_KITTY_CHILD_VALID=true
      export TIER0_KITTY_CHILD_CLASSIFICATION="$classification"
      export TIER0_KITTY_CHILD_REASON="${reason:-}"
      export TIER0_KITTY_CHILD_EXIT="${exit_code:-124}"
      export TIER0_KITTY_TRANSPORT_OK=true
      export TIER0_KITTY_TRANSPORT_REASON="child status published"
      ;;
    *)
      export TIER0_KITTY_CHILD_VISIBLE=false
      export TIER0_KITTY_CHILD_DONE=false
      export TIER0_KITTY_CHILD_VALID=false
      export TIER0_KITTY_CHILD_CLASSIFICATION="missing_status"
      export TIER0_KITTY_CHILD_REASON="${reason:-unknown kitty child state}"
      export TIER0_KITTY_CHILD_EXIT=""
      export TIER0_KITTY_TRANSPORT_OK=false
      export TIER0_KITTY_TRANSPORT_REASON="${reason:-kitty transport unavailable}"
      ;;
  esac
}

tier0_wait_for_kitty_child_status() {
  local status_dir=${1:?status_dir}
  local attempts=${2:-200}
  local status_path="$status_dir/status.json"
  local done_path="$status_dir/done"
  local started_path="$status_dir/started.json"
  local attempt=0
  local child_exit=""
  local valid=""
  local classification=""
  local reason=""

  export TIER0_KITTY_CHILD_STATUS_DIR="$status_dir"
  export TIER0_KITTY_CHILD_STATUS_PATH="$status_path"
  export TIER0_KITTY_CHILD_DONE_PATH="$done_path"
  export TIER0_KITTY_CHILD_STARTED_PATH="$started_path"
  export TIER0_KITTY_CHILD_VISIBLE=false
  export TIER0_KITTY_CHILD_DONE=false
  export TIER0_KITTY_KNOWN_OUTER_EXIT="${TIER0_KITTY_KNOWN_OUTER_EXIT:-}"

  while ((attempt < attempts)); do
    if [[ -e "$started_path" ]]; then
      export TIER0_KITTY_CHILD_VISIBLE=true
    fi
    if [[ -e "$done_path" ]]; then
      export TIER0_KITTY_CHILD_DONE=true
    fi
    if [[ -s "$status_path" ]]; then
      child_exit="$(jq -r '.exit // empty' "$status_path" 2>/dev/null || true)"
      valid="$(jq -r 'if (.valid == true) then "true" else "false" end' "$status_path" 2>/dev/null || printf 'false')"
      classification="$(jq -r '.classification // empty' "$status_path" 2>/dev/null || true)"
      reason="$(jq -r '.reason // empty' "$status_path" 2>/dev/null || true)"
      export TIER0_KITTY_CHILD_VALID="$valid"
      export TIER0_KITTY_CHILD_CLASSIFICATION="${classification:-invalid_status}"
      export TIER0_KITTY_CHILD_REASON="$reason"
      export TIER0_KITTY_CHILD_EXIT="$child_exit"
      export TIER0_KITTY_TRANSPORT_OK=true
      export TIER0_KITTY_TRANSPORT_REASON="child status published"
      return 0
    fi
    sleep 0.05
    attempt=$((attempt + 1))
  done

  if [[ -e "$started_path" && ! -e "$done_path" ]]; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="timeout"
    export TIER0_KITTY_CHILD_REASON="timed out waiting for child done sentinel"
  elif [[ -e "$done_path" && ! -s "$status_path" ]]; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="missing_status"
    export TIER0_KITTY_CHILD_REASON="done sentinel appeared but status.json was missing"
  elif [[ -s "$status_path" ]]; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="invalid_status"
    export TIER0_KITTY_CHILD_REASON="status.json exists but could not be parsed"
  else
    export TIER0_KITTY_CHILD_CLASSIFICATION="child_launch_failed"
    export TIER0_KITTY_CHILD_REASON="child wrapper did not publish status"
  fi

  export TIER0_KITTY_CHILD_DONE="${TIER0_KITTY_CHILD_DONE:-false}"
  export TIER0_KITTY_CHILD_VISIBLE="${TIER0_KITTY_CHILD_VISIBLE:-false}"
  export TIER0_KITTY_CHILD_VALID=false
  export TIER0_KITTY_CHILD_EXIT=""
  export TIER0_KITTY_TRANSPORT_OK=false
  export TIER0_KITTY_TRANSPORT_REASON="$TIER0_KITTY_CHILD_REASON"

  case "$TIER0_KITTY_CHILD_CLASSIFICATION" in
    timeout) return 124 ;;
    missing_status|invalid_status) return 65 ;;
    child_launch_failed) return 127 ;;
    terminal_substrate_unavailable) return 127 ;;
    *) return 1 ;;
  esac
}

tier0_kitty_run_shell() {
  local script_file=${1:?script_file}
  local -a runner=()
  local status_dir
  local outer_exit=124
  local wait_status=0
  local child_wrapper

  if command -v kitten >/dev/null 2>&1; then
    runner=(kitten run-shell --shell=/bin/bash)
  elif command -v kitty >/dev/null 2>&1; then
    runner=(kitty +kitten run-shell --shell=/bin/bash)
  else
    printf '%s\n' 'kitty run-shell backend unavailable: kitten/kitty missing' >&2
    tier0_kitty_publish_child_state "${TIER0_HOME}/.local/state/tier0-kitty-run-shell-missing" terminal_substrate_unavailable "kitten not found on PATH" 127
    return 127
  fi

  status_dir="$(tier0_kitty_prepare_status_dir)"
  child_wrapper="$TIER0_REPO_ROOT/tier-0/tests/tier0/scripts/kitty-child-wrapper.sh"
  export TIER0_KITTY_STATUS_DIR="$status_dir"
  export TIER0_KITTY_CHILD_STATUS_DIR="$status_dir"
  export TIER0_KITTY_CHILD_STATUS_PATH="$status_dir/status.json"
  export TIER0_KITTY_CHILD_DONE_PATH="$status_dir/done"
  export TIER0_KITTY_CHILD_STARTED_PATH="$status_dir/started.json"

  # The kitty backend is intentionally optional. If kitty is present, let it
  # launch the subshell and run the same loader-transition script inside it.
  # The transport exit code is only metadata; the child status document is
  # authoritative.
  tier0_clean_env /bin/bash timeout 8s env \
    TIER0_BACKEND="kitty-run-shell" \
    TIER0_KITTY_STATUS_DIR="$status_dir" \
    TIER0_KITTY_SCRIPT_FILE="$script_file" \
    TIER0_KITTY_CHILD_WRAPPER="$child_wrapper" \
    PATH="$PATH" \
    HOME="$HOME" \
    XDG_BIN_HOME="${XDG_BIN_HOME:-}" \
    TOOL_PATH_HOME="${TOOL_PATH_HOME:-}" \
    TIER0_SYSTEM_PATH="${TIER0_SYSTEM_PATH:-}" \
    "${runner[@]}" \
      --cwd "$PWD" \
      --env "TIER0_KITTY_STATUS_DIR=$status_dir" \
      --env "TIER0_KITTY_SCRIPT_FILE=$script_file" \
      bash "$child_wrapper" bash "$script_file" || outer_exit=$?

  export TIER0_KITTY_KNOWN_OUTER_EXIT="$outer_exit"
  export TIER0_KITTY_OUTER_EXIT="$outer_exit"

  wait_status=0
  if tier0_wait_for_kitty_child_status "$status_dir"; then
    wait_status=0
  else
    wait_status=$?
  fi

  case "$TIER0_KITTY_CHILD_CLASSIFICATION" in
    ok)
      rm -rf -- "$status_dir"
      return "${TIER0_KITTY_CHILD_EXIT:-0}"
      ;;
    command_failed)
      rm -rf -- "$status_dir"
      return "${TIER0_KITTY_CHILD_EXIT:-1}"
      ;;
    timeout)
      rm -rf -- "$status_dir"
      return 124
      ;;
    missing_status|invalid_status|child_launch_failed|terminal_substrate_unavailable)
      rm -rf -- "$status_dir"
      case "$TIER0_KITTY_CHILD_CLASSIFICATION" in
        terminal_substrate_unavailable) return 127 ;;
        child_launch_failed) return 127 ;;
        invalid_status) return 65 ;;
        missing_status) return 65 ;;
        *) return "$wait_status" ;;
      esac
      ;;
    *)
      rm -rf -- "$status_dir"
      return "${TIER0_KITTY_CHILD_EXIT:-1}"
      ;;
  esac
}
