#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
ZSH_DIR="$REPO/home/dot_config/zsh"
STARSHIP="$REPO/home/dot_config/starship.toml"
SOURCE_SCRIPT="$REPO/home/.chezmoiscripts/run_onchange_after_40-zshrc-source.sh"
LINE='[ -r "$HOME/.config/zsh/dotfiles.zsh" ] && source "$HOME/.config/zsh/dotfiles.zsh"'

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/home/.config"
  cp -R "$ZSH_DIR" "$TMP/home/.config/zsh"
  cp "$STARSHIP" "$TMP/home/.config/starship.toml"
}
teardown() { rm -rf "$TMP"; }

# An interactive zsh in the scratch HOME that sources the tracked config and runs "$1".
in_zsh() {
  HOME="$TMP/home" ZDOTDIR="$TMP/home" STARSHIP_CONFIG="$TMP/home/.config/starship.toml" \
    zsh -i -c "source ~/.config/zsh/dotfiles.zsh; $1" 2>&1 | grep -v "can't change option: zle"
}

@test "zsh files parse" {
  for f in "$ZSH_DIR"/*.zsh; do
    run zsh -n "$f"
    [ "$status" -eq 0 ] || { echo "$f: $output"; false; }
  done
}

@test "syntax-highlighting theme is vendored at a pinned commit with its licence" {
  T="$ZSH_DIR/catppuccin_mocha-zsh-syntax-highlighting.zsh"
  grep -qE 'commit$' "$T"
  grep -qE '^# [0-9a-f]{40} ' "$T"
  grep -q '^MIT License' "$ZSH_DIR/catppuccin-zsh-syntax-highlighting.LICENSE"
}

@test "config loads with every tool wired up" {
  run in_zsh 'bindkey "^R"; bindkey "^T"; alias ls; whence -w z fzf-tab-complete _zsh_autosuggest_start _zsh_highlight _fnm_autoload_hook; print -r -- $ZSH_HIGHLIGHT_STYLES[comment] $PROMPT'
  [[ "$output" == *'"^R" fzf-history-widget'* ]] || false
  [[ "$output" == *'"^T" fzf-file-widget'* ]] || false
  [[ "$output" == *"ls='eza "* ]] || false
  for fn in z fzf-tab-complete _zsh_autosuggest_start _zsh_highlight _fnm_autoload_hook; do
    [[ "$output" == *"$fn: function"* ]] || { echo "missing $fn"; false; }
  done
  [[ "$output" == *'fg=#585b70'* ]] || false
  [[ "$output" == *'starship prompt'* ]] || false
  [[ "$output" != *"not found"* ]] || false
}

@test "config still loads when none of the tools are installed" {
  run env HOME="$TMP/home" ZDOTDIR="$TMP/home" PATH=/usr/bin:/bin \
    zsh -i -c 'source ~/.config/zsh/dotfiles.zsh; echo "rc=$?"; alias ls || echo no-eza; whence fnm || echo no-fnm'
  [[ "$output" == *"rc=0"* ]] || false
  [[ "$output" == *"no-eza"* ]] || false
  [[ "$output" == *"no-fnm"* ]] || false
  [[ "$output" != *"not found"* ]] || false
}

# Starship prints each config warning once per cache dir, so every check gets a fresh one.
starship_warnings() { STARSHIP_CACHE="$(mktemp -d "$TMP/cache.XXXXXX")" STARSHIP_CONFIG="$1" starship prompt 2>&1 >/dev/null; }

@test "starship config parses with no warnings" {
  run starship_warnings "$STARSHIP"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '^palette = "catppuccin_mocha"' "$STARSHIP"
}

@test "starship check catches a broken config" {
  printf '[directory]\nbogus_key = 1\n' > "$TMP/bad.toml"
  run starship_warnings "$TMP/bad.toml"
  [ -n "$output" ]
}

@test "source line script adds the block to a new ~/.zshrc" {
  HOME="$TMP/home" sh "$SOURCE_SCRIPT"
  [ "$(grep -cxF "$LINE" "$TMP/home/.zshrc")" -eq 1 ]
  grep -qx '# >>> dotfiles >>>.*' "$TMP/home/.zshrc"
  grep -qx '# <<< dotfiles <<<' "$TMP/home/.zshrc"
}

@test "source line script is idempotent and keeps every other line" {
  printf 'export SECRET_KEY=abc\nexport PATH="$HOME/pnpm:$PATH"' > "$TMP/home/.zshrc"
  HOME="$TMP/home" sh "$SOURCE_SCRIPT"
  first="$(cat "$TMP/home/.zshrc")"
  HOME="$TMP/home" sh "$SOURCE_SCRIPT"
  [ "$(cat "$TMP/home/.zshrc")" = "$first" ]
  [ "$(grep -cxF "$LINE" "$TMP/home/.zshrc")" -eq 1 ]
  [ "$(sed -n 1p "$TMP/home/.zshrc")" = 'export SECRET_KEY=abc' ]
  [ "$(sed -n 2p "$TMP/home/.zshrc")" = 'export PATH="$HOME/pnpm:$PATH"' ]
}

@test "source line script repairs an edited block in place" {
  HOME="$TMP/home" sh "$SOURCE_SCRIPT"
  sed -i '' "s|dotfiles.zsh\" ] && source|nope|" "$TMP/home/.zshrc"
  echo 'export AFTER=1' >> "$TMP/home/.zshrc"
  HOME="$TMP/home" sh "$SOURCE_SCRIPT"
  [ "$(grep -cxF "$LINE" "$TMP/home/.zshrc")" -eq 1 ]
  [ "$(grep -c '>>> dotfiles >>>' "$TMP/home/.zshrc")" -eq 1 ]
  ! grep -q nope "$TMP/home/.zshrc"
  [ "$(tail -n 1 "$TMP/home/.zshrc")" = 'export AFTER=1' ]
}

@test "brewfile lists the shell tools" {
  run brew bundle list --file="$REPO/Brewfile" --all
  [ "$status" -eq 0 ]
  for pkg in starship zsh-autosuggestions zsh-syntax-highlighting fzf fzf-tab fd zoxide eza fnm font-jetbrains-mono-nerd-font; do
    grep -qx "$pkg" <<<"$output" || { echo "missing $pkg"; false; }
  done
}
