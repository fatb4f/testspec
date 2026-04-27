set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    just --list

test-tier0-matrix:
    bash ./tier-0/tests/tier0/scripts/distrobox-matrix.sh

test-tier0:
    bash ./tier-0/tests/tier0/run.sh --all
