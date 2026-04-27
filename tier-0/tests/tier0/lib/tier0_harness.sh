#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tier0_backend.sh
source "$script_dir/tier0_backend.sh"
# shellcheck source=tier0_kitty.sh
source "$script_dir/tier0_kitty.sh"

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
  loader_transition_contract
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

tier0_install_just_shim() {
  local home=${1:?home}
  local path_home="$home/.local/share/path"
  local real_just

  real_just="$(command -v just)"
  mkdir -p "$path_home"

  cat > "$path_home/just" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
: "\${HOME:?HOME is required}"

export HOME="\${TIER0_HOME:-\$HOME}"
export XDG_CONFIG_HOME="\${XDG_CONFIG_HOME:-\$HOME/.config}"
export XDG_DATA_HOME="\${XDG_DATA_HOME:-\$HOME/.local/share}"
export XDG_STATE_HOME="\${XDG_STATE_HOME:-\$HOME/.local/state}"
export XDG_CACHE_HOME="\${XDG_CACHE_HOME:-\$HOME/.cache}"

exec "$real_just" "\$@"
SHIM
  chmod 0755 "$path_home/just"
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
    tier0_install_just_shim "$home"
  fi

  export TIER0_HOME="$home"
  export TIER0_FIXTURE_HOME="$home"
  export TIER0_FIXTURE_BIN_HOME="$home/.local/share/path"
  export TIER0_XDG_CONFIG_HOME="$home/.config"
  export TIER0_XDG_DATA_HOME="$home/.local/share"
  export TIER0_XDG_STATE_HOME="$home/.local/state"
  export TIER0_XDG_CACHE_HOME="$home/.cache"
  export TIER0_REPO_ROOT="$repo"
  export TIER0_SYSTEM_PATH="$home/.local/share/path:$home/.local/bin:${PATH:-/usr/local/bin:/usr/bin:/bin}"
  export TIER0_HOST_CLASS="${TIER0_HOST_CLASS:-$(tier0_detect_host_class)}"
}

tier0_cleanup_home() {
  if [[ -n "${TIER0_HOME:-}" && -d "$TIER0_HOME" ]]; then
    rm -rf -- "$TIER0_HOME"
  fi
}

tier0_clean_env() {
  local home="$TIER0_HOME"

  env -i \
    HOME="$home" \
    TIER0_HOME="$TIER0_HOME" \
    TIER0_FIXTURE_HOME="$TIER0_FIXTURE_HOME" \
    TIER0_FIXTURE_BIN_HOME="$TIER0_FIXTURE_BIN_HOME" \
    USER="${USER:-tier0}" \
    LOGNAME="${LOGNAME:-${USER:-tier0}}" \
    PATH="$TIER0_SYSTEM_PATH" \
    SHELL="${1:-/bin/bash}" \
    HOST_CLASS="$TIER0_HOST_CLASS" \
    DRY_RUN=1 \
    XDG_CONFIG_HOME="$TIER0_XDG_CONFIG_HOME" \
    XDG_DATA_HOME="$TIER0_XDG_DATA_HOME" \
    XDG_STATE_HOME="$TIER0_XDG_STATE_HOME" \
    XDG_CACHE_HOME="$TIER0_XDG_CACHE_HOME" \
    XDG_BIN_HOME="$TIER0_FIXTURE_BIN_HOME" \
    TOOL_PATH_HOME="$TIER0_FIXTURE_BIN_HOME" \
    XDG_DATA_BIN="$TIER0_FIXTURE_BIN_HOME" \
    TERM="${TERM:-xterm-256color}"
}

