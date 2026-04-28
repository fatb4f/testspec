set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    just --list

test-tier0-matrix:
    bash ./tier-0/tests/tier0/scripts/distrobox-matrix.sh

test-tier0:
    bash ./tier-0/tests/tier0/run.sh --all

test-tier0-kitty-loader-transition:
    bash ./tier-0/tests/tier0/scripts/kitty-run-shell.sh

test-tier0-kitty-run-shell:
    bash ./tier-0/tests/tier0/scripts/kitty-run-shell.sh

test-tier0-kitty-status:
    bash -n ./tier-0/tests/tier0/scripts/kitty-child-wrapper.sh
    bash -n ./tier-0/tests/tier0/lib/tier0_kitty.sh
    bash ./tier-0/tests/tier0/scripts/kitty-status-synthetic.sh
    if command -v bats >/dev/null 2>&1; then bats ./tier-0/tests/tier0/bats/tier0_kitty_status.bats; else echo "bats missing; skipping kitty status bats"; fi

test-tier0-execution-classifier:
    bash -n ./tier-0/tests/tier0/lib/tier0_execution.sh
    bash ./tier-0/tests/tier0/scripts/tier0-execution-synthetic.sh

test-tier0-mutation-guard:
    bash -n ./tier-0/tests/tier0/lib/tier0_mutation_guard.sh
    bash ./tier-0/tests/tier0/scripts/tier0-mutation-synthetic.sh

test-tier0-chaos:
    bash -n ./tier-0/tests/tier0/lib/tier0_chaos.sh
    bash ./tier-0/tests/tier0/scripts/tier0-chaos-synthetic.sh

build-tier0-archive:
    bash ./tier-0/scripts/build-archive.sh ./dist

smoke-tier0-archive:
    bash ./tier-0/scripts/smoke-archive.sh ./dist/tier0-robustness-tests.tar.gz
