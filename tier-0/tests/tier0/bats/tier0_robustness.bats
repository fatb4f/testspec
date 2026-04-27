#!/usr/bin/env bats

setup() {
  export TIER0_REPO_ROOT="${TIER0_REPO_ROOT:-$PWD}"
  # shellcheck source=tests/tier0/lib/tier0_harness.sh
  source "$TIER0_REPO_ROOT/tests/tier0/lib/tier0_harness.sh"
  tier0_prepare_home "$TIER0_REPO_ROOT" "$BATS_TEST_TMPDIR"
}

teardown() {
  tier0_cleanup_home
}

@test "phase 1: clean bash load" {
  tier0_phase_clean_bash_load
}

@test "phase 1: clean zsh load" {
  tier0_phase_clean_zsh_load
}

@test "phase 1: login zsh does not hang" {
  tier0_phase_login_zsh_no_hang
}

@test "phase 1: bash to zsh transition" {
  tier0_phase_bash_to_zsh
}

@test "phase 1: zsh to bash transition" {
  tier0_phase_zsh_to_bash
}

@test "phase 2: projected tool PATH resolution" {
  tier0_phase_path_resolution
}

@test "phase 3: precommit lint gate" {
  tier0_phase_precommit_lint
}

@test "phase 4: audit gate" {
  tier0_phase_audit_gate
}

@test "phase 5: doctor graph" {
  tier0_phase_doctor_graph
}

@test "phase 6: bootstrap dry-run" {
  tier0_phase_bootstrap_dry_run
}

@test "phase 7: git substrate refresh/status" {
  tier0_phase_git_refresh_status
}

@test "aggregate: dotctl check" {
  tier0_phase_dotctl_check
}
