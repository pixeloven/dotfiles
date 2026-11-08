#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
SRC="$REPO/home/dot_config/herdr/config.toml.tmpl"

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

render() { # <os> : the herdr config as chezmoi writes it on <os>
  chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template \
    --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" < "$SRC"
}

toml_get() { # <section> <key> : read a value from the TOML on stdin ("" when absent)
  python3 -I -c '
import sys, tomllib
print(tomllib.load(sys.stdin.buffer).get(sys.argv[1], {}).get(sys.argv[2], ""))
' "$1" "$2"
}

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
  for os in darwin linux; do
    render "$os" > "$TMP/$os.toml"
    [ "$(toml_get ui agent_panel_sort < "$TMP/$os.toml")" = "spaces" ] || { echo "not spaces on $os"; false; }
  done
}

# distrobox sets SHELL=bash in the box, so a herdr server started from it would open bash panes.
# Linux pins zsh; macOS leaves the pane shell to $SHELL.
@test "herdr pins the pane shell to zsh on Linux only" {
  render linux > "$TMP/linux.toml"
  render darwin > "$TMP/darwin.toml"
  [ "$(toml_get terminal default_shell < "$TMP/linux.toml")" = "/usr/bin/zsh" ]
  [ -z "$(toml_get terminal default_shell < "$TMP/darwin.toml")" ]
  ! grep -q '^\[terminal\]' "$TMP/darwin.toml"
}