tier0_in_home() {
  (
    export HOME="$TIER0_HOME"
    export TIER0_HOME="$TIER0_HOME"
    export TIER0_FIXTURE_HOME="$TIER0_FIXTURE_HOME"
    export TIER0_FIXTURE_BIN_HOME="$TIER0_FIXTURE_BIN_HOME"
    export USER="${USER:-tier0}"
    export LOGNAME="${LOGNAME:-$USER}"
    export PATH="$TIER0_SYSTEM_PATH"
    export HOST_CLASS="$TIER0_HOST_CLASS"
    export DRY_RUN=1
    export XDG_CONFIG_HOME="$TIER0_XDG_CONFIG_HOME"
    export XDG_DATA_HOME="$TIER0_XDG_DATA_HOME"
    export XDG_STATE_HOME="$TIER0_XDG_STATE_HOME"
    export XDG_CACHE_HOME="$TIER0_XDG_CACHE_HOME"
    export XDG_BIN_HOME="$TIER0_FIXTURE_BIN_HOME"
    export TOOL_PATH_HOME="$TIER0_FIXTURE_BIN_HOME"
    export XDG_DATA_BIN="$TIER0_FIXTURE_BIN_HOME"
    # shellcheck source=/dev/null
    . "$HOME/.config/shell/load-env.sh"
    cd "$HOME"
    "$@"
  )
}

tier0_snapshot_env_json() {
  jq -n \
    --arg home "$HOME" \
    --arg path "${PATH:-}" \
    --arg xdg_bin_home "${XDG_BIN_HOME:-}" \
    --arg xdg_data_bin "${XDG_DATA_BIN:-}" \
    --arg tool_path_home "${TOOL_PATH_HOME:-}" \
    --arg tier0_system_path "${TIER0_SYSTEM_PATH:-}" \
    --arg backend "${TIER0_SHELL_BACKEND:-headless}" \
    --arg pwd "$PWD" \
    --arg dotctl "$(command -v dotctl 2>/dev/null || true)" \
    --arg yadm "$(command -v yadm 2>/dev/null || true)" \
    --arg just "$(command -v just 2>/dev/null || true)" \
    '{
      home:$home,
      path:($path | split(":")),
      xdg_bin_home:$xdg_bin_home,
      xdg_data_bin:$xdg_data_bin,
      tool_path_home:$tool_path_home,
      tier0_system_path:$tier0_system_path,
      backend:$backend,
      pwd:$pwd,
      commands:{dotctl:$dotctl, yadm:$yadm, just:$just}
    }'
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

tier0_preflight_check_json() {
  local name=${1:?name}
  local ok=${2:?ok}
  local reason=${3:-}

  jq -n \
    --arg name "$name" \
    --arg reason "$reason" \
    --argjson ok "$ok" \
    '{name:$name, ok:$ok, reason:$reason}'
}

tier0_preflight_bundle() {
  local env_json=${1:-}

  if [[ -n "$env_json" ]]; then
    jq -s --argjson env "$env_json" '{ok: all(.[]; .ok == true), checks:., env:$env}'
  else
    jq -s '{ok: all(.[]; .ok == true), checks:.}'
  fi
}

