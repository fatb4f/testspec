#!/usr/bin/env bash
# shellcheck shell=bash

tier0_known_tool_key() {
  case "$1" in
    bash|zsh|python3|git|jq|cue|just|gh|shellcheck|shellharden|shfmt|bats|shellspec)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tier0_known_command_key() {
  case "$1" in
    just.precommit-lint|dotctl.audit.run|dotctl.doctor.check|dotctl.git.refresh|dotctl.check|yadm.bootstrap.dry-run)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tier0_extract_missing_dependency() {
  local stderr_file=${1:?stderr_file}
  local tool

  for tool in cue jq gh git python3 shellharden shellspec shellcheck shfmt bats just dotctl yadm; do
    if grep -qiE "(^|[[:space:]])${tool}(: command not found|: not found| not found)|command not found: ${tool}|missing required command: ${tool}|(^|[[:space:]])${tool} missing|warn: ${tool} missing|No such file or directory.*${tool}" "$stderr_file" 2>/dev/null; then
      printf '%s\n' "$tool"
      return 0
    fi
  done

  return 1
}

tier0_execution_excerpt() {
  local file=${1:?file}
  local limit=${2:-12}

  if [[ -r "$file" ]]; then
    tail -n "$limit" "$file" 2>/dev/null || true
  fi
}

tier0_classify_generic_execution() {
  local phase=${1:?phase}
  local exit_code=${2:?exit_code}
  local stderr_file=${3:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"

  export TIER0_EXECUTION_EXIT="$exit_code"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_STDOUT_EXCERPT="${TIER0_EXECUTION_STDOUT_EXCERPT:-}"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="execution passed"
    return 0
  fi

  if [[ "$exit_code" -eq 127 ]]; then
    if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
      export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
      export TIER0_EXECUTION_FAILED_CHECK="$dep"
      export TIER0_EXECUTION_REASON="$dep missing during execution"
    else
      export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
      export TIER0_EXECUTION_FAILED_CHECK="command"
      export TIER0_EXECUTION_REASON="command exited 127"
    fi
    return 0
  fi

  if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="$dep"
    export TIER0_EXECUTION_REASON="$dep missing during execution"
    return 0
  fi

  if grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="command"
    export TIER0_EXECUTION_REASON="command or tool missing during execution"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|vet failed|policy' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="CUE policy rejected execution output"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="$phase"
  export TIER0_EXECUTION_REASON="execution failed"
  return 0
}

tier0_classify_precommit_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="precommit lint passed"
    return 0
  fi

  if grep -qiE 'precommit-lint recipe missing|Justfile does not contain recipe|recipe missing' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="fixture_gap"
    export TIER0_EXECUTION_FAILED_CHECK="precommit-lint_recipe"
    export TIER0_EXECUTION_REASON="precommit-lint recipe missing"
    return 0
  fi

  if grep -qiE 'cue(:| .*not found|.*command not found)|command not found: cue|cue: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="cue missing during precommit lint"
    return 0
  fi

  if grep -qiE 'shellcheck(:| .*not found|.*command not found)|shellcheck: not found|command not found: shellcheck' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="shellcheck"
    export TIER0_EXECUTION_REASON="shellcheck missing during precommit lint"
    return 0
  fi

  if grep -qiE 'shfmt(:| .*not found|.*command not found)|shfmt: not found|command not found: shfmt' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="shfmt"
    export TIER0_EXECUTION_REASON="shfmt missing during precommit lint"
    return 0
  fi

  if grep -qiE 'shellharden(:| .*not found|.*command not found)|shellharden: not found|command not found: shellharden' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="shellharden"
    export TIER0_EXECUTION_REASON="shellharden missing during precommit lint"
    return 0
  fi

  if grep -qiE 'bats(:| .*not found|.*command not found)|bats: not found|command not found: bats' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="bats"
    export TIER0_EXECUTION_REASON="bats missing during precommit lint"
    return 0
  fi

  if grep -qiE 'shellspec(:| .*not found|.*command not found)|shellspec: not found|command not found: shellspec' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="shellspec"
    export TIER0_EXECUTION_REASON="shellspec missing during precommit lint"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="precommit_lint"
  export TIER0_EXECUTION_REASON="precommit lint failed"
  return 0
}

