#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

TIER0_REQUIRED_TOOLS=(
  bash
  zsh
  git
  jq
  cue
  just
  python3
  shellcheck
  shfmt
  shellharden
  bats
  shellspec
  timeout
)

TIER0_PHASES=(
  clean_bash_load
  clean_zsh_load
  login_zsh_no_hang
  bash_to_zsh
  zsh_to_bash
  path_resolution
  precommit_lint
  audit_gate
  doctor_graph
  bootstrap_dry_run
  git_refresh_status
  dotctl_check
)

tier0_repo_root() {
  if [[ -n "${TIER0_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$TIER0_REPO_ROOT"
    return 0
  fi

  git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || pwd -P
}

tier0_detect_host_class() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      arch|artix|endeavouros|manjaro) printf 'arch-base\n'; return 0 ;;
      debian|ubuntu|linuxmint|pop) printf 'debian-base\n'; return 0 ;;
    esac
    case " ${ID_LIKE:-} " in
      *' arch '*) printf 'arch-base\n'; return 0 ;;
      *' debian '*|*' ubuntu '*) printf 'debian-base\n'; return 0 ;;
    esac
  fi

  if command -v pacman >/dev/null 2>&1; then
    printf 'arch-base\n'
  elif command -v apt-get >/dev/null 2>&1; then
    printf 'debian-base\n'
  else
    printf 'unsupported\n'
    return 1
  fi
}

tier0_require_tools() {
  local missing=()
  local tool

  for tool in "${TIER0_REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ((${#missing[@]})); then
    printf 'missing required Tier-0 test tools:' >&2
    printf ' %s' "${missing[@]}" >&2
    printf '\n' >&2
    return 1
  fi
}

tier0_copy_item() {
  local repo=${1:?repo}
  local home=${2:?home}
  local rel=${3:?rel}

  [[ -e "$repo/$rel" || -L "$repo/$rel" ]] || return 0
  mkdir -p "$home/$(dirname -- "$rel")"
  cp -a -- "$repo/$rel" "$home/$rel"
}

tier0_copy_control_plane() {
  local repo=${1:?repo}
  local home=${2:?home}
  local rel
  local items=(
    .config/shell
    .config/dotctl
    .config/dotfiles-audit
    .config/yadm
    .config/bin
    .config/broot
    .config/nvim
    .config/uv
    .config/zsh
    .zshenv
    .zprofile
    .zshrc
    Justfile
  )

  for rel in "${items[@]}"; do
    tier0_copy_item "$repo" "$home" "$rel"
  done
}

tier0_prepare_zim_stub() {
  local home=${1:?home}
  mkdir -p "$home/.cache/zim"
  printf 'return 0\n' > "$home/.cache/zim/zimfw.zsh"
  printf 'return 0\n' > "$home/.cache/zim/init.zsh"
}

tier0_install_yadm_shim() {
  local home=${1:?home}
  local path_home="$home/.local/share/path"
  mkdir -p "$path_home"

  cat > "$path_home/yadm" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
: "${HOME:?HOME is required}"

cmd="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  bootstrap)
    DRY_RUN="${DRY_RUN:-1}" HOST_CLASS="${HOST_CLASS:-debian-base}" bash "$HOME/.config/yadm/bootstrap" "$@"
    ;;
  status)
    git -C "$HOME" status "$@"
    ;;
  ls-files)
    git -C "$HOME" ls-files "$@"
    ;;
  init)
    git -C "$HOME" init "$@"
    ;;
  '')
    git -C "$HOME" status --short --branch
    ;;
  *)
    git -C "$HOME" "$cmd" "$@"
    ;;
esac
SHIM
  chmod 0755 "$path_home/yadm"
}

tier0_install_dotctl_shim() {
  local home=${1:?home}
  local path_home="$home/.local/share/path"
  mkdir -p "$path_home"

  cat > "$path_home/dotctl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
: "${HOME:?HOME is required}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"

if [[ -r "$XDG_CONFIG_HOME/shell/load-env.sh" ]]; then
  # shellcheck source=/dev/null
  . "$XDG_CONFIG_HOME/shell/load-env.sh"
fi

cmd="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  audit)
    sub="${1:-run}"
    if [[ $# -gt 0 ]]; then shift; fi
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/audit.sh"
    case "$sub" in
      observe) dotctl_audit_observe "$@" ;;
      vet) dotctl_audit_vet "$@" ;;
      run|'') dotctl_audit_run "$@" ;;
      *) printf 'unknown dotctl audit command: %s\n' "$sub" >&2; exit 2 ;;
    esac
    ;;
  doctor)
    json_mode=false
    if [[ "${1:-}" == check ]]; then
      shift
    fi
    if [[ "${1:-}" == --json ]]; then
      json_mode=true
      shift
    fi
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/doctor.sh"
    dotctl_doctor_run "$json_mode"
    ;;
  git)
    sub="${1:-status}"
    if [[ $# -gt 0 ]]; then shift; fi
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/git.sh"
    case "$sub" in
      observe) dotctl_git_observe "$@" ;;
      vet)
        if [[ "${1:-}" == --input ]]; then shift; fi
        dotctl_git_vet "$@"
        ;;
      project-state)
        if [[ "${1:-}" == --input ]]; then shift; fi
        dotctl_git_project_state "$@"
        ;;
      refresh) dotctl_git_refresh "$@" ;;
      status|'') dotctl_git_status "$@" ;;
      add) dotctl_git_add "$@" ;;
      *) printf 'unknown dotctl git command: %s\n' "$sub" >&2; exit 2 ;;
    esac
    ;;
  check)
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/check.sh"
    dotctl_check_all
    ;;
  bootstrap)
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/yadm.sh"
    dotctl_yadm_bootstrap
    ;;
  status)
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/env.sh"
    # shellcheck source=/dev/null
    source "$XDG_CONFIG_HOME/dotctl/src/lib/yadm.sh"
    dotctl_yadm_status
    ;;
  -h|--help|'')
    cat <<'HELP'