tier0_preflight_precommit_lint() {
  local checks=()
  local ok reason

  ok=false; reason="just binary missing"; command -v just >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json just "$ok" "$reason")")

  ok=false; reason="Justfile missing"; [[ -r "$TIER0_REPO_ROOT/Justfile" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json Justfile "$ok" "$reason")")

  ok=false; reason="precommit-lint recipe missing"; if command -v just >/dev/null 2>&1; then just --list 2>/dev/null | grep -qx 'precommit-lint' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json precommit-lint_recipe "$ok" "$reason")")

  ok=false; reason="cue missing on PATH"; command -v cue >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json cue "$ok" "$reason")")

  ok=false; reason="shellcheck missing on PATH"; command -v shellcheck >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json shellcheck "$ok" "$reason")")

  ok=false; reason="shfmt missing on PATH"; command -v shfmt >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json shfmt "$ok" "$reason")")

  ok=false; reason="shellharden missing on PATH"; command -v shellharden >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json shellharden "$ok" "$reason")")

  ok=false; reason="bats missing on PATH"; command -v bats >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json bats "$ok" "$reason")")

  ok=false; reason="shellspec missing on PATH"; command -v shellspec >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json shellspec "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_audit_gate() {
  local checks=()
  local ok reason

  ok=false; reason="dotctl missing on PATH"; command -v dotctl >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json dotctl "$ok" "$reason")")

  ok=false; reason="dotctl audit command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])audit([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_audit_command "$ok" "$reason")")

  ok=false; reason="cue missing on PATH"; command -v cue >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json cue "$ok" "$reason")")

  ok=false; reason="jq missing on PATH"; command -v jq >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json jq "$ok" "$reason")")

  ok=false; reason="policy directory missing"; [[ -d "$TIER0_REPO_ROOT/tests/tier0/policy" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json policy_dir "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_doctor_graph() {
  local checks=()
  local ok reason

  ok=false; reason="dotctl missing on PATH"; command -v dotctl >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json dotctl "$ok" "$reason")")

  ok=false; reason="dotctl doctor command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])doctor([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_doctor_command "$ok" "$reason")")

  ok=false; reason="dotctl doctor check command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])doctor([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_doctor_check_command "$ok" "$reason")")

  ok=false; reason="jq missing on PATH"; command -v jq >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json jq "$ok" "$reason")")

  ok=false; reason="python3 missing on PATH"; command -v python3 >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json python3 "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_bootstrap_dry_run() {
  local checks=()
  local ok reason

  ok=false; reason="yadm missing on PATH"; command -v yadm >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json yadm "$ok" "$reason")")

  ok=false; reason="bootstrap entrypoint missing"; [[ -x "$TIER0_REPO_ROOT/.config/yadm/bootstrap" || -x "$TIER0_REPO_ROOT/tests/tier0/fixtures/.config/yadm/bootstrap" || -x "$TIER0_REPO_ROOT/tier-0/.config/yadm/bootstrap" || -x "$TIER0_REPO_ROOT/.config/yadm/bootstrap" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json bootstrap_entrypoint "$ok" "$reason")")

  ok=false; reason="bootstrap.d directory missing"; [[ -d "$TIER0_REPO_ROOT/.config/yadm/bootstrap.d" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json bootstrap_d_dir "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_git_refresh_status() {
  local checks=()
  local ok reason

  ok=false; reason="dotctl missing on PATH"; command -v dotctl >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json dotctl "$ok" "$reason")")

  ok=false; reason="dotctl git command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])git([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_git_command "$ok" "$reason")")

  ok=false; reason="dotctl git refresh command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])git([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_git_refresh_command "$ok" "$reason")")

  ok=false; reason="git missing on PATH"; command -v git >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json git "$ok" "$reason")")

  ok=false; reason="repo fixture unreadable"; [[ -r "$TIER0_REPO_ROOT/Justfile" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json repo_fixture "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_dotctl_check() {
  local checks=()
  local ok reason

  ok=false; reason="dotctl missing on PATH"; command -v dotctl >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json dotctl "$ok" "$reason")")

  ok=false; reason="dotctl check command missing"; if command -v dotctl >/dev/null 2>&1; then dotctl --help 2>/dev/null | grep -qE '(^|[[:space:]])check([[:space:]]|$)' && ok=true && reason=""; fi
  checks+=("$(tier0_preflight_check_json dotctl_check_command "$ok" "$reason")")

  ok=false; reason="cue missing on PATH"; command -v cue >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json cue "$ok" "$reason")")

  ok=false; reason="jq missing on PATH"; command -v jq >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json jq "$ok" "$reason")")

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_preflight_loader_transition_contract() {
  local checks=()
  local ok reason

  ok=false; reason="cue missing on PATH"; command -v cue >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json cue "$ok" "$reason")")

  ok=false; reason="jq missing on PATH"; command -v jq >/dev/null 2>&1 && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json jq "$ok" "$reason")")

  ok=false; reason="load-env.sh missing"; [[ -r "$TIER0_REPO_ROOT/.config/shell/load-env.sh" ]] && ok=true && reason=""
  checks+=("$(tier0_preflight_check_json load_env_sh "$ok" "$reason")")

  if [[ "${TIER0_SHELL_BACKEND:-headless}" == "kitty-run-shell" ]]; then
    ok=false; reason="kitty run-shell backend unavailable"; (command -v kitten >/dev/null 2>&1 || command -v kitty >/dev/null 2>&1) && ok=true && reason=""
    checks+=("$(tier0_preflight_check_json kitty_run_shell "$ok" "$reason")")
  fi

  printf '%s\n' "${checks[@]}" | tier0_preflight_bundle "$(tier0_snapshot_env_json)"
}

