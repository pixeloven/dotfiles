#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
GHOSTTY="${GHOSTTY:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"

@test "ghostty config validates" {
  run "$GHOSTTY" +validate-config --config-file="$REPO/home/dot_config/ghostty/config.ghostty"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ghostty effective theme" {
  run "$GHOSTTY" +show-config
  [ "$status" -eq 0 ]
  [[ "$(grep '^theme = ' <<<"$output")" == *"Catppuccin Mocha"* ]]
}
