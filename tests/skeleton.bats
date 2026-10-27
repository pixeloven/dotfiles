#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

# bats test_tags=machine
@test "chezmoi sees source root" {
  run chezmoi source-path
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/Development/dotfiles/home" ]
}

@test "brewfile parses" {
  run brew bundle list --file="$REPO/Brewfile" --all
  [ "$status" -eq 0 ]
  for pkg in font-jetbrains-mono bat git-delta glow chezmoi; do
    grep -qxF "$pkg" <<<"$output"
  done
  if [ "$(uname -s)" = Darwin ]; then
    grep -qxF ghostty <<<"$output"
    ! grep -qxF xclip <<<"$output" || false
  else
    grep -qxF wl-clipboard <<<"$output"
    grep -qxF xclip <<<"$output"
    ! grep -qxF ghostty <<<"$output" || false
  fi
}

toolsets_list() { # <HOMEBREW_DOTFILES_TOOLSETS value> : the Brewfile's packages beyond its base list
  env HOMEBREW_DOTFILES_TOOLSETS="$1" brew bundle list --file="$REPO/Brewfile" --all --taps |
    grep -vxF -f <(env -u HOMEBREW_DOTFILES_TOOLSETS brew bundle list --file="$REPO/Brewfile" --all --taps) | LC_ALL=C sort
}

@test "brewfile lists no tool set without HOMEBREW_DOTFILES_TOOLSETS, on any OS" {
  local pkg
  run env -u HOMEBREW_DOTFILES_TOOLSETS brew bundle list --file="$REPO/Brewfile" --all --taps
  [ "$status" -eq 0 ]
  for pkg in $(sed 's/#.*//' "$REPO/lib/toolsets.txt" | awk 'NF { $1 = ""; print }') hashicorp/tap siderolabs/tap; do
    ! grep -qxF "$pkg" <<<"$output" || { echo "unexpected $pkg"; false; }
  done
}

@test "brewfile lists each tool set's formulae and tap, all of them for all, and ignores unknown names" {
  [ "$(toolsets_list kubernetes | paste -sd ' ' -)" = "argocd helm kubernetes-cli" ]
  [ "$(toolsets_list talos | paste -sd ' ' -)" = "siderolabs/tap siderolabs/tap/omnictl siderolabs/tap/talosctl" ]
  [ "$(toolsets_list terraform | paste -sd ' ' -)" = "hashicorp/tap hashicorp/tap/terraform" ]
  [ "$(toolsets_list ansible)" = ansible ]
  [ "$(toolsets_list containers)" = docker ]
  [ "$(toolsets_list bogus,ansible)" = ansible ]
  [ "$(toolsets_list all | wc -l | tr -d ' ')" -eq 10 ]
  [ "$(toolsets_list all)" = "$(toolsets_list kubernetes,talos,terraform,ansible,containers)" ]
  ! toolsets_list all | grep -qxF opentofu || false
}

# The brew script as chezmoi renders it with the given chezmoi data, run with a stub brew that logs
# its calls and the tool sets variable it sees. $3 is the container marker file (absent unless the
# test creates it).
brew_script() { # <stub-brew-body | none> [data-json] [container-marker]
  local tmp="$BATS_TEST_TMPDIR" data='{}'
  [ -z "${2:-}" ] || data="$2"
  mkdir -p "$tmp/bin"
  chezmoi --source "$REPO" --config "$tmp/none.toml" execute-template --override-data "$data" \
    < "$REPO/home/.chezmoiscripts/run_before_00-brew-bundle.sh.tmpl" > "$tmp/brew-bundle.sh" || return
  if [ "$1" != none ]; then
    printf '#!/bin/sh\necho "$*" >> "%s/calls"\necho "sets=$HOMEBREW_DOTFILES_TOOLSETS" >> "%s/env"\n%s\n' "$tmp" "$tmp" "$1" > "$tmp/bin/brew"
    chmod +x "$tmp/bin/brew"
  fi
  env HOMEBREW_DOTFILES_TOOLSETS=inherited DOTFILES_CONTAINER_MARKER="${3:-$tmp/no-containerenv}" PATH="$tmp/bin:/usr/bin:/bin" \
    sh "$tmp/brew-bundle.sh"
}

@test "brew script skips with a message when brew is missing" {
  run brew_script none
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew not found"* ]] || false
}

@test "brew script installs nothing when the Brewfile is satisfied" {
  run brew_script 'exit 0'
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "bundle check --no-upgrade --file=$(cd "$REPO" && pwd)/Brewfile" ]
}

@test "brew script installs when something in the Brewfile is missing" {
  run brew_script 'case "$1 $2" in "bundle check") exit 1 ;; esac'
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/calls")" = "bundle --no-upgrade --file=$(cd "$REPO" && pwd)/Brewfile" ]
}

brew_sets() { # <data-json> : the HOMEBREW_DOTFILES_TOOLSETS the brew script passes to brew
  rm -f "$BATS_TEST_TMPDIR/env"
  brew_script 'case "$1 $2" in "bundle check") exit 1 ;; esac' "$1" >/dev/null && sort -u "$BATS_TEST_TMPDIR/env"
}

@test "brew script passes the tool sets joined by commas, never an inherited value" {
  [ "$(brew_sets '{"toolsets":["kubernetes","terraform"]}')" = "sets=kubernetes,terraform" ]
  [ "$(brew_sets '{"toolsets":[]}')" = "sets=" ]
  [ "$(brew_sets '{}')" = "sets=" ]
  # Unknown names pass through for the Brewfile to ignore; ones a shell would read are dropped.
  [ "$(brew_sets '{"toolsets":["bogus","talos","x;y"]}')" = "sets=bogus,talos" ]
}

@test "brew script follows opsTools until init replaces it with toolsets: true is all, false none" {
  [ "$(brew_sets '{"opsTools":true}')" = "sets=all" ]
  [ "$(brew_sets '{"opsTools":false}')" = "sets=" ]
  [ "$(brew_sets '{"opsTools":true,"toolsets":["ansible"]}')" = "sets=ansible" ]
}

@test "installTarget host installs wherever chezmoi runs" {
  run brew_script 'exit 0' '{"installTarget":"host"}'
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/calls" ]
}

@test "installTarget distrobox installs nothing outside a container" {
  run brew_script 'exit 0' '{"installTarget":"distrobox"}'
  [ "$status" -eq 0 ]
  [ "$output" = "dotfiles: installTarget is distrobox and this is the host; skipping the Brewfile (run chezmoi apply in the box)" ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "installTarget distrobox installs inside the container" {
  touch "$BATS_TEST_TMPDIR/containerenv"
  run brew_script 'exit 0' '{"installTarget":"distrobox"}' "$BATS_TEST_TMPDIR/containerenv"
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/calls" ]
}

@test "the distrobox file builds ubuntu-dev on the shared home, without a GPU" {
  run python3 -I -c '
import configparser, sys
ini = configparser.ConfigParser(strict=True, interpolation=None)
with open(sys.argv[1]) as f:
    ini.read_file(f)
box = ini["ubuntu-dev"]
print(ini.sections(), box["nvidia"], "home" in box)
' "$REPO/lib/distrobox/ubuntu-dev.ini"
  [ "$status" -eq 0 ]
  [ "$output" = "['ubuntu-dev'] false False" ]
}
