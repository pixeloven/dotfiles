#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
SRC="$REPO/home/dot_config/herdr/config.toml"

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
