#!/usr/bin/env bash
set -euo pipefail

archive="${1:?archive path}"
work="$(mktemp -d)"

tar -C "$work" -xzf "$archive"
cd "$work/tier0-robustness-tests"

test -r README.md
test -r CRAWL.md
test -r manifest.json
test -r Justfile.tier0-snippet
test -d tests/tier0
test -r tests/tier0/run.sh
test -r tests/tier0/scripts/distrobox-matrix.sh

bash -n tests/tier0/run.sh
bash -n tests/tier0/scripts/distrobox-matrix.sh

if grep -RIn '/home/x404' . >/dev/null 2>&1; then
  printf 'archive contains hardcoded host path\n' >&2
  exit 1
fi

printf 'tier0 archive smoke ok\n'
