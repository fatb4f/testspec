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
    if command -v bats >/dev/null 2>&1; then bats ./tier-0/tests/tier0/bats/tier0_kitty_status.bats; else echo "bats missing; skipping kitty status bats"; fi
