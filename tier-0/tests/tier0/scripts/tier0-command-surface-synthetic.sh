#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/tier0_fixture.sh
source "$script_dir/../lib/tier0_fixture.sh"

assert_eq() {
  local expected=${1:?expected}
  local actual=${2:?actual}
  local label=${3:?label}

  if [[ "$expected" != "$actual" ]]; then
    printf 'assertion failed: %s expected=%s actual=%s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

export TIER0_FIXTURE_HOME="$tmp/fixture"
export TOOL_PATH_HOME="$TIER0_FIXTURE_HOME/.local/share/path"
export XDG_BIN_HOME="$TOOL_PATH_HOME"
export PATH="$TOOL_PATH_HOME:${PATH:-/usr/local/bin:/usr/bin:/bin}"
mkdir -p "$TOOL_PATH_HOME"

cat >"$TOOL_PATH_HOME/dotctl" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  printf 'dotctl test shim\ncommands: audit doctor git check\n'
  exit 0
fi
case "${1:-}" in
  audit) printf 'run\n' ;;
  doctor) printf 'check\n' ;;
  git) printf 'refresh\n' ;;
  check) printf 'check\n' ;;
esac
SHIM
chmod 0755 "$TOOL_PATH_HOME/dotctl"

cat >"$TOOL_PATH_HOME/just" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == --list ]]; then
  printf 'precommit-lint\n'
  exit 0
fi
exit 0
SHIM
chmod 0755 "$TOOL_PATH_HOME/just"

cat >"$TOOL_PATH_HOME/yadm" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == bootstrap ]]; then
  printf 'bootstrap\n'
  exit 0
fi
exit 0
SHIM
chmod 0755 "$TOOL_PATH_HOME/yadm"

probe="$(tier0_probe_command_surface dotctl.audit.run)"
assert_eq fixture "$(printf '%s\n' "$probe" | jq -r '.source')" "dotctl.audit.run source"
assert_eq true "$(printf '%s\n' "$probe" | jq -r '.ok')" "dotctl.audit.run ok"
assert_eq 0 "$(tier0_resolved_from_fixture "$TOOL_PATH_HOME/dotctl" >/dev/null; printf '%s' "$?")" "fixture resolution"
assert_eq 1 "$(tier0_resolved_from_fixture /usr/bin/dotctl >/dev/null 2>&1; printf '%s' "$?")" "host resolution rejection"

probe="$(tier0_probe_command_surface just.precommit-lint)"
assert_eq fixture "$(printf '%s\n' "$probe" | jq -r '.source')" "just.precommit-lint source"
assert_eq true "$(printf '%s\n' "$probe" | jq -r '.ok')" "just.precommit-lint ok"

probe="$(tier0_probe_command_surface yadm.bootstrap.dry-run)"
assert_eq fixture "$(printf '%s\n' "$probe" | jq -r '.source')" "yadm.bootstrap.dry-run source"
assert_eq true "$(printf '%s\n' "$probe" | jq -r '.ok')" "yadm.bootstrap.dry-run ok"

if ! grep -q 'dotctl.audit.run' "$script_dir/../policy/substrate.cue"; then
  printf 'substrate declaration missing dotctl.audit.run\n' >&2
  exit 1
fi

printf '%s\n' 'tier0-command-surface-synthetic: ok'
