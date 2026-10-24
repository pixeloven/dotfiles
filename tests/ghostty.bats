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
  [ "$(grep '^theme = ' <<<"$output")" = "theme = Catppuccin Mocha" ]
}

# The effective value of "$1" when Ghostty loads only the tracked config.
tracked_setting() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/ghostty"
  cp "$REPO/home/dot_config/ghostty/config.ghostty" "$tmp/ghostty/"
  XDG_CONFIG_HOME="$tmp" HOME="$tmp" "$GHOSTTY" +show-config | sed -n "s/^$1 = //p"
  rm -rf "$tmp"
}

@test "ghostty uses the installed JetBrainsMono Nerd Font" {
  [ "$(tracked_setting font-family)" = "JetBrainsMono Nerd Font" ]
  "$GHOSTTY" +list-fonts | grep -q 'JetBrainsMono Nerd Font'
}

@test "ghostty sends left Option as Alt" {
  [ "$(tracked_setting macos-option-as-alt)" = "left" ]
}
