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

@test "brewfile installs the ops tools only inside a Linux container" {
  run brew bundle list --file="$REPO/Brewfile" --all
  [ "$status" -eq 0 ]
  local pkg
  for pkg in kubernetes-cli helm argocd siderolabs/tap/talosctl siderolabs/tap/omnictl hashicorp/tap/terraform ansible docker; do
    if [ "$(uname -s)" = Linux ] && [ -e /run/.containerenv ]; then
      grep -qxF "$pkg" <<<"$output" || { echo "missing $pkg"; false; }
    else
      ! grep -qxF "$pkg" <<<"$output" || { echo "unexpected $pkg"; false; }
    fi
  done
  ! grep -qxF opentofu <<<"$output" || false
}

# The brew script as chezmoi renders it, run with a stub brew that logs its calls. $2 is the ostree
# marker file (absent unless the test creates it).
brew_script() { # <stub-brew-body | none> [ostree-marker]
  local tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin"
  chezmoi --source "$REPO" execute-template < "$REPO/home/.chezmoiscripts/run_before_00-brew-bundle.sh.tmpl" > "$tmp/brew-bundle.sh"
  if [ "$1" != none ]; then
    printf '#!/bin/sh\necho "$*" >> "%s/calls"\n%s\n' "$tmp" "$1" > "$tmp/bin/brew"
    chmod +x "$tmp/bin/brew"
  fi
  DOTFILES_OSTREE_MARKER="${2:-$tmp/no-ostree}" PATH="$tmp/bin:/usr/bin:/bin" sh "$tmp/brew-bundle.sh"
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

@test "brew script installs nothing on an image-based host (ostree marker)" {
  touch "$BATS_TEST_TMPDIR/ostree-booted"
  run brew_script 'exit 0' "$BATS_TEST_TMPDIR/ostree-booted"
  [ "$status" -eq 0 ]
  [ "$output" = "dotfiles: image-based host; install tools in the distrobox, skipping the Brewfile" ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "the distrobox file builds ubuntu-dev on the shared home, without a GPU" {
  local ini="$REPO/lib/distrobox/ubuntu-dev.ini"
  grep -qx '\[ubuntu-dev\]' "$ini"
  grep -qx 'nvidia=false' "$ini"
  ! grep -qE '^home=' "$ini" || false
}
