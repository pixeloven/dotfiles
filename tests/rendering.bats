#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
GITCONFIG_SCRIPT="$REPO/home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh"

@test "bat theme set" {
  [ -f "$(bat --config-file)" ]
  grep -q 'Catppuccin Mocha' "$(bat --config-file)"
  bat --list-themes | grep -q 'Catppuccin Mocha'
}

@test "delta is git pager" {
  [ "$(git config --global core.pager)" = "delta" ]
}

@test "gitconfig script is idempotent" {
  sh "$GITCONFIG_SCRIPT"
  first="$(git config --global --list | sort)"
  sh "$GITCONFIG_SCRIPT"
  [ "$(git config --global --list | sort)" = "$first" ]
}

@test "user email untouched" {
  before="$(git config --global user.email || true)"
  sh "$GITCONFIG_SCRIPT"
  [ "$(git config --global user.email || true)" = "$before" ]
}

@test "glow config set" {
  grep -q "^style: \"auto\"" "$HOME/Library/Preferences/glow/glow.yml"
  grep -q "^pager: true" "$HOME/Library/Preferences/glow/glow.yml"
}
