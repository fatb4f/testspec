#!/usr/bin/env bash
# shellcheck shell=bash

tier0_chaos_cases() {
  printf '%s\n' \
    remove-cue \
    remove-gh \
    remove-shellharden \
    remove-shellspec \
    break-dotctl-wrapper \
    remove-dotctl-audit-run-surface \
    remove-just-precommit-lint-recipe \
    remove-policy-dir
}

tier0_chaos_case_json() {
  local case_name=${1:?case}
  case "$case_name" in
    remove-cue)
      jq -n '{name:"remove-cue", mutation:"remove_tool", target:"cue", expected_phase:"audit_gate", expected_classification:"missing_substrate", expected_failed_check:"cue"}'
      ;;
    remove-gh)
      jq -n '{name:"remove-gh", mutation:"remove_tool", target:"yadm", expected_phase:"bootstrap_dry_run", expected_classification:"missing_command_surface", expected_failed_check:"yadm.bootstrap.dry-run"}'
      ;;
    remove-shellharden)
      jq -n '{name:"remove-shellharden", mutation:"remove_tool", target:"shellharden", expected_phase:"precommit_lint", expected_classification:"missing_substrate", expected_failed_check:"shellharden"}'
      ;;
    remove-shellspec)
      jq -n '{name:"remove-shellspec", mutation:"remove_tool", target:"shellspec", expected_phase:"precommit_lint", expected_classification:"missing_substrate", expected_failed_check:"shellspec"}'
      ;;
    break-dotctl-wrapper)
      jq -n '{name:"break-dotctl-wrapper", mutation:"remove_tool", target:"dotctl", expected_phase:"dotctl_check", expected_classification:"missing_command_surface", expected_failed_check:"dotctl.check"}'
      ;;
    remove-dotctl-audit-run-surface)
      jq -n '{name:"remove-dotctl-audit-run-surface", mutation:"break_command_surface", target:"dotctl.audit.run", expected_phase:"audit_gate", expected_classification:"missing_command_surface", expected_failed_check:"dotctl.audit.run"}'
      ;;
    remove-just-precommit-lint-recipe)
      jq -n '{name:"remove-just-precommit-lint-recipe", mutation:"break_command_surface", target:"just.precommit-lint", expected_phase:"precommit_lint", expected_classification:"missing_command_surface", expected_failed_check:"just.precommit-lint"}'
      ;;
    break-loader-tool-path-home)
      jq -n '{name:"break-loader-tool-path-home", mutation:"break_loader", target:"load-env.sh", expected_phase:"loader_transition_contract", expected_classification:"policy_reject", expected_failed_check:"TOOL_PATH_HOME"}'
      ;;
    remove-policy-dir)
      jq -n '{name:"remove-policy-dir", mutation:"remove_fixture_path", target:"policy_dir", expected_phase:"audit_gate", expected_classification:"fixture_gap", expected_failed_check:"policy_dir"}'
      ;;
    unreadable-git-fixture)
      jq -n '{name:"unreadable-git-fixture", mutation:"break_git", target:"git", expected_phase:"git_refresh_status", expected_classification:"command_failed", expected_failed_check:""}'
      ;;
    *)
      printf 'unknown chaos case: %s\n' "$case_name" >&2
      return 64
      ;;
  esac
}

tier0_chaos_report_json() {
  local case_name=${TIER0_CHAOS_CASE:-}
  if [[ -z "$case_name" ]]; then
    jq -n '{enabled:false, ok:true, case:null}'
    return 0
  fi

  jq -n --arg case "$case_name" --argjson spec "$(tier0_chaos_case_json "$case_name")" '{
    enabled: true,
    ok: true,
    case: $case,
    mutation: $spec.mutation,
    target: $spec.target,
    expected: {
      phase: $spec.expected_phase,
      classification: $spec.expected_classification,
      failed_check: $spec.expected_failed_check
    }
  }'
}

tier0_chaos_apply_case() {
  local case_name=${1:?case}
  local path_home="${TIER0_HOME:?missing TIER0_HOME}/.local/share/path"
  local repo_root="${TIER0_REPO_ROOT:?missing TIER0_REPO_ROOT}"

  case "$case_name" in
    remove-cue|remove-gh|remove-shellharden|remove-shellspec)
      rm -f -- "$path_home/$(
        case "$case_name" in
          remove-cue) printf cue ;;
          remove-gh) printf yadm ;;
          remove-shellharden) printf shellharden ;;
          remove-shellspec) printf shellspec ;;
        esac
      )"
      ;;
    break-dotctl-wrapper)
      cat > "$path_home/dotctl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf 'dotctl chaos wrapper\n' >&2
exit 127
SHIM
      chmod 0755 "$path_home/dotctl"
      ;;
    remove-dotctl-audit-run-surface)
      cat > "$path_home/dotctl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  --help|-h)
    cat <<'HELP'
dotctl chaos wrapper
commands: doctor, git, check
HELP
    ;;
  audit)
    case "${1:-}" in
      --help|-h)
        printf 'dotctl audit chaos wrapper\n'
        ;;
      *)
        printf 'audit surface removed by chaos fixture\n' >&2
        exit 127
        ;;
    esac
    ;;
  *)
    printf 'dotctl chaos wrapper\n' >&2
    exit 127
    ;;
esac
SHIM
      chmod 0755 "$path_home/dotctl"
      ;;
    remove-just-precommit-lint-recipe)
      rm -f -- "$TIER0_HOME/Justfile"
      python3 - "$repo_root/Justfile" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
out = []
skip = False
indent = None
for line in lines:
    if line.startswith('precommit-lint:'):
        skip = True
        indent = len(line) - len(line.lstrip())
        continue
    if skip:
        if line.strip() and (len(line) - len(line.lstrip()) <= indent) and not line.startswith((' ', '\t')):
            skip = False
        else:
            continue
    if not skip:
        out.append(line)
path.write_text('\n'.join(out) + '\n', encoding='utf-8')
PY
      ;;
    break-loader-tool-path-home)
      cat > "$TIER0_HOME/.config/shell/load-env.sh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

: "${HOME:?HOME is required}"
TOOL_PATH_HOME="/broken/tool/path"
XDG_DATA_BIN="/broken/data/bin"
PATH="$HOME/.local/share/path:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export TOOL_PATH_HOME XDG_DATA_BIN PATH
SHIM
      chmod 0755 "$TIER0_HOME/.config/shell/load-env.sh"
      ;;
    remove-policy-dir)
      rm -rf -- "$repo_root/tier-0/tests/tier0/policy"
      ;;
    unreadable-git-fixture)
      rm -rf -- "$TIER0_HOME/.git" 2>/dev/null || true
      ;;
    *)
      printf 'unknown chaos case: %s\n' "$case_name" >&2
      return 64
      ;;
  esac
}
