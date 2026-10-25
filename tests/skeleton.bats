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

# The brew script as chezmoi renders it, run with a stub brew that logs its calls.
brew_script() { # <stub-brew-body | none>
  local tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin"
  chezmoi --source "$REPO" execute-template < "$REPO/home/.chezmoiscripts/run_before_00-brew-bundle.sh.tmpl" > "$tmp/brew-bundle.sh"
  if [ "$1" != none ]; then
    printf '#!/bin/sh\necho "$*" >> "%s/calls"\n%s\n' "$tmp" "$1" > "$tmp/bin/brew"
    chmod +x "$tmp/bin/brew"
  fi
  PATH="$tmp/bin:/usr/bin:/bin" sh "$tmp/brew-bundle.sh"
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
