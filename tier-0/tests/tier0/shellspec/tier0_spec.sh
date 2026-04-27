# shellcheck shell=bash

Describe 'Tier-0 robustness workflow'
  TIER0_REPO_ROOT="${TIER0_REPO_ROOT:-$PWD}"
  Include "$TIER0_REPO_ROOT/tests/tier0/lib/tier0_harness.sh"

  setup_fixture() {
    tier0_prepare_home "$TIER0_REPO_ROOT" "${TMPDIR:-/tmp}"
  }

  cleanup_fixture() {
    tier0_cleanup_home
  }

  BeforeEach 'setup_fixture'
  AfterEach 'cleanup_fixture'

  It 'loads from a clean bash shell'
    When call tier0_phase_clean_bash_load
    The status should be success
  End

  It 'loads from a clean zsh shell'
    When call tier0_phase_clean_zsh_load
    The status should be success
  End

  It 'starts login zsh without hanging'
    When call tier0_phase_login_zsh_no_hang
    The status should be success
  End

  It 'crosses bash to zsh'
    When call tier0_phase_bash_to_zsh
    The status should be success
  End

  It 'crosses zsh to bash'
    When call tier0_phase_zsh_to_bash
    The status should be success
  End

  It 'resolves projected control-plane tools'
    When call tier0_phase_path_resolution
    The status should be success
  End

  It 'passes precommit lint gate'
    When call tier0_phase_precommit_lint
    The status should be success
  End

  It 'passes audit gate'
    When call tier0_phase_audit_gate
    The status should be success
  End

  It 'emits and vets doctor graph'
    When call tier0_phase_doctor_graph
    The status should be success
  End

  It 'runs bootstrap dry-run'
    When call tier0_phase_bootstrap_dry_run
    The status should be success
  End

  It 'refreshes git substrate state'
    When call tier0_phase_git_refresh_status
    The status should be success
  End

  It 'passes aggregate dotctl check'
    When call tier0_phase_dotctl_check
    The status should be success
  End
End