tier0_classify_audit_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="audit gate passed"
    return 0
  fi

  if grep -qiE 'cue(:| .*not found|.*command not found)|command not found: cue|cue: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="cue missing during audit execution"
    return 0
  fi

  if grep -qiE 'jq(:| .*not found|.*command not found)|command not found: jq|jq: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="jq"
    export TIER0_EXECUTION_REASON="jq missing during audit execution"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|vet failed|policy' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="CUE policy rejected audit execution output"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="audit_gate"
  export TIER0_EXECUTION_REASON="audit execution failed"
  return 0
}

tier0_classify_doctor_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="doctor graph passed"
    return 0
  fi

  if grep -qiE 'cue(:| .*not found|.*command not found)|command not found: cue|cue: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="cue missing during doctor execution"
    return 0
  fi

  if grep -qiE 'jq(:| .*not found|.*command not found)|command not found: jq|jq: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="jq"
    export TIER0_EXECUTION_REASON="jq missing during doctor execution"
    return 0
  fi

  if grep -qiE 'python3(:| .*not found|.*command not found)|command not found: python3|python3: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="python3"
    export TIER0_EXECUTION_REASON="python3 missing during doctor execution"
    return 0
  fi

  if grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="command"
    export TIER0_EXECUTION_REASON="command or tool missing during doctor execution"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|vet failed|policy' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="CUE policy rejected doctor execution output"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="doctor_graph"
  export TIER0_EXECUTION_REASON="doctor execution failed"
  return 0
}

tier0_classify_bootstrap_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="bootstrap dry run passed"
    return 0
  fi

  if grep -qiE 'DRY_RUN|dry run violation|install|mutat|delete|rm -rf|apt|pacman|bootstrap.*install|bootstrap.*mutat' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="dry_run_violation"
    export TIER0_EXECUTION_FAILED_CHECK="dry_run"
    export TIER0_EXECUTION_REASON="bootstrap dry run attempted a mutation"
    if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
      export TIER0_EXECUTION_FAILED_CHECK="$dep"
    fi
    return 0
  fi

  if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
    if [[ "$dep" == "gh" ]]; then
      export TIER0_EXECUTION_CLASSIFICATION="dry_run_violation"
      export TIER0_EXECUTION_FAILED_CHECK="gh"
      export TIER0_EXECUTION_REASON="bootstrap dry run reached gh-dependent install/projection path"
      return 0
    fi
    if [[ "$dep" == "yadm" ]]; then
      export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
      export TIER0_EXECUTION_FAILED_CHECK="$dep"
      export TIER0_EXECUTION_REASON="yadm missing during bootstrap execution"
      return 0
    fi
  fi

  if grep -qiE 'yadm(:| .*not found|.*command not found)|command not found: yadm|yadm: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="yadm"
    export TIER0_EXECUTION_REASON="yadm missing during bootstrap execution"
    return 0
  fi

  if grep -qiE 'gh(:| .*not found|.*command not found)|command not found: gh|gh: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="dry_run_violation"
    export TIER0_EXECUTION_FAILED_CHECK="gh"
    export TIER0_EXECUTION_REASON="bootstrap dry run reached gh-dependent install/projection path"
    return 0
  fi

  if grep -qiE 'command not found|not found|No such file or directory' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="command"
    export TIER0_EXECUTION_REASON="command or tool missing during bootstrap execution"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="bootstrap_dry_run"
  export TIER0_EXECUTION_REASON="bootstrap dry run failed"
  return 0
}

tier0_classify_git_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="git refresh passed"
    return 0
  fi

  if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
    if [[ "$dep" == "cue" ]]; then
      export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
      export TIER0_EXECUTION_FAILED_CHECK="$dep"
      export TIER0_EXECUTION_REASON="cue missing during git execution"
      return 0
    fi
  fi

  if grep -qiE 'git(:| .*not found|.*command not found)|command not found: git|git: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="git"
    export TIER0_EXECUTION_REASON="git missing during execution"
    return 0
  fi

  if grep -qiE 'dotctl(:| .*not found|.*command not found)|command not found: dotctl|dotctl: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="dotctl"
    export TIER0_EXECUTION_REASON="dotctl missing during execution"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="git_refresh_status"
  export TIER0_EXECUTION_REASON="git refresh failed"
  return 0
}

