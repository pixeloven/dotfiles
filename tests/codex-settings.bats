#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
SET="$REPO/lib/toml-set.sh"

setup() {
  TMP="$(mktemp -d)"
  CFG="$TMP/config.toml"
}

teardown() { rm -rf "$TMP"; }

@test "adds a missing table at the end and keeps everything else" {
  printf 'model = "m"\n\n[features]\nhooks = true\n' > "$CFG"
  run "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$status" -eq 0 ]
  [ "$(sed -n 1,4p "$CFG")" = "$(printf 'model = "m"\n\n[features]\nhooks = true')" ]
  grep -qx '\[tui\]' "$CFG"
  grep -qx 'theme = "catppuccin-mocha"' "$CFG"
}

@test "replaces the key inside an existing table only" {
  printf '[tui]\ntheme = "dracula"\nanimations = false\n\n[other]\ntheme = "keep"\n' > "$CFG"
  "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$(cat "$CFG")" = "$(printf '[tui]\ntheme = "catppuccin-mocha"\nanimations = false\n\n[other]\ntheme = "keep"')" ]
}

@test "inserts into an existing table before the next one" {
  printf '[tui]\nanimations = false\n\n[other]\nx = 1\n' > "$CFG"
  "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$(sed -n 1,3p "$CFG")" = "$(printf '[tui]\nanimations = false\ntheme = "catppuccin-mocha"')" ]
  grep -qx '\[other\]' "$CFG"
}

@test "is a no-op when the value is already set" {
  printf '[tui]\ntheme = "catppuccin-mocha"\n' > "$CFG"
  before="$(stat -f %m "$CFG")"
  sleep 1
  "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$(stat -f %m "$CFG")" = "$before" ]
  [ ! -e "$CFG.bak-dotfiles" ]
}

@test "backs up the file before its first change" {
  printf 'model = "m"\n' > "$CFG"
  "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$(cat "$CFG.bak-dotfiles")" = 'model = "m"' ]
}

@test "creates the file when absent" {
  "$SET" "$TMP/new/config.toml" tui theme '"catppuccin-mocha"'
  grep -qx 'theme = "catppuccin-mocha"' "$TMP/new/config.toml"
}

@test "refuses an inline tui table rather than guessing" {
  printf 'tui = { theme = "x" }\n' > "$CFG"
  run "$SET" "$CFG" tui theme '"catppuccin-mocha"'
  [ "$status" -eq 3 ]
  [ "$(cat "$CFG")" = 'tui = { theme = "x" }' ]
}

@test "--get reads the current value" {
  printf '[tui]\ntheme = "dracula"\n' > "$CFG"
  run "$SET" --get "$CFG" tui theme
  [ "$output" = '"dracula"' ]
}

@test "owned keys list sets the Catppuccin theme" {
  grep -qx 'tui theme "catppuccin-mocha"' "$REPO/lib/codex-owned-keys.txt"
}