dotctl test shim
commands: audit, doctor, git, check, bootstrap, status
HELP
    ;;
  *)
    printf 'unknown dotctl command: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
SHIM
  chmod 0755 "$path_home/dotctl"
}

tier0_init_git_fixture() {
  local home=${1:?home}

  git -C "$home" init -q
  git -C "$home" config user.email tier0@example.invalid
  git -C "$home" config user.name 'Tier0 Fixture'
  git -C "$home" add .
  git -C "$home" commit -qm 'tier0 fixture baseline'
}

tier0_prepare_home() {
  local repo=${1:-$(tier0_repo_root)}
  local base=${2:-${TMPDIR:-/tmp}}
  local mode=${TIER0_MODE:-unit}
  local home

  home="$(mktemp -d "$base/tier0-home.XXXXXX")"
  mkdir -p "$home/.local/share/path" "$home/.local/bin" "$home/.local/state" "$home/.cache"

  tier0_copy_control_plane "$repo" "$home"
  tier0_prepare_zim_stub "$home"
  tier0_init_git_fixture "$home"

  if [[ "$mode" == unit ]]; then
    tier0_install_yadm_shim "$home"
    tier0_install_dotctl_shim "$home"
  fi

  export TIER0_HOME="$home"
  export TIER0_REPO_ROOT="$repo"
  export TIER0_SYSTEM_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
  export TIER0_HOST_CLASS="${TIER0_HOST_CLASS:-$(tier0_detect_host_class)}"
}

tier0_cleanup_home() {
  if [[ -n "${TIER0_HOME:-}" && -d "$TIER0_HOME" ]]; then
    rm -rf -- "$TIER0_HOME"
  fi
}

tier0_clean_env() {
  env -i \
    HOME="$TIER0_HOME" \
    USER="${USER:-tier0}" \
    LOGNAME="${LOGNAME:-${USER:-tier0}}" \
    PATH="$TIER0_SYSTEM_PATH" \
    SHELL="${1:-/bin/bash}" \
    HOST_CLASS="$TIER0_HOST_CLASS" \
    DRY_RUN=1 \
    TERM="${TERM:-xterm-256color}"
}

tier0_in_home() {
  (
    export HOME="$TIER0_HOME"
    export USER="${USER:-tier0}"
    export LOGNAME="${LOGNAME:-$USER}"
    export PATH="$TIER0_SYSTEM_PATH"
    export HOST_CLASS="$TIER0_HOST_CLASS"
    export DRY_RUN=1
    # shellcheck source=/dev/null
    . "$HOME/.config/shell/load-env.sh"
    cd "$HOME"
    "$@"
  )
}

tier0_phase_clean_bash_load() {
  tier0_clean_env /bin/bash bash --noprofile --norc -c '
    set -euo pipefail
    . "$HOME/.config/shell/load-env.sh"
    test -n "${XDG_CONFIG_HOME-}"
    test -n "${XDG_DATA_HOME-}"
    test -n "${XDG_STATE_HOME-}"
    test -n "${XDG_CACHE_HOME-}"
    test -n "${TOOL_PATH_HOME-}"
    case ":$PATH:" in *":$TOOL_PATH_HOME:"*) ;; *) exit 10 ;; esac
  '
}

tier0_phase_clean_zsh_load() {
  tier0_clean_env /bin/zsh zsh -f -c '
    . "$HOME/.config/shell/load-env.sh"
    test -n "${XDG_CONFIG_HOME-}"
    test -n "${XDG_DATA_HOME-}"
    test -n "${XDG_STATE_HOME-}"
    test -n "${XDG_CACHE_HOME-}"
    test -n "${TOOL_PATH_HOME-}"
    case ":$PATH:" in *":$TOOL_PATH_HOME:"*) ;; *) exit 10 ;; esac
  '
}

tier0_phase_login_zsh_no_hang() {
  tier0_clean_env /bin/zsh timeout 8s zsh -lic 'print -r -- tier0-login-zsh-ok' >/dev/null
}