tier0_run_phase_preflight() {
  local phase=${1:?phase}

  case "$phase" in
    precommit_lint) tier0_preflight_precommit_lint ;;
    audit_gate) tier0_preflight_audit_gate ;;
    doctor_graph) tier0_preflight_doctor_graph ;;
    bootstrap_dry_run) tier0_preflight_bootstrap_dry_run ;;
    git_refresh_status) tier0_preflight_git_refresh_status ;;
    dotctl_check) tier0_preflight_dotctl_check ;;
    loader_transition_contract) tier0_preflight_loader_transition_contract ;;
    *) jq -n '{ok:true, checks:[]}' ;;
  esac
}

tier0_phase_loader_transition_contract() {
  local backend="${TIER0_SHELL_BACKEND:-headless}"
  case "$backend" in
    kitty-run-shell) tier0_phase_loader_transition_contract_kitty ;;
    headless|'') tier0_phase_loader_transition_contract_headless ;;
    *)
      printf 'unsupported shell backend: %s\n' "$backend" >&2
      return 2
      ;;
  esac
}

tier0_loader_transition_script_body() {
  cat <<'EOF'
set -euo pipefail

snapshot() {
  jq -n \
    --arg home "$HOME" \
    --arg path "${PATH:-}" \
    --arg xdg_bin_home "${XDG_BIN_HOME:-}" \
    --arg xdg_data_bin "${XDG_DATA_BIN:-}" \
    --arg tool_path_home "${TOOL_PATH_HOME:-}" \
    --arg tier0_system_path "${TIER0_SYSTEM_PATH:-}" \
    --arg backend "${TIER0_SHELL_BACKEND:-headless}" \
    --arg pwd "$PWD" \
    --arg dotctl "$(command -v dotctl 2>/dev/null || true)" \
    --arg yadm "$(command -v yadm 2>/dev/null || true)" \
    --arg just "$(command -v just 2>/dev/null || true)" \
    '{
      home:$home,
      path:($path | split(":")),
      xdg_bin_home:$xdg_bin_home,
      xdg_data_bin:$xdg_data_bin,
      tool_path_home:$tool_path_home,
      tier0_system_path:$tier0_system_path,
      backend:$backend,
      pwd:$pwd,
      commands:{dotctl:$dotctl, yadm:$yadm, just:$just}
    }'
}

transition_file="$TIER0_HOME/.local/state/tier0-loader-transition.json"
before="$(snapshot before)"
. "$HOME/.config/shell/load-env.sh"
after="$(snapshot after)"
# shellcheck source=/dev/null
source "$TIER0_REPO_ROOT/tier-0/tests/tier0/lib/tier0_backend.sh"
backend="$(tier0_backend_report_json)"

jq -n \
  --argjson before "$before" \
  --argjson after "$after" \
  --argjson backend "$backend" \
  '{
    schema:"tier0.loader-transition.observed.v0",
    backend:$backend,
    before:$before,
    after:$after,
    invariants:{
      tool_path_preserved:(($before.tool_path_home == "") or ($after.path | index($before.tool_path_home) != null)),
      xdg_bin_preserved:(($before.xdg_bin_home == "") or ($after.path | index($before.xdg_bin_home) != null)),
      fixture_tools_first:(($before.tool_path_home == "") or ($after.path[0] == $before.tool_path_home)),
      dotctl_resolves:($after.commands.dotctl != ""),
      yadm_resolves:($after.commands.yadm != ""),
      just_resolves:($after.commands.just != "")
    }
  }' > "$transition_file"

cat "$transition_file"
cue vet \
  "$TIER0_REPO_ROOT/tier-0/tests/tier0/policy/backend.cue" \
  "$TIER0_REPO_ROOT/tier-0/tests/tier0/policy/env.cue" \
  "$transition_file" \
  -d "#LoaderTransition" >/dev/null
EOF
}

tier0_phase_loader_transition_contract_headless() {
  local script_file
  script_file="$(mktemp "${TIER0_HOME}/.local/state/tier0-loader-transition.XXXXXX.sh")"
  tier0_loader_transition_script_body >"$script_file"
  chmod 0755 "$script_file"
  tier0_clean_env /bin/bash bash --noprofile --norc "$script_file"
}

