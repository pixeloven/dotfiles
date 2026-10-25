#!/usr/bin/env bats
# bats file_tags=render
# Renders the source for each OS into throwaway HOMEs. CI runs this on macOS and Linux.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TMP="$(mktemp -d)"
  # A fixed config rather than `chezmoi init`, because --override-data doesn't reach init.
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "ghostty"\ncontainer = false\n' "$REPO" > "$TMP/chezmoi.toml"
}

teardown() { rm -rf "$TMP"; }

render() { # <os> : apply the source as <os> into $TMP/<os> (scripts excluded) and list what it wrote
  mkdir -p "$TMP/$1"
  HOME="$TMP/$1" chezmoi --source "$REPO" --config "$TMP/chezmoi.toml" --persistent-state "$TMP/$1.boltdb" \
    --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" apply --exclude scripts
  (cd "$TMP/$1" && find . \( -type f -o -type l \) | sed 's#^\./##' | LC_ALL=C sort)
}

init_config() { # <os> [chezmoi flags] : render .chezmoi.toml.tmpl as `chezmoi init` would on <os>
  local os="$1"; shift
  chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template --init --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" "$@" < "$REPO/home/.chezmoi.toml.tmpl"
}

@test "macOS gets today's files, plus macos.ghostty" {
  run render darwin
  [ "$status" -eq 0 ]
  expected=".agents/skills/codify/SKILL.md
.agents/skills/lastreply/SKILL.md
.claude/hooks/speak-alert.sh
.claude/skills/codify/SKILL.md
.claude/skills/lastreply/SKILL.md
.claude/themes/catppuccin-mocha.json
.config/bat/config
.config/ghostty/config.ghostty
.config/ghostty/macos.ghostty
.config/glow/catppuccin-mocha.json
.config/herdr/config.toml
.config/starship.toml
.config/zsh/catppuccin-zsh-syntax-highlighting.LICENSE
.config/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh
.config/zsh/dotfiles.zsh
.local/bin/lastreply
Library/Preferences/glow/glow.yml"
  [ "$(grep -v 'config file template has changed' <<<"$output")" = "$expected" ]
}

@test "Linux gets glow in ~/.config and linux.ghostty, and no ~/Library" {
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *.config/glow/glow.yml* ]] || false
  [[ "$output" == *.config/ghostty/linux.ghostty* ]] || false
  [[ "$output" != *macos.ghostty* ]] || false
  [ ! -e "$TMP/linux/Library" ]
}

@test "glow config is the same on both OSes and points at the HOME's Catppuccin style" {
  render darwin > /dev/null
  render linux > /dev/null
  mac="$TMP/darwin/Library/Preferences/glow/glow.yml" linux="$TMP/linux/.config/glow/glow.yml"
  grep -qxF "style: \"$TMP/darwin/.config/glow/catppuccin-mocha.json\"" "$mac"
  [ "$(sed "s#$TMP/darwin#H#" "$mac")" = "$(sed "s#$TMP/linux#H#" "$linux")" ]
}

@test "macOS init asks nothing and picks Ghostty" {
  run init_config darwin --promptChoice "Terminal app on this Linux machine=other"
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "ghostty"'* ]] || false
}

@test "Linux init records the terminal answer, defaulting to Ptyxis" {
  run init_config linux --promptChoice "Terminal app on this Linux machine=other"
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "other"'* ]] || false
  VTE_VERSION= run init_config linux
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "ptyxis"'* ]] || false
  [[ "$output" == *$'\ncontainer = '* ]] || false
}
