#!/usr/bin/env bats

@test "kitty child wrapper publishes exit status and done sentinel" {
  status_dir="$(mktemp -d)"

  run env -i HOME="$HOME" PATH="$PATH" \
    TIER0_KITTY_STATUS_DIR="$status_dir" \
    bash "$BATS_TEST_DIRNAME/../scripts/kitty-child-wrapper.sh" bash -lc 'exit 7'

  [ "$status" -eq 7 ]

  [ -s "$status_dir/status.json" ]
  [ -e "$status_dir/done" ]

  run jq -r '.exit' "$status_dir/status.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 7 ]
}
