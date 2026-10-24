#!/bin/sh
# Make sure ~/.zshrc sources ~/.config/zsh/dotfiles.zsh. ~/.zshrc itself is never tracked (it
# holds private lines such as API keys); we own only the lines between the two markers below.
# Appends the block when it is missing and repairs it in place when edited; every other line is
# left exactly as it was. bin/drift reads LINE from here to report the block missing.
set -eu
BEGIN='# >>> dotfiles >>> (managed by ~/Development/dotfiles; do not edit)'
# shellcheck disable=SC2016  # $HOME is expanded by zsh when ~/.zshrc runs, not here
LINE='[ -r "$HOME/.config/zsh/dotfiles.zsh" ] && source "$HOME/.config/zsh/dotfiles.zsh"'
END='# <<< dotfiles <<<'
RC="$HOME/.zshrc"

[ -f "$RC" ] && grep -qxF "$LINE" "$RC" && exit 0

if [ -f "$RC" ] && grep -qxF "$BEGIN" "$RC" && grep -qxF "$END" "$RC"; then
  tmp="$(mktemp "$RC.XXXXXX")"
  awk -v b="$BEGIN" -v l="$LINE" -v e="$END" '
    $0 == b { print; print l; skip = 1; next }
    skip && $0 == e { skip = 0 }
    !skip { print }' "$RC" > "$tmp"
  cat "$tmp" > "$RC"
  rm -f "$tmp"
  exit 0
fi

if [ -s "$RC" ] && [ -n "$(tail -c 1 "$RC")" ]; then echo >> "$RC"; fi
printf '\n%s\n%s\n%s\n' "$BEGIN" "$LINE" "$END" >> "$RC"
