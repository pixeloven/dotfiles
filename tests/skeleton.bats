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

OPS_TOOLS=(kubernetes-cli helm argocd siderolabs/tap/talosctl siderolabs/tap/omnictl hashicorp/tap/terraform ansible docker)

@test "brewfile lists the ops tools only when the opsTools answer turns them on, on any OS" {
  local pkg
  run env -u HOMEBREW_DOTFILES_OPS_TOOLS brew bundle list --file="$REPO/Brewfile" --all
  [ "$status" -eq 0 ]
  for pkg in "${OPS_TOOLS[@]}"; do
    ! grep -qxF "$pkg" <<<"$output" || { echo "unexpected $pkg"; false; }
  done
  run env HOMEBREW_DOTFILES_OPS_TOOLS=1 brew bundle list --file="$REPO/Brewfile" --all
  [ "$status" -eq 0 ]
  for pkg in "${OPS_TOOLS[@]}"; do
    grep -qxF "$pkg" <<<"$output" || { echo "missing $pkg"; false; }
  done
  ! grep -qxF opentofu <<<"$output" || false
}

# The brew script as chezmoi renders it with the given chezmoi data, run with a stub brew that logs
# its calls and the ops tools variable it sees. $3 is the container marker file (absent unless the
# test creates it).
brew_script() { # <stub-brew-body | none> [data-json] [container-marker]
  local tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin"
  chezmoi --source "$REPO" --config "$tmp/none.toml" execute-template --override-data "${2:-{\}}" \
    < "$REPO/home/.chezmoiscripts/run_before_00-brew-bundle.sh.tmpl" > "$tmp/brew-bundle.sh"
  if [ "$1" != none ]; then
    printf '#!/bin/sh\necho "$*" >> "%s/calls"\necho "ops=$HOMEBREW_DOTFILES_OPS_TOOLS" >> "%s/env"\n%s\n' "$tmp" "$tmp" "$1" > "$tmp/bin/brew"
    chmod +x "$tmp/bin/brew"
  fi
  env -u HOMEBREW_DOTFILES_OPS_TOOLS DOTFILES_CONTAINER_MARKER="${3:-$tmp/no-containerenv}" PATH="$tmp/bin:/usr/bin:/bin" \
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

@test "brew script turns on the ops tools only when opsTools is true" {
  run brew_script 'case "$1 $2" in "bundle check") exit 1 ;; esac' '{"opsTools":false}'
  [ "$status" -eq 0 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/env")" = "ops=" ]
  rm "$BATS_TEST_TMPDIR/env"
  run brew_script 'case "$1 $2" in "bundle check") exit 1 ;; esac' '{"opsTools":true}'
  [ "$status" -eq 0 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/env")" = "ops=1" ]
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