tier0_phase_loader_transition_contract_kitty() {
  local script_file

  script_file="$(mktemp "${TIER0_HOME}/.local/state/tier0-loader-transition-kitty.XXXXXX.sh")"
  tier0_loader_transition_script_body >"$script_file"
  chmod 0755 "$script_file"
  tier0_kitty_run_shell "$script_file"
}

tier0_classify_phase_failure() {
  local phase=${1:?phase}
  local status=${2:?status}
  local output_file=${3:?output_file}
  local preflight_file=${4:-}
  local output=""
  local preflight_failed_name=""
  local preflight_failed_reason=""

  if [[ -r "$output_file" ]]; then
    output="$(cat "$output_file")"
  fi

  if [[ -n "$preflight_file" && -r "$preflight_file" ]]; then
    preflight_failed_name="$(jq -r '.checks[] | select(.ok == false) | .name' "$preflight_file" 2>/dev/null | head -n1 || true)"
    preflight_failed_reason="$(jq -r '.checks[] | select(.ok == false) | .reason' "$preflight_file" 2>/dev/null | head -n1 || true)"
  fi

  if [[ -n "$preflight_failed_name" ]]; then
    case "$preflight_failed_name" in
      just|dotctl|yadm|git)
        printf '%s\n%s\n' 'missing_tool' "${preflight_failed_reason:-command unavailable for phase: $phase}"
        return 0
        ;;
      cue|jq|python3|shellcheck|shfmt|shellharden|bats|shellspec)
        printf '%s\n%s\n' 'missing_dependency' "${preflight_failed_reason:-dependency unavailable for phase: $phase}"
        return 0
        ;;
      Justfile|precommit-lint_recipe|policy_dir|bootstrap_entrypoint|bootstrap_d_dir|repo_fixture)
        printf '%s\n%s\n' 'fixture_gap' "${preflight_failed_reason:-fixture gap for phase: $phase}"
        return 0
        ;;
      dotctl_audit_command|dotctl_doctor_command|dotctl_doctor_check_command|dotctl_git_command|dotctl_git_refresh_command|dotctl_check_command)
        printf '%s\n%s\n' 'missing_tool' "${preflight_failed_reason:-missing command contract for phase: $phase}"
        return 0
        ;;
    esac
  fi

  if [[ "$status" -eq 127 ]] || grep -qiE 'missing required Tier-0 test tools|command not found|not found' <<<"$output"; then
    printf '%s\n%s\n' 'missing_tool' "command or required tool unavailable for phase: $phase"
    return 0
  fi

  if grep -qiE 'Justfile does not contain recipe|missing fixture|cannot stat|No such file or directory|No such file' <<<"$output"; then
    printf '%s\n%s\n' 'fixture_gap' "fixture or projected file missing for phase: $phase"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|policy|vet failed' <<<"$output"; then
    printf '%s\n%s\n' 'policy_reject' "policy rejected observed state for phase: $phase"
    return 0
  fi

  if grep -qiE 'Permission denied' <<<"$output"; then
    printf '%s\n%s\n' 'missing_dependency' "permission denied while executing phase: $phase"
    return 0
  fi

  printf '%s\n%s\n' 'command_failed' "command returned non-zero for phase: $phase"
}

tier0_run_phase() {
  local phase=${1:?phase}
  local status=0
  local output_file

  output_file="$(mktemp "${TIER0_HOME}/.local/state/tier0-${phase}.XXXXXX")"
  set +e
  ("tier0_phase_${phase}") >"$output_file" 2>&1
  status=$?
  set -e

  TIER0_PHASE_OUTPUT_FILE="$output_file"
  return "$status"
}

