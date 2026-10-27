#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
SRC="$REPO/home/dot_config/herdr/config.toml"

# bats test_tags=machine
@test "herdr config checks clean" {
  run herdr config check
  [ "$status" -eq 0 ]
  ! grep -qiE 'unknown|ignoring|invalid' <<<"$output"
}

@test "herdr theme values" {
  grep -q '^name = "catppuccin"' "$SRC"
  grep -q '^auto_switch = false' "$SRC"
  ! grep -q 'latte' "$SRC"
}

@test "herdr agents panel grouped by workspace" {
  run python3 -I -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    print(tomllib.load(f)["ui"]["agent_panel_sort"])
' "$SRC"
  [ "$status" -eq 0 ]
  [ "$output" = "spaces" ]
}
