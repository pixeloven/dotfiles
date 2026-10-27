#!/usr/bin/env bats
# bats file_tags=render
# Renders the source for each OS into throwaway HOMEs. CI runs this on macOS and Linux.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TMP="$(mktemp -d)"
  config ghostty
}

config() { # <terminal> : a fixed config rather than `chezmoi init`, because --override-data doesn't reach init
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "%s"\ncontainer = false\n' "$REPO" "$1" > "$TMP/chezmoi.toml"
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
.config/zsh/op-env.zsh
.local/bin/lastreply
.local/bin/speak-kokoro
.local/bin/toolsets
.local/bin/voice
.local/bin/voice-cloud
Library/Preferences/glow/glow.yml"
  [ "$(grep -v 'config file template has changed' <<<"$output")" = "$expected" ]
}

@test "Linux with Ghostty gets glow in ~/.config and linux.ghostty, and no ~/Library or Ptyxis palette" {
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *.config/glow/glow.yml* ]] || false
  [[ "$output" == *.config/ghostty/linux.ghostty* ]] || false
  [[ "$output" != *macos.ghostty* ]] || false
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  [[ "$output" == *.local/bin/dictate* ]] || false
  [ ! -e "$TMP/linux/Library" ]
}

@test "Linux with Ptyxis also gets the Catppuccin Ptyxis palette" {
  palette=.local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette
  config ptyxis
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *$palette* ]] || false
}

@test "the Ptyxis settings script renders nothing without Ptyxis" {
  script() { # <os> <terminal> <container>
    chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template \
      --override-data "{\"chezmoi\":{\"os\":\"$1\"},\"terminal\":\"$2\",\"container\":$3}" \
      < "$REPO/home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl"
  }
  [ -z "$(script linux ghostty false)" ]
  [ -z "$(script darwin ghostty false)" ]
}

@test "glow config is the same on both OSes and points at the HOME's Catppuccin style" {
  render darwin > /dev/null
  render linux > /dev/null
  mac="$TMP/darwin/Library/Preferences/glow/glow.yml" linux="$TMP/linux/.config/glow/glow.yml"
  grep -qxF "style: \"$TMP/darwin/.config/glow/catppuccin-mocha.json\"" "$mac"
  [ "$(sed "s#$TMP/darwin#H#" "$mac")" = "$(sed "s#$TMP/linux#H#" "$linux")" ]
}

TOOLSETS_PROMPT="Ops tool sets to install (lib/toolsets.txt; none by default)"

@test "macOS init asks only about the tool sets, and picks Ghostty and the host" {
  run init_config darwin --promptChoice "Terminal app on this Linux machine=other" \
    --promptChoice "Install tools on this host, or only inside a distrobox=distrobox"
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "ghostty"'* ]] || false
  [[ "$output" == *'installTarget = "host"'* ]] || false
  [[ "$output" == *$'\ntoolsets = []\n'* ]] || false
  [[ "$output" != *"opsTools ="* ]] || false
}

@test "init records the tool sets answer on both OSes, defaulting to none" {
  local os
  for os in darwin linux; do
    run init_config "$os" --promptMultichoice "$TOOLSETS_PROMPT=kubernetes/terraform"
    [ "$status" -eq 0 ]
    [[ "$output" == *'toolsets = ["kubernetes", "terraform"]'* ]] || { echo "$os: $output"; false; }
  done
}

@test "the init choices are the sets in lib/toolsets.txt" {
  local want
  want="$(sed 's/#.*//' "$REPO/lib/toolsets.txt" | awk 'NF { print $1 }' | paste -sd / -)"
  run init_config darwin --promptMultichoice "$TOOLSETS_PROMPT=$want"
  [ "$status" -eq 0 ]
  [[ "$output" == *'toolsets = ["kubernetes", "talos", "terraform", "ansible", "containers"]'* ]] || false
}

re_init() { # <os> <old [data] lines> [chezmoi flags] : render the init template over an existing config, as a re-init does
  local os="$1"
  printf '[data]\n%s\n' "$2" > "$TMP/old.toml"
  shift 2
  chezmoi --source "$REPO" --config "$TMP/old.toml" execute-template --init --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" "$@" < "$REPO/home/.chezmoi.toml.tmpl"
}

@test "re-init turns the old opsTools answer into tool sets without asking: yes is all, no is none" {
  local os
  for os in darwin linux; do
    # A tool sets answer here would show up as kubernetes alone; the legacy seed must win.
    run re_init "$os" $'terminal = "ptyxis"\ninstallTarget = "host"\nopsTools = true' \
      --promptMultichoice "$TOOLSETS_PROMPT=kubernetes"
    [ "$status" -eq 0 ]
    [[ "$output" == *'toolsets = ["kubernetes", "talos", "terraform", "ansible", "containers"]'* ]] || { echo "$os: $output"; false; }
    [[ "$output" != *"opsTools ="* ]] || false
    run re_init "$os" $'terminal = "ptyxis"\ninstallTarget = "host"\nopsTools = false' \
      --promptMultichoice "$TOOLSETS_PROMPT=kubernetes"
    [[ "$output" == *$'\ntoolsets = []\n'* ]] || { echo "$os: $output"; false; }
  done
}

@test "re-init keeps the tool sets already chosen" {
  run re_init darwin 'toolsets = ["talos"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'toolsets = ["talos"]'* ]] || false
}

@test "re-init keeps the keys set by hand" {
  run re_init darwin $'agentPlugins = false\noperatorPersona = "operator"\noperatorHome = "~/Development/operator"'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nagentPlugins = false'* ]] || false
  [[ "$output" == *$'\noperatorPersona = "operator"'* ]] || false
  [[ "$output" == *$'\noperatorHome = "~/Development/operator"'* ]] || false
  run init_config darwin
  [[ "$output" != *agentPlugins* ]] || false
  [[ "$output" != *operator* ]] || false
}

@test "Linux init records where tools install" {
  run init_config linux --promptChoice "Install tools on this host, or only inside a distrobox=distrobox"
  [ "$status" -eq 0 ]
  [[ "$output" == *'installTarget = "distrobox"'* ]] || false
  { [ -e /run/ostree-booted ] || [ -e /run/host/run/ostree-booted ]; } && skip "an image-based host suggests distrobox"
  run init_config linux
  [ "$status" -eq 0 ]
  [[ "$output" == *'installTarget = "host"'* ]] || false
}

@test "the installTarget answer reaches zsh on Linux only" {
  run render linux
  [[ "$output" == *.config/zsh/dotfiles-target.zsh* ]] || false
  grep -qx '_dotfiles_install_target="host"' "$TMP/linux/.config/zsh/dotfiles-target.zsh"
  run render darwin
  [[ "$output" != *dotfiles-target* ]] || false
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