tier0_phase_bash_to_zsh() {
  tier0_clean_env /bin/bash bash --noprofile --norc -c '
    set -euo pipefail
    . "$HOME/.config/shell/load-env.sh"
    zsh -f -c "test -n \"\${XDG_CONFIG_HOME-}\" && command -v dotctl >/dev/null"
  '
}

tier0_phase_zsh_to_bash() {
  tier0_clean_env /bin/zsh zsh -f -c '
    . "$HOME/.config/shell/load-env.sh"
    bash --noprofile --norc -c "set -euo pipefail; test -n \"\${XDG_CONFIG_HOME-}\"; command -v dotctl >/dev/null"
  '
}

tier0_phase_path_resolution() {
  tier0_clean_env /bin/bash bash --noprofile --norc -c '
    set -euo pipefail
    . "$HOME/.config/shell/load-env.sh"
    command -v python3 >/dev/null
    command -v dotctl >/dev/null
    command -v cue >/dev/null
    command -v just >/dev/null
    command -v yadm >/dev/null
    command -v git >/dev/null
    command -v shellcheck >/dev/null
    command -v shfmt >/dev/null
    command -v shellharden >/dev/null
    command -v bats >/dev/null
    command -v shellspec >/dev/null
  '
}

tier0_phase_precommit_lint() {
  tier0_in_home just precommit-lint >/dev/null
}

tier0_phase_audit_gate() {
  tier0_in_home dotctl audit run >/dev/null
}

tier0_phase_doctor_graph() {
  local out
  out="$(tier0_in_home dotctl doctor --json)"
  printf '%s\n' "$out" | jq -e '.schema == "dotctl.doctor.observed.v0" and (.services["shell.env"].status == "ok")' >/dev/null
  printf '%s\n' "$out" > "$TIER0_HOME/.local/state/tier0-doctor.json"
  tier0_in_home cue vet "$TIER0_HOME/.config/dotctl/policy/doctor.cue" "$TIER0_HOME/.local/state/tier0-doctor.json" -d '#Doctor' >/dev/null
}

tier0_phase_bootstrap_dry_run() {
  tier0_in_home env DRY_RUN=1 HOST_CLASS="$TIER0_HOST_CLASS" yadm bootstrap >/dev/null
}

tier0_phase_git_refresh_status() {
  tier0_in_home dotctl git refresh >/dev/null
  tier0_in_home dotctl git status >/dev/null
  test -s "$TIER0_HOME/.local/state/dotctl/backend/git/current.json"
}

tier0_phase_dotctl_check() {
  tier0_in_home dotctl check >/dev/null
}

tier0_run_phase() {
  local phase=${1:?phase}
  local status=0

  set +e
  ("tier0_phase_${phase}")
  status=$?
  set -e

  return "$status"
}

tier0_record_phase() {
  local phase=${1:?phase}
  local status=${2:?status}
  local ok=false

  if [[ "$status" -eq 0 ]]; then
    ok=true
  fi

  jq -n \
    --arg name "$phase" \
    --arg mode "${TIER0_MODE:-unit}" \
    --arg distro "$TIER0_HOST_CLASS" \
    --arg command "tier0_phase_${phase}" \
    --argjson ok "$ok" \
    --argjson exit "$status" \
    '{name:$name, ok:$ok, exit:$exit, mode:$mode, distro:$distro, readonly:true, command:$command}'
}

tier0_run_all_phases() {
  local phase status=0
  local ok=true
  local report="$TIER0_HOME/.local/state/tier0-robustness-report.ndjson"
  : > "$report"

  for phase in "${TIER0_PHASES[@]}"; do
    if tier0_run_phase "$phase"; then
      status=0
      printf '[ok] %s\n' "$phase"
    else
      status=$?
      printf '[fail] %s\n' "$phase" >&2
      ok=false
    fi

    tier0_record_phase "$phase" "$status" >> "$report"
  done

  jq -s --arg distro "$TIER0_HOST_CLASS" --arg mode "${TIER0_MODE:-unit}" \
    '{schema:"tier0.robustness.report.v0", distro:$distro, mode:$mode, summary:{ok:(all(.[]; .ok == true)), count:length, expected_count:length, failed:[.[] | select(.ok == false) | .name]}, phases:.}' \
    "$report" > "$TIER0_HOME/.local/state/tier0-robustness-report.json"

  tier0_in_home cue vet "$TIER0_REPO_ROOT/tests/tier0/policy/robustness.cue" "$TIER0_HOME/.local/state/tier0-robustness-report.json" -d '#RobustnessReport' >/dev/null

  if [[ "$ok" == true ]]; then
    tier0_in_home cue vet \
      "$TIER0_REPO_ROOT/tests/tier0/policy/robustness.cue" \
      "$TIER0_REPO_ROOT/tests/tier0/policy/success.cue" \
      "$TIER0_HOME/.local/state/tier0-robustness-report.json" \
      -d '#SuccessfulRobustnessReport' >/dev/null
  fi

  [[ "$ok" == true ]]
}
