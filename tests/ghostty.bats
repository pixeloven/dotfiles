#!/usr/bin/env bats
# bats file_tags=machine

REPO="$BATS_TEST_DIRNAME/.."
GHOSTTY="${GHOSTTY:-$(command -v ghostty || echo /Applications/Ghostty.app/Contents/MacOS/ghostty)}"

setup() {
  [ -x "$GHOSTTY" ] || skip "Ghostty not installed"
}

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

# The effective value of "$1" when Ghostty loads only the tracked config (and this OS's include).
tracked_setting() {
  local tmp os=linux
  [ "$(uname -s)" = Darwin ] && os=macos
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/ghostty"
  cp "$REPO/home/dot_config/ghostty/config.ghostty" "$REPO/home/dot_config/ghostty/$os.ghostty" "$tmp/ghostty/"
  XDG_CONFIG_HOME="$tmp" HOME="$tmp" "$GHOSTTY" +show-config | sed -n "s/^$1 = //p"
  rm -rf "$tmp"
}

@test "ghostty uses the installed JetBrainsMono Nerd Font" {
  [ "$(tracked_setting font-family)" = "JetBrainsMono Nerd Font" ]
  "$GHOSTTY" +list-fonts | grep -q 'JetBrainsMono Nerd Font'
}

@test "ghostty sends left Option as Alt" {
  [ "$(uname -s)" = Darwin ] || skip "macOS only"
  [ "$(tracked_setting macos-option-as-alt)" = "left" ]
}
