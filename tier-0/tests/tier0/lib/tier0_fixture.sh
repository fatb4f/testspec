#!/usr/bin/env bash
# shellcheck shell=bash

tier0_resolved_from_fixture() {
  local resolved=${1:?resolved}

  case "$resolved" in
    "$TIER0_FIXTURE_HOME"/* | "$TOOL_PATH_HOME"/* | "$XDG_BIN_HOME"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tier0_probe_command_surface() {
  local key=${1:?key}
  local resolved=""
  local source="missing"
  local ok=false
  local reason=""
  local command=""

  case "$key" in
    just.precommit-lint)
      command="just precommit-lint"
      if resolved="$(command -v just 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if just --list 2>/dev/null | grep -q 'precommit-lint'; then
            ok=true
            reason="precommit-lint recipe available"
          else
            reason="precommit-lint recipe missing"
          fi
        else
          source="host"
          reason="just resolved outside fixture"
        fi
      else
        reason="just missing on PATH"
      fi
      ;;
    dotctl.audit.run)
      command="dotctl audit run"
      if resolved="$(command -v dotctl 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if dotctl audit --help 2>/dev/null | grep -qi 'run'; then
            ok=true
            reason="dotctl audit run command available"
          else
            reason="dotctl audit run command missing"
          fi
        else
          source="host"
          reason="dotctl resolved outside fixture"
        fi
      else
        reason="dotctl missing on PATH"
      fi
      ;;
    dotctl.doctor.check)
      command="dotctl doctor check"
      if resolved="$(command -v dotctl 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if dotctl doctor --help 2>/dev/null | grep -qi 'check'; then
            ok=true
            reason="dotctl doctor check command available"
          else
            reason="dotctl doctor check command missing"
          fi
        else
          source="host"
          reason="dotctl resolved outside fixture"
        fi
      else
        reason="dotctl missing on PATH"
      fi
      ;;
    dotctl.git.refresh)
      command="dotctl git refresh"
      if resolved="$(command -v dotctl 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if dotctl git --help 2>/dev/null | grep -qi 'refresh'; then
            ok=true
            reason="dotctl git refresh command available"
          else
            reason="dotctl git refresh command missing"
          fi
        else
          source="host"
          reason="dotctl resolved outside fixture"
        fi
      else
        reason="dotctl missing on PATH"
      fi
      ;;
    dotctl.check)
      command="dotctl check"
      if resolved="$(command -v dotctl 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if dotctl --help 2>/dev/null | grep -qi 'check'; then
            ok=true
            reason="dotctl check command available"
          else
            reason="dotctl check command missing"
          fi
        else
          source="host"
          reason="dotctl resolved outside fixture"
        fi
      else
        reason="dotctl missing on PATH"
      fi
      ;;
    yadm.bootstrap.dry-run)
      command="DRY_RUN=1 yadm bootstrap"
      if resolved="$(command -v yadm 2>/dev/null)"; then
        if tier0_resolved_from_fixture "$resolved"; then
          source="fixture"
          if yadm bootstrap --help >/dev/null 2>&1; then
            ok=true
            reason="yadm bootstrap dry-run command available"
          else
            reason="yadm bootstrap dry-run command missing"
          fi
        else
          source="host"
          reason="yadm resolved outside fixture"
        fi
      else
        reason="yadm missing on PATH"
      fi
      ;;
    *)
      reason="unknown command surface key: $key"
      ;;
  esac

  jq -n \
    --arg name "$key" \
    --arg key "$key" \
    --arg command "$command" \
    --arg resolved "$resolved" \
    --arg source "$source" \
    --arg reason "$reason" \
    --argjson ok "$ok" \
    '{
      name:$name,
      key:$key,
      command:$command,
      resolved:$resolved,
      source:$source,
      ok:$ok,
      reason:$reason
    }'
}
