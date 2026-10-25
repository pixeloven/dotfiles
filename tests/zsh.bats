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

# bats test_tags=machine
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
  run env -u HISTFILE HOME="$TMP/home" ZDOTDIR="$TMP/home" HOMEBREW_PREFIX="$TMP/no-brew" PATH=/usr/bin:/bin \
    zsh -i -c 'source ~/.config/zsh/dotfiles.zsh; echo "rc=$?"; echo "histfile=$HISTFILE"; alias ls || echo no-eza; whence fnm || echo no-fnm'
  [[ "$output" == *"rc=0"* ]] || false
  [[ "$output" == *"histfile=$TMP/home/.zsh_history"* ]] || false
  [[ "$output" == *"no-eza"* ]] || false
  [[ "$output" == *"no-fnm"* ]] || false
  [[ "$output" != *"not found"* ]] || false
}

# PATH as dotfiles.zsh leaves it, one dir per line, with a fake Homebrew at $TMP/brew.
# $1 is the starting PATH, $2 the ostree marker file (absent unless the test creates it).
brew_path() {
  local zsh; zsh="$(command -v zsh)"
  mkdir -p "$TMP/brew/bin" "$TMP/brew/sbin"
  HOME="$TMP/home" HOMEBREW_PREFIX="$TMP/brew" DOTFILES_OSTREE_MARKER="${2:-$TMP/no-ostree}" PATH="$1" \
    "$zsh" -f -c 'source ~/.config/zsh/dotfiles.zsh; print -rl -- $path'
}
lines() { printf '%s\n' "$@"; }

@test "homebrew goes ahead of the system dirs, behind ~/.local/bin" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local h="$TMP/home" b="$TMP/brew"
  run brew_path "$h/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$b/bin"
  [ "$status" -eq 0 ]
  [ "$output" = "$(lines "$h/.local/bin" "$b/bin" "$b/sbin" /usr/local/bin /usr/bin /bin /usr/sbin /sbin)" ]
}

@test "homebrew stays behind ~/.local/bin even when ~/.local/bin came after the system dirs" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local h="$TMP/home" b="$TMP/brew"
  run brew_path "$b/bin:/opt/tool/bin:/usr/bin:/bin:$h/.local/bin"
  [ "$status" -eq 0 ]
  [ "$output" = "$(lines /opt/tool/bin "$h/.local/bin" "$b/bin" "$b/sbin" /usr/bin /bin)" ]
}

@test "homebrew already ahead of the system dirs stays put (macOS after brew shellenv)" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local start="$TMP/home/.local/bin:$TMP/brew/bin:$TMP/brew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  run brew_path "$start"
  [ "$status" -eq 0 ]
  [ "$output" = "$(tr : '\n' <<<"$start")" ]
}

@test "an image-based host (ostree marker) keeps homebrew last" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local h="$TMP/home" b="$TMP/brew"
  touch "$TMP/ostree-booted"
  run brew_path "$b/bin:$h/.local/bin:/usr/bin:/bin" "$TMP/ostree-booted"
  [ "$status" -eq 0 ]
  [ "$output" = "$(lines "$h/.local/bin" /usr/bin /bin "$b/bin" "$b/sbin")" ]
}

@test "homebrew is found when HOMEBREW_PREFIX is unset" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local p found=
  for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do [ -x "$p/bin/brew" ] && { found=$p; break; }; done
  [ -n "$found" ] || skip "no Homebrew in a standard prefix"
  run env -u HOMEBREW_PREFIX HOME="$TMP/home" DOTFILES_OSTREE_MARKER="$TMP/no-ostree" PATH=/usr/bin:/bin \
    "$(command -v zsh)" -f -c 'source ~/.config/zsh/dotfiles.zsh; print -r -- "prefix=$HOMEBREW_PREFIX"; print -rl -- $path'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "prefix=$found" ]
  [ "$found" = /usr/local ] || [ "${lines[1]}" = "$found/bin" ]
}

# Starship prints each config warning once per cache dir, so every check gets a fresh one.
starship_warnings() { STARSHIP_CACHE="$(mktemp -d "$TMP/cache.XXXXXX")" STARSHIP_CONFIG="$1" starship prompt 2>&1 >/dev/null; }

@test "starship config parses with no warnings" {
  run starship_warnings "$STARSHIP"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$(STARSHIP_CONFIG="$STARSHIP" starship print-config palette)" == *'palette = "catppuccin_mocha"'* ]] || false
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
  sed -i.bak "s|dotfiles.zsh\" ] && source|nope|" "$TMP/home/.zshrc" && rm "$TMP/home/.zshrc.bak"
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