tier0_classify_dotctl_check_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="dotctl check passed"
    return 0
  fi

  if dep="$(tier0_extract_missing_dependency "$stderr_file")"; then
    if [[ "$dep" == "shellharden" ]]; then
      export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
      export TIER0_EXECUTION_FAILED_CHECK="$dep"
      export TIER0_EXECUTION_REASON="shellharden missing during dotctl check execution"
      return 0
    fi
  fi

  if grep -qiE 'dotctl(:| .*not found|.*command not found)|command not found: dotctl|dotctl: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_tool"
    export TIER0_EXECUTION_FAILED_CHECK="dotctl"
    export TIER0_EXECUTION_REASON="dotctl missing during execution"
    return 0
  fi

  if grep -qiE 'jq(:| .*not found|.*command not found)|command not found: jq|jq: not found' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="missing_dependency"
    export TIER0_EXECUTION_FAILED_CHECK="jq"
    export TIER0_EXECUTION_REASON="jq missing during dotctl check execution"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|vet failed|policy' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="cue"
    export TIER0_EXECUTION_REASON="CUE policy rejected dotctl check output"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="dotctl_check"
  export TIER0_EXECUTION_REASON="dotctl check failed"
  return 0
}

tier0_classify_loader_transition_execution() {
  local exit_code=${1:?exit_code}
  local stderr_file=${2:?stderr_file}
  local stderr_excerpt

  stderr_excerpt="$(tier0_execution_excerpt "$stderr_file")"
  export TIER0_EXECUTION_STDERR_EXCERPT="$stderr_excerpt"
  export TIER0_EXECUTION_OK=false

  if [[ "$exit_code" -eq 0 ]]; then
    export TIER0_EXECUTION_OK=true
    export TIER0_EXECUTION_CLASSIFICATION="ok"
    export TIER0_EXECUTION_FAILED_CHECK=""
    export TIER0_EXECUTION_REASON="loader transition passed"
    return 0
  fi

  if grep -qiE 'TOOL_PATH_HOME|tool_path_preserved|fixture_tools_first|PATH' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="TOOL_PATH_HOME"
    export TIER0_EXECUTION_REASON="TOOL_PATH_HOME not preserved after load-env.sh"
    return 0
  fi

  if grep -qiE 'conflicting values|incomplete value|field not allowed|vet failed|policy' <<<"$stderr_excerpt"; then
    export TIER0_EXECUTION_CLASSIFICATION="policy_reject"
    export TIER0_EXECUTION_FAILED_CHECK="TOOL_PATH_HOME"
    export TIER0_EXECUTION_REASON="loader transition policy rejected observed env"
    return 0
  fi

  export TIER0_EXECUTION_CLASSIFICATION="command_failed"
  export TIER0_EXECUTION_FAILED_CHECK="loader_transition_contract"
  export TIER0_EXECUTION_REASON="loader transition failed"
  return 0
}

tier0_classify_execution() {
  local phase=${1:?phase}
  local exit_code=${2:?exit_code}
  local stdout_file=${3:?stdout_file}
  local stderr_file=${4:?stderr_file}
  local stdout_excerpt=""

  stdout_excerpt="$(tier0_execution_excerpt "$stdout_file")"
  export TIER0_EXECUTION_STDOUT_EXCERPT="$stdout_excerpt"

  case "$phase" in
    precommit_lint) tier0_classify_precommit_execution "$exit_code" "$stderr_file" ;;
    audit_gate) tier0_classify_audit_execution "$exit_code" "$stderr_file" ;;
    doctor_graph) tier0_classify_doctor_execution "$exit_code" "$stderr_file" ;;
    bootstrap_dry_run) tier0_classify_bootstrap_execution "$exit_code" "$stderr_file" ;;
    git_refresh_status) tier0_classify_git_execution "$exit_code" "$stderr_file" ;;
    dotctl_check) tier0_classify_dotctl_check_execution "$exit_code" "$stderr_file" ;;
    loader_transition_contract) tier0_classify_loader_transition_execution "$exit_code" "$stderr_file" ;;
    *) tier0_classify_generic_execution "$phase" "$exit_code" "$stderr_file" ;;
  esac

  export TIER0_EXECUTION_STDOUT_EXCERPT="$stdout_excerpt"
}
