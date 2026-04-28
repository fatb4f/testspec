#!/usr/bin/env bash
# shellcheck shell=bash

tier0_backend_name() {
  printf '%s\n' "${TIER0_BACKEND:-${TIER0_SHELL_BACKEND:-headless}}"
}

tier0_backend_report_json() {
  local backend
  local kitten_found=false
  local kitten_path=""
  local kitty_present=false
  local outer_exit="${TIER0_KITTY_OUTER_EXIT:-0}"
  local transport_ok=true
  local transport_reason=""
  local classification="ok"
  local reason=""
  local child_classification="${TIER0_KITTY_CHILD_CLASSIFICATION:-}"
  local child_reason="${TIER0_KITTY_CHILD_REASON:-}"
  local child_exit="${TIER0_KITTY_CHILD_EXIT:-}"
  local child_visible="${TIER0_KITTY_CHILD_VISIBLE:-false}"
  local child_done="${TIER0_KITTY_CHILD_DONE:-false}"
  local child_valid="${TIER0_KITTY_CHILD_VALID:-false}"
  local child_failed_check="${TIER0_KITTY_CHILD_FAILED_CHECK:-}"
  local child_status_path="${TIER0_KITTY_CHILD_STATUS_PATH:-}"
  local child_done_path="${TIER0_KITTY_CHILD_DONE_PATH:-}"
  local child_started_path="${TIER0_KITTY_CHILD_STARTED_PATH:-}"
  local child_status_dir="${TIER0_KITTY_CHILD_STATUS_DIR:-}"
  local child_stderr_excerpt="${TIER0_KITTY_CHILD_STDERR_EXCERPT:-}"
  local child_stdout_excerpt="${TIER0_KITTY_CHILD_STDOUT_EXCERPT:-}"
  local required=false

  backend="$(tier0_backend_name)"

  if command -v kitten >/dev/null 2>&1; then
    kitten_found=true
    kitten_path="$(command -v kitten)"
  fi

  if command -v kitty >/dev/null 2>&1; then
    kitty_present=true
  fi

  if [[ "$backend" == "kitty-run-shell" && "$kitten_found" != true && "$kitty_present" != true ]]; then
    classification="terminal_substrate_unavailable"
    reason="kitten not found on PATH"
    transport_ok=false
    transport_reason="$reason"
  elif [[ "$backend" == "kitty-run-shell" ]]; then
    if [[ -n "$child_classification" ]]; then
      classification="$child_classification"
      reason="${child_reason:-child status published}"
      transport_reason="${TIER0_KITTY_TRANSPORT_REASON:-child status published}"
      transport_ok="${TIER0_KITTY_TRANSPORT_OK:-true}"
    else
      classification="missing_status"
      reason="${child_reason:-kitty child status missing}"
      transport_reason="${TIER0_KITTY_TRANSPORT_REASON:-kitty child status missing}"
      transport_ok=false
    fi
  else
    transport_reason="${TIER0_KITTY_TRANSPORT_REASON:-transport available}"
  fi

  jq -n \
    --arg name "$backend" \
    --argjson required "$required" \
    --arg classification "$classification" \
    --arg reason "$reason" \
    --argjson outer_exit "$outer_exit" \
    --argjson transport_ok "$transport_ok" \
    --arg transport_reason "$transport_reason" \
    --arg kitten_path "$kitten_path" \
    --argjson kitten_found "$kitten_found" \
    --argjson kitty_present "$kitty_present" \
    --arg shell_name "${SHELL:-bash}" \
    --arg backend_path "${TIER0_FIXTURE_BIN_HOME:-${TOOL_PATH_HOME:-${XDG_DATA_BIN:-}}}" \
    --arg home "${HOME:-}" \
    --arg child_classification "$child_classification" \
    --arg child_reason "$child_reason" \
    --argjson child_exit "${child_exit:-null}" \
    --argjson child_visible "${child_visible:-false}" \
    --argjson child_done "${child_done:-false}" \
    --argjson child_valid "${child_valid:-false}" \
    --arg child_failed_check "$child_failed_check" \
    --arg child_status_path "$child_status_path" \
    --arg child_done_path "$child_done_path" \
    --arg child_started_path "$child_started_path" \
    --arg child_status_dir "$child_status_dir" \
    --arg child_stderr_excerpt "$child_stderr_excerpt" \
    --arg child_stdout_excerpt "$child_stdout_excerpt" \
    '{
      name:$name,
      required:$required,
      ok:($classification == "ok"),
      classification:$classification,
      reason:$reason,
      transport:{
        outer_exit:$outer_exit,
        ok:$transport_ok,
        reason:$transport_reason,
        name:$name,
        kitten:{found:$kitten_found, path:$kitten_path},
        kitty:{present:$kitty_present},
        shell:{name:$shell_name, mode:"run-shell"}
      },
      child: (
        if $name == "kitty-run-shell" then
          {
            status_dir:$child_status_dir,
            status_path:$child_status_path,
            done_path:$child_done_path,
            started_path:$child_started_path,
            visible:$child_visible,
            done:$child_done,
            valid:$child_valid,
            exit:(if $child_classification == "" then null else $child_exit end),
            classification:(if $child_classification == "" then "missing_status" else $child_classification end),
            failed_check:$child_failed_check,
            reason:$child_reason
            ,
            stderr_excerpt:$child_stderr_excerpt,
            stdout_excerpt:$child_stdout_excerpt
          }
        else
          null
        end
      ),
      fixture:{
        home:$home,
        tool_path_home:$backend_path,
        xdg_bin_home:($backend_path)
      }
    }'
}
