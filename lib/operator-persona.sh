#!/bin/sh
# Select the operator persona theme in an operator home; run by
# home/.chezmoiscripts/run_onchange_after_50-operator-persona.sh.tmpl when the chezmoi data key
# operatorPersona is set. Writes only the first line of <home>/config/po-theme, and only when it
# differs; the operator's own bin/po-theme.sh stays the only writer of its derived state
# (data/captain-shared.md, alias skills). Skips (exit 0) when the home is missing, has no
# executable bin/po-theme.sh, or is a secondmate home.
#
# Usage: operator-persona.sh <name> [home]   (home defaults to ~/Development/operator)
set -eu
name="$1"
home="${2:-$HOME/Development/operator}"
# shellcheck disable=SC2088  # matching a literal ~, not expanding one
case "$home" in "~") home="$HOME" ;; "~/"*) home="$HOME/${home#"~/"}" ;; esac
po="$home/bin/po-theme.sh"

skip() { echo "operator persona: $1; skipping"; exit 0; }
[ -d "$home" ] || skip "no operator home at $home"
[ -x "$po" ] || skip "$po is not executable"
[ ! -e "$home/.fm-secondmate-home" ] || skip "$home is a secondmate home"

"$po" validate "$name"
sel="$home/config/po-theme"
if [ "$(head -n 1 "$sel" 2>/dev/null)" != "$name" ]; then
  mkdir -p "$home/config"
  echo "$name" > "$sel"
fi
"$po" apply
"$po" verify
