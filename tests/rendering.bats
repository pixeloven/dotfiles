#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
GITCONFIG_SCRIPT="$REPO/home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh"

# bats test_tags=machine
@test "bat theme set" {
  [ -f "$(bat --config-file)" ]
  grep -q '^--theme="Catppuccin Mocha"' "$(bat --config-file)"
  ! grep -q 'Latte' "$(bat --config-file)"
  bat --list-themes | grep -q 'Catppuccin Mocha'
}

# bats test_tags=machine
@test "delta is git pager" {
  [ "$(git config --global core.pager)" = "delta" ]
}

# bats test_tags=machine
@test "gitconfig script is idempotent" {
  sh "$GITCONFIG_SCRIPT"
  first="$(git config --global --list | sort)"
  sh "$GITCONFIG_SCRIPT"
  [ "$(git config --global --list | sort)" = "$first" ]
}

# bats test_tags=machine
@test "user email untouched" {
  before="$(git config --global user.email || true)"
  sh "$GITCONFIG_SCRIPT"
  [ "$(git config --global user.email || true)" = "$before" ]
}

# bats test_tags=machine
@test "glow config set" {
  # glow reads ~/Library/Preferences/glow on macOS and ~/.config/glow elsewhere
  f="$HOME/.config/glow/glow.yml"
  [ "$(uname -s)" = Darwin ] && f="$HOME/Library/Preferences/glow/glow.yml"
  grep -q "^style: \"$HOME/.config/glow/catppuccin-mocha.json\"" "$f"
  grep -q "^pager: true" "$f"
}

@test "glow style is Catppuccin with peach inline code" {
  S="$BATS_TEST_DIRNAME/../home/dot_config/glow/catppuccin-mocha.json"
  [ "$(jq -r '.code.color' "$S")" = "#fab387" ]
  [ "$(jq -r '.document.color' "$S")" = "#cdd6f4" ]
}

# bats test_tags=machine
@test "glow renders with the Catppuccin style" {
  run bash -c "printf '# Hi\\n\\nUse \\`x\\`\\n' | glow -s '$BATS_TEST_DIRNAME/../home/dot_config/glow/catppuccin-mocha.json' -"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hi"* ]] || false
}
