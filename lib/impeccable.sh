#!/usr/bin/env bash
# Keep the Impeccable design skill installed at user scope for Claude Code, Codex and pi, at the version
# pinned in lib/impeccable.txt. A tool that isn't installed is skipped.
#
# Usage: impeccable.sh ensure|check|latest
#   ensure  install the pin where the skill is missing or older (run by chezmoi apply); a newer copy is
#           left alone. A copy this script did not install is backed up first, to the backup dir below.
#   check   read-only and offline; one drift line per finding, as bin/drift prints them:
#           skill-missing / skill-behind / skill-ahead <tab> <tool> impeccable@<pin> <tab> <suggested action>
#   latest  print the pin and the latest published version (network); bump the pin to update
# Exit 0, or 1 when a download or install failed (check always exits 0).
#
# Installs run Impeccable's own installer, `npx impeccable@<pin> install --user`, from $HOME so it never
# writes into a project. That installer always fetches the newest bundle, so it is handed the pinned
# release's bundle through IMPECCABLE_BUNDLE_PATH instead. Claude Code gets the skill's design hook
# (in ~/.claude/settings.json); Codex and pi get none (--no-hooks).
# Skill dirs, as the installer places them: ~/.claude/skills, ~/.agents/skills (Codex), ~/.pi/agent/skills.
# IMPECCABLE_RELEASE_URL moves the release downloads and IMPECCABLE_REGISTRY_URL the npm registry (tests).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RELEASES="${IMPECCABLE_RELEASE_URL:-https://github.com/pbakaus/impeccable/releases/download}"
REGISTRY="${IMPECCABLE_REGISTRY_URL:-https://registry.npmjs.org}"
STATE="$HOME/.local/state/dotfiles/impeccable" # <tool> holds the version this script installed there
MODE="${1:-}"
PIN="$(grep -vE '^[[:space:]]*(#|$)' "$REPO/lib/impeccable.txt" | head -n 1 | tr -d '[:space:]')"
FAILED=0
TMPD=""
trap '[ -z "$TMPD" ] || rm -rf "$TMPD"' EXIT

say() { echo "impeccable: $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
emit() { printf '%s\t%s\t%s\n' "$1" "$2 impeccable@$PIN" "$3"; }

dir() { # <tool> : where Impeccable's installer puts the skill for that tool
  case "$1" in
    claude) echo "$HOME/.claude/skills/impeccable" ;;
    codex) echo "$HOME/.agents/skills/impeccable" ;;
    pi) echo "$HOME/.pi/agent/skills/impeccable" ;;
  esac
}

installed() { # <tool> : the installed skill's version, or nothing. The frontmatter carries it at top
  # level, or under metadata: in the Codex copy, as the installer itself reads it.
  awk 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit }
    f && /^[[:space:]]*version:/ { sub(/^[[:space:]]*version:[[:space:]]*/, ""); gsub(/["\047\r ]/, ""); print; exit }' \
    "$(dir "$1")/SKILL.md" 2>/dev/null
}

older() { # <a> <b> : a is an earlier version than b
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]
}

backup() { # <tool> <version> : copy an install this script did not make before the installer replaces it
  local to
  [ "$(cat "$STATE/$1" 2>/dev/null)" = "$2" ] && return 0
  to="$STATE/backup/$1-$2-$(date +%Y%m%d%H%M%S)"
  { mkdir -p "$STATE/backup" && cp -R "$(dir "$1")" "$to"; } || { say "could not back up $(dir "$1"); leaving it"; return 1; }
  say "backed up $(dir "$1") ($2) to $to"
}

install() { # <args...> : run the pinned installer on the pinned bundle from $HOME, quietly
  say "npx impeccable@$PIN install -y --user $*"
  (cd "$HOME" && IMPECCABLE_BUNDLE_PATH="$TMPD/universal.zip" npx --yes "impeccable@$PIN" install -y --user "$@") \
    </dev/null >/dev/null || { say "failed: npx impeccable@$PIN install -y --user $*"; FAILED=1; }
}

ensure() {
  local tool got want=() rest=()
  for tool in claude codex pi; do
    have "$tool" || { say "$tool not found; skipping"; continue; }
    got="$(installed "$tool")"
    [ -z "$got" ] || older "$got" "$PIN" || continue
    [ -z "$got" ] || backup "$tool" "$got" || { FAILED=1; continue; }
    want+=("$tool")
  done
  [ ${#want[@]} -gt 0 ] || return 0
  have npx || { say "npx not found (install node); skipping"; FAILED=1; return 0; }
  TMPD="$(mktemp -d)"
  curl -fsSL -o "$TMPD/universal.zip" "$RELEASES/skill-v$PIN/universal.zip" ||
    { say "could not fetch $RELEASES/skill-v$PIN/universal.zip"; FAILED=1; return 0; }
  for tool in "${want[@]}"; do
    if [ "$tool" = claude ]; then install --providers=claude; else rest+=("$tool"); fi
  done
  [ ${#rest[@]} -eq 0 ] || install --no-hooks --providers="$(IFS=,; echo "${rest[*]}")"
  mkdir -p "$STATE"
  for tool in "${want[@]}"; do
    if [ "$(installed "$tool")" = "$PIN" ]; then echo "$PIN" > "$STATE/$tool"
    else say "$tool: $(dir "$tool") is not at $PIN after install"; FAILED=1; fi
  done
}

check() {
  local tool got
  for tool in claude codex pi; do
    have "$tool" || continue
    got="$(installed "$tool")"
    if [ -z "$got" ]; then emit skill-missing "$tool" "chezmoi apply"
    elif older "$got" "$PIN"; then emit skill-behind "$tool" "chezmoi apply"
    elif older "$PIN" "$got"; then emit skill-ahead "$tool" "set lib/impeccable.txt to $got"
    fi
  done
}

latest() {
  local v
  v="$(curl -fsSL "$REGISTRY/impeccable/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)"
  [ -n "$v" ] || { say "could not read the latest version from $REGISTRY"; exit 1; }
  echo "impeccable: pinned $PIN, latest $v"
  older "$PIN" "$v" && echo "to update: set $REPO/lib/impeccable.txt to $v, then chezmoi apply"
  return 0
}

[ -n "$PIN" ] || { say "no version in $REPO/lib/impeccable.txt"; exit 1; }
case "$MODE" in
  ensure) ensure ;;
  check) check; exit 0 ;;
  latest) latest ;;
  *) echo "usage: impeccable.sh ensure|check|latest" >&2; exit 2 ;;
esac
exit "$FAILED"