tier0_record_phase() {
  local phase=${1:?phase}
  local status=${2:?status}
  local output_file=${3:?output_file}
  local preflight_file=${4:-}
  local ok=false
  local classification reason stderr_excerpt
  local preflight_json='{"ok":true,"checks":[]}'
  local preflight_failed_check=""
  local preflight_failed_reason=""

  stderr_excerpt=""

  if [[ -n "$preflight_file" && -r "$preflight_file" ]]; then
    preflight_json="$(cat "$preflight_file")"
    preflight_failed_check="$(jq -r '.checks[] | select(.ok == false) | .name' "$preflight_file" 2>/dev/null | head -n1 || true)"
    preflight_failed_reason="$(jq -r '.checks[] | select(.ok == false) | .reason' "$preflight_file" 2>/dev/null | head -n1 || true)"
  fi

  if [[ "$status" -eq 0 ]]; then
    ok=true
    classification="passed"
    reason="phase completed successfully"
  else
    classification="$(tier0_classify_phase_failure "$phase" "$status" "$output_file" "$preflight_file" | sed -n '1p')"
    reason="$(tier0_classify_phase_failure "$phase" "$status" "$output_file" "$preflight_file" | sed -n '2p')"
    stderr_excerpt="$(tail -n 12 "$output_file" 2>/dev/null || true)"
  fi

  jq -n \
    --arg name "$phase" \
    --arg mode "${TIER0_MODE:-unit}" \
    --arg distro "$TIER0_HOST_CLASS" \
    --arg command "tier0_phase_${phase}" \
    --arg classification "$classification" \
    --arg reason "$reason" \
    --arg stderr_excerpt "$stderr_excerpt" \
    --arg preflight_failed_check "$preflight_failed_check" \
    --arg preflight_failed_reason "$preflight_failed_reason" \
    --argjson preflight "$preflight_json" \
    --argjson ok "$ok" \
    --argjson exit "$status" \
    '{name:$name, ok:$ok, exit:$exit, mode:$mode, distro:$distro, readonly:true, command:$command, classification:$classification, reason:$reason, stderr_excerpt:$stderr_excerpt, preflight_failed_check:$preflight_failed_check, preflight_failed_reason:$preflight_failed_reason, preflight:$preflight}'
}

tier0_run_all_phases() {
  local phase status=0
  local ok=true
  local output_file
  local preflight_file
  local report="$TIER0_HOME/.local/state/tier0-robustness-report.ndjson"
  : > "$report"

  for phase in "${TIER0_PHASES[@]}"; do
    preflight_file="$(mktemp "${TIER0_HOME}/.local/state/tier0-${phase}.preflight.XXXXXX")"
    tier0_in_home tier0_run_phase_preflight "$phase" >"$preflight_file"
    if tier0_run_phase "$phase"; then
      status=0
    else
      status=$?
      ok=false
    fi

    output_file="${TIER0_PHASE_OUTPUT_FILE:-}"
    if [[ -n "$output_file" && -r "$output_file" ]]; then
      cat "$output_file"
    fi

  if [[ "$status" -eq 0 ]]; then
      printf '[ok] %s\n' "$phase"
    else
      printf '[fail] %s\n' "$phase" >&2
    fi

    tier0_record_phase "$phase" "$status" "$output_file" "$preflight_file" >> "$report"
    rm -f -- "$output_file"
    rm -f -- "$preflight_file"
  done

  jq -s --arg distro "$TIER0_HOST_CLASS" --arg mode "${TIER0_MODE:-unit}" \
    --argjson backend "$(tier0_backend_report_json)" \
    '{schema:"tier0.robustness.report.v0", backend:$backend, distro:$distro, mode:$mode, summary:{ok:(all(.[]; .ok == true)), count:length, expected_count:length, failed:[.[] | select(.ok == false) | .name]}, phases:.}' \
    "$report" > "$TIER0_HOME/.local/state/tier0-robustness-report.json"

  tier0_in_home cue vet \
    "$TIER0_REPO_ROOT/tests/tier0/policy/backend.cue" \
    "$TIER0_REPO_ROOT/tests/tier0/policy/robustness.cue" \
    "$TIER0_HOME/.local/state/tier0-robustness-report.json" \
    -d '#RobustnessReport' >/dev/null

  if [[ "$ok" == true ]]; then
    tier0_in_home cue vet \
      "$TIER0_REPO_ROOT/tests/tier0/policy/backend.cue" \
      "$TIER0_REPO_ROOT/tests/tier0/policy/robustness.cue" \
      "$TIER0_REPO_ROOT/tests/tier0/policy/success.cue" \
      "$TIER0_HOME/.local/state/tier0-robustness-report.json" \
      -d '#SuccessfulRobustnessReport' >/dev/null
  fi

  [[ "$ok" == true ]]
}
