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
  export TIER0_KITTY_CHILD_STDOUT_PATH="${TIER0_KITTY_CHILD_STDOUT_PATH:-$status_dir/stdout.txt}"
  export TIER0_KITTY_CHILD_STDERR_PATH="${TIER0_KITTY_CHILD_STDERR_PATH:-$status_dir/stderr.txt}"

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
    command_failed|timeout|missing_status|invalid_status|child_launch_failed|terminal_substrate_unavailable|transport_failed)
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

tier0_kitty_classify_child_status() {
  local status_path=${1:?status_path}
  local child_exit=""
  local stderr_excerpt=""
  local stdout_excerpt=""
  local stderr_path=""
  local stdout_path=""
  local classification=""
  local failed_check=""
  local reason=""

  child_exit="$(jq -r '.exit // empty' "$status_path" 2>/dev/null || true)"
  stderr_excerpt="$(jq -r '.stderr_excerpt // empty' "$status_path" 2>/dev/null || true)"
  stdout_excerpt="$(jq -r '.stdout_excerpt // empty' "$status_path" 2>/dev/null || true)"
  stderr_path="$(jq -r '.stderr_path // empty' "$status_path" 2>/dev/null || true)"
  stdout_path="$(jq -r '.stdout_path // empty' "$status_path" 2>/dev/null || true)"

  if [[ "$child_exit" == 0 ]]; then
    classification="ok"
    reason="child command exited 0"
  elif [[ "$child_exit" == 127 ]]; then
    if grep -qiE 'cue(:| .*not found|.*command not found)|command not found: cue|cue: not found' <<<"$stderr_excerpt"; then
      classification="missing_dependency"
      failed_check="cue"
      reason="cue not found inside kitty-run-shell child environment"
    elif grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
      classification="missing_tool"
      failed_check="command"
      reason="child command or tool missing inside kitty-run-shell child environment"
    else
      classification="missing_dependency"
      failed_check="${TIER0_PHASE_NAME:-loader_transition_contract}"
      reason="child dependency missing inside kitty-run-shell child environment"
    fi
  elif grep -qiE 'conflicting values|incomplete value|field not allowed|policy|vet failed' <<<"$stderr_excerpt"; then
    classification="policy_reject"
    failed_check="cue"
    reason="CUE policy rejected child command output"
  elif grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
    classification="missing_dependency"
    failed_check="${TIER0_PHASE_NAME:-loader_transition_contract}"
    reason="dependency missing inside kitty-run-shell child environment"
  else
    classification="command_failed"
    failed_check="${TIER0_PHASE_NAME:-loader_transition_contract}"
    reason="child command failed"
  fi

  export TIER0_KITTY_CHILD_EXIT="$child_exit"
  export TIER0_KITTY_CHILD_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_KITTY_CHILD_STDOUT_EXCERPT="$stdout_excerpt"
  export TIER0_KITTY_CHILD_STDERR_PATH="$stderr_path"
  export TIER0_KITTY_CHILD_STDOUT_PATH="$stdout_path"
  export TIER0_KITTY_CHILD_CLASSIFICATION="$classification"
  export TIER0_KITTY_CHILD_FAILED_CHECK="$failed_check"
  export TIER0_KITTY_CHILD_REASON="$reason"
  export TIER0_KITTY_CHILD_VALID=true
  export TIER0_KITTY_CHILD_DONE=true
  export TIER0_KITTY_CHILD_VISIBLE=true
  export TIER0_KITTY_TRANSPORT_OK=true
  export TIER0_KITTY_TRANSPORT_REASON="child status published"
}

tier0_kitty_classify_child_failure_from_stderr() {
  local stderr_path=${1:?stderr_path}
  local phase_name="${TIER0_PHASE_NAME:-loader_transition_contract}"
  local stderr_excerpt=""

  if [[ -r "$stderr_path" ]]; then
    stderr_excerpt="$(head -c 2000 "$stderr_path" 2>/dev/null || true)"
  fi

  export TIER0_KITTY_CHILD_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_KITTY_CHILD_STDOUT_EXCERPT="${TIER0_KITTY_CHILD_STDOUT_EXCERPT:-}"

  if grep -qiE 'cue(:| .*not found|.*command not found)|command not found: cue|cue: not found' <<<"$stderr_excerpt"; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="missing_dependency"
    export TIER0_KITTY_CHILD_FAILED_CHECK="cue"
    export TIER0_KITTY_CHILD_REASON="cue not found inside kitty-run-shell child environment"
    export TIER0_KITTY_CHILD_EXIT="${TIER0_KITTY_CHILD_EXIT:-127}"
    return 0
  fi

  if grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="missing_tool"
    export TIER0_KITTY_CHILD_FAILED_CHECK="command"
    export TIER0_KITTY_CHILD_REASON="child command or tool missing inside kitty-run-shell child environment"
    export TIER0_KITTY_CHILD_EXIT="${TIER0_KITTY_CHILD_EXIT:-127}"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|policy|vet failed' <<<"$stderr_excerpt"; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="policy_reject"
    export TIER0_KITTY_CHILD_FAILED_CHECK="cue"
    export TIER0_KITTY_CHILD_REASON="CUE policy rejected child command output"
    export TIER0_KITTY_CHILD_EXIT="${TIER0_KITTY_CHILD_EXIT:-1}"
    return 0
  fi

  if [[ -n "$stderr_excerpt" ]]; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="command_failed"
    export TIER0_KITTY_CHILD_FAILED_CHECK="$phase_name"
    export TIER0_KITTY_CHILD_REASON="child command failed"
    export TIER0_KITTY_CHILD_EXIT="${TIER0_KITTY_CHILD_EXIT:-1}"
    return 0
  fi

  return 1
}

