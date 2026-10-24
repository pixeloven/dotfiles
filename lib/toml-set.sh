#!/usr/bin/env bash
# Set one key in one table of a TOML file we don't own (e.g. ~/.codex/config.toml), editing
# only that line so every other setting, comment and secret stays exactly as it was.
# Usage: toml-set.sh <file> <table> <key> <toml-value>     e.g. ... tui theme '"catppuccin-mocha"'
#        toml-set.sh --get <file> <table> <key>            prints the current raw value, if any
# Backs the file up to <file>.bak-dotfiles before its first change; no-op when already set.
# Exit 0 on write or no-op, 3 when the table is written inline (`tui = {...}`) and we won't guess.
set -euo pipefail

get=""
if [ "${1:-}" = --get ]; then get=1; shift; fi
file="$1" table="$2" key="$3" value="${4:-}"

if [ -n "$get" ]; then
  [ -f "$file" ] || exit 0
  awk -v t="[$table]" -v k="$key" '
    /^[[:space:]]*\[/ { cur = $0; sub(/[[:space:]]+$/, "", cur) }
    cur == t && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", ""); print; exit }
  ' "$file"
  exit 0
fi

if [ ! -e "$file" ]; then
  mkdir -p "$(dirname "$file")"
  printf '[%s]\n%s = %s\n' "$table" "$key" "$value" > "$file"
  exit 0
fi

if grep -qE "^[[:space:]]*${table}[[:space:]]*=" "$file"; then
  echo "toml-set: $file defines $table inline; set $table.$key by hand" >&2
  exit 3
fi

tmp="$(mktemp "$file.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v t="[$table]" -v k="$key" -v line="$key = $value" '
  function header(s) { sub(/[[:space:]]+$/, "", s); return s }
  /^[[:space:]]*\[/ {
    # Leaving our table without the key: add it at the table end, before the blank lines.
    if (cur == t && !done) { print line; done = 1 }
    for (i = 0; i < blanks; i++) print ""
    blanks = 0
    cur = header($0); if (cur == t) seen = 1
    print; next
  }
  /^[[:space:]]*$/ { blanks++; next }
  {
    for (i = 0; i < blanks; i++) print ""
    blanks = 0
    if (cur == t && $0 ~ "^[[:space:]]*" k "[[:space:]]*=") { print line; done = 1; next }
    print
  }
  END {
    if (cur == t && !done) { print line; done = 1 }
    for (i = 0; i < blanks; i++) print ""
    if (!seen) { print ""; print t; print line }
  }
' "$file" > "$tmp"

cmp -s "$file" "$tmp" && exit 0
[ -e "$file.bak-dotfiles" ] || cp -p "$file" "$file.bak-dotfiles"
cat "$tmp" > "$file"
