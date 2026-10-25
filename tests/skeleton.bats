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
  for pkg in ghostty font-jetbrains-mono bat git-delta glow chezmoi; do
    [[ "$output" == *"$pkg"* ]] || false
  done
}