tier0_wait_for_kitty_child_status() {
  local status_dir=${1:?status_dir}
  local attempts=${2:-200}
  local status_path="$status_dir/status.json"
  local done_path="$status_dir/done"
  local started_path="$status_dir/started.json"
  local stderr_path="$status_dir/stderr.txt"
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
      if [[ "$valid" == true ]]; then
        tier0_kitty_classify_child_status "$status_path"
      else
        export TIER0_KITTY_CHILD_CLASSIFICATION="invalid_status"
        export TIER0_KITTY_CHILD_REASON="${reason:-status.json exists but could not be parsed}"
        export TIER0_KITTY_CHILD_EXIT="$child_exit"
        export TIER0_KITTY_TRANSPORT_OK=true
        export TIER0_KITTY_TRANSPORT_REASON="child status published"
      fi
      return 0
    fi
    sleep 0.05
    attempt=$((attempt + 1))
  done

  if [[ -e "$started_path" && ! -e "$done_path" ]]; then
    if tier0_kitty_classify_child_failure_from_stderr "$stderr_path"; then
      :
    else
      if [[ "${TIER0_KITTY_KNOWN_OUTER_EXIT:-}" != "" && "${TIER0_KITTY_KNOWN_OUTER_EXIT:-0}" -ne 0 ]]; then
        export TIER0_KITTY_CHILD_CLASSIFICATION="transport_failed"
        export TIER0_KITTY_CHILD_FAILED_CHECK="transport"
        export TIER0_KITTY_CHILD_REASON="kitty transport failed before child status was published"
      else
        export TIER0_KITTY_CHILD_CLASSIFICATION="timeout"
        export TIER0_KITTY_CHILD_REASON="timed out waiting for child done sentinel"
      fi
    fi
  elif [[ -e "$done_path" && ! -s "$status_path" ]]; then
    if tier0_kitty_classify_child_failure_from_stderr "$stderr_path"; then
      :
    else
      if [[ "${TIER0_KITTY_KNOWN_OUTER_EXIT:-}" != "" && "${TIER0_KITTY_KNOWN_OUTER_EXIT:-0}" -ne 0 ]]; then
        export TIER0_KITTY_CHILD_CLASSIFICATION="transport_failed"
        export TIER0_KITTY_CHILD_FAILED_CHECK="transport"
        export TIER0_KITTY_CHILD_REASON="kitty transport failed before child status was published"
      else
        export TIER0_KITTY_CHILD_CLASSIFICATION="missing_status"
        export TIER0_KITTY_CHILD_REASON="done sentinel appeared but status.json was missing"
      fi
    fi
  elif [[ -s "$status_path" ]]; then
    export TIER0_KITTY_CHILD_CLASSIFICATION="invalid_status"
    export TIER0_KITTY_CHILD_REASON="status.json exists but could not be parsed"
  else
    if tier0_kitty_classify_child_failure_from_stderr "$stderr_path"; then
      :
    else
      if [[ "${TIER0_KITTY_KNOWN_OUTER_EXIT:-}" != "" && "${TIER0_KITTY_KNOWN_OUTER_EXIT:-0}" -ne 0 ]]; then
        export TIER0_KITTY_CHILD_CLASSIFICATION="transport_failed"
        export TIER0_KITTY_CHILD_FAILED_CHECK="transport"
        export TIER0_KITTY_CHILD_REASON="kitty transport failed before child status was published"
      else
        export TIER0_KITTY_CHILD_CLASSIFICATION="child_launch_failed"
        export TIER0_KITTY_CHILD_REASON="child wrapper did not publish status"
      fi
    fi
  fi

  export TIER0_KITTY_CHILD_DONE="${TIER0_KITTY_CHILD_DONE:-false}"
  export TIER0_KITTY_CHILD_VISIBLE="${TIER0_KITTY_CHILD_VISIBLE:-false}"
  export TIER0_KITTY_CHILD_VALID="${TIER0_KITTY_CHILD_VALID:-false}"
  : "${TIER0_KITTY_CHILD_EXIT:=}"
  : "${TIER0_KITTY_CHILD_STDERR_EXCERPT:=}"
  : "${TIER0_KITTY_CHILD_STDOUT_EXCERPT:=}"
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
  export TIER0_PHASE_NAME="${TIER0_PHASE_NAME:-loader_transition_contract}"

  # The kitty backend is intentionally optional. If kitty is present, let it
  # launch the subshell and run the same loader-transition script inside it.
  # The transport exit code is only metadata; the child status document is
  # authoritative.
  timeout 8s \
    "${runner[@]}" \
      --cwd "$PWD" \
      env \
        TIER0_KITTY_STATUS_DIR="$status_dir" \
        TIER0_KITTY_SCRIPT_FILE="$script_file" \
        TIER0_PHASE_NAME="${TIER0_PHASE_NAME:-loader_transition_contract}" \
        bash "$child_wrapper" bash "$script_file" || outer_exit=$?

  export TIER0_KITTY_KNOWN_OUTER_EXIT="$outer_exit"
  export TIER0_KITTY_OUTER_EXIT="$outer_exit"

  wait_status=0
  if tier0_wait_for_kitty_child_status "$status_dir"; then
    wait_status=0
  else
    wait_status=$?
  fi

  local backend_report
  backend_report="$(tier0_backend_report_json)"

  if [[ -r "$TIER0_HOME/.local/state/tier0-loader-transition.json" ]]; then
    local report_file="$TIER0_HOME/.local/state/tier0-loader-transition.json"
    local report_tmp
    report_tmp="$(mktemp "${status_dir}/loader-transition.XXXXXX.json")"
    jq --argjson backend "$backend_report" '.backend=$backend' "$report_file" >"$report_tmp" && mv "$report_tmp" "$report_file"
  fi

  printf '%s\n' "$backend_report"

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
