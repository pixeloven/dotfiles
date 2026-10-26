#!/usr/bin/env bash
# Keep the plugins in lib/agent-plugins.txt installed at user scope for Claude Code, Codex and pi,
# all at the pixeloven marketplace's pins. A tool that isn't installed is skipped.
#
# Usage: agent-plugins.sh ensure|update|check
#   ensure  install only what is missing (run by chezmoi apply); a plugin you disabled stays disabled
#   update  bring every installed, enabled plugin to the catalogue's current pins
#   check   read-only; one drift line per finding, as bin/drift prints them:
#           plugin-missing / plugin-behind <tab> <tool> <name>@pixeloven <tab> <suggested action>
# Exit 0, or 1 when an install or update failed (check always exits 0).
# CLAUDE_CONFIG_DIR, CODEX_HOME and PI_CODING_AGENT_DIR move each tool's home, as the tools themselves do;
# AGENT_PLUGINS_MARKETPLACE_URL moves the catalogue that `update` and a first pi install fetch (tests use it).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MARKET=pixeloven
SOURCE=pixeloven/marketplace
URL="${AGENT_PLUGINS_MARKETPLACE_URL:-https://github.com/$SOURCE.git}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
MODE="${1:-}"
FAILED=0
CATALOGUE=""
TMPD=""
trap '[ -z "$TMPD" ] || rm -rf "$TMPD"' EXIT

names() { grep -vE '^[[:space:]]*(#|$)' "$REPO/lib/agent-plugins.txt"; }
say() { echo "agent plugins: $*" >&2; }
emit() { printf '%s\t%s\t%s\n' "$1" "$2 $3@$MARKET" "$4"; }
have() { command -v "$1" >/dev/null 2>&1; }

run() { # run a tool command quietly, reporting it and any failure
  say "$*"
  "$@" </dev/null >/dev/null || { say "failed: $*"; FAILED=1; }
}

catalogue() { # [fetch] : set CATALOGUE to a local copy of the marketplace catalogue
  local f
  [ -n "$CATALOGUE" ] && return 0
  if [ "${1:-}" != fetch ]; then
    for f in "$CLAUDE_DIR/plugins/marketplaces/$MARKET/.claude-plugin/marketplace.json" \
             "$CODEX_DIR/.tmp/marketplaces/$MARKET/.claude-plugin/marketplace.json"; do
      [ -f "$f" ] && { CATALOGUE="$f"; return 0; }
    done
    [ "$MODE" = check ] && return 1
  fi
  TMPD="$(mktemp -d)"
  git clone --quiet --depth 1 "$URL" "$TMPD/m" 2>/dev/null || { say "could not fetch $URL"; FAILED=1; return 1; }
  CATALOGUE="$TMPD/m/.claude-plugin/marketplace.json"
}

pinned() { # <name> : the catalogue's commit SHA for name, or nothing
  [ -n "$CATALOGUE" ] || return 0
  jq -r --arg n "$1" '.plugins[]? | select(.name == $n) | .source.sha // empty' "$CATALOGUE" 2>/dev/null
}

listed() { # <list> <name> : print name's enabled flag from "<name> <enabled>" lines; fail when absent
  awk -v n="$2" '$1 == n { print $2; found = 1 } END { exit !found }' <<<"$1"
}

# --- Claude Code -----------------------------------------------------------------------------
claude_list() { # "<name> <enabled>" for each pixeloven plugin installed at user scope
  claude plugin list --json 2>/dev/null |
    jq -r --arg m "@$MARKET" '.[]? | select(.scope == "user" and (.id | endswith($m))) | "\(.id | rtrimstr($m)) \(.enabled)"'
}

claude_ensure() {
  local list p
  claude plugin marketplace list --json 2>/dev/null | jq -e --arg m "$MARKET" 'any(.[]?; .name == $m)' >/dev/null ||
    run claude plugin marketplace add "$SOURCE" --json
  list="$(claude_list)"
  for p in $(names); do
    listed "$list" "$p" >/dev/null || run claude plugin install "$p@$MARKET" --scope user --json
  done
}

claude_update() {
  local list p
  list="$(claude_list)"
  [ -n "$list" ] || return 0
  run claude plugin marketplace update "$MARKET" --json
  for p in $(names); do
    [ "$(listed "$list" "$p")" = true ] && run claude plugin update "$p@$MARKET" --scope user --json
  done
}

claude_check() {
  local list p want got
  list="$(claude_list)"
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) ;;
      false) continue ;;
      *) emit plugin-missing claude "$p" "chezmoi apply"; continue ;;
    esac
    want="$(pinned "$p")"
    got="$(jq -r --arg id "$p@$MARKET" '.plugins[$id][]? | select(.scope == "user") | .gitCommitSha // empty' \
      "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)"
    [ -n "$want" ] && [ "$got" != "$want" ] && emit plugin-behind claude "$p" "$REPO/lib/agent-plugins.sh update"
  done
}

# --- Codex -----------------------------------------------------------------------------------
codex_list() { # "<name> <enabled> <version>" for each installed pixeloven plugin
  codex plugin list --marketplace "$MARKET" --json 2>/dev/null |
    jq -r '.installed[]? | select(.installed != false) | "\(.name) \(.enabled) \(.version)"'
}

codex_ensure() {
  local list p
  codex plugin marketplace list --json 2>/dev/null | jq -e --arg m "$MARKET" 'any(.marketplaces[]?; .name == $m)' >/dev/null ||
    run codex plugin marketplace add "$SOURCE" --json
  list="$(codex_list)"
  for p in $(names); do
    listed "$list" "$p" >/dev/null || run codex plugin add "$p@$MARKET" --json
  done
}

codex_update() { # `codex plugin add` re-enables a disabled plugin, so only enabled ones are re-added
  local list p
  list="$(codex_list)"
  [ -n "$list" ] || return 0
  run codex plugin marketplace upgrade "$MARKET" --json
  for p in $(names); do
    [ "$(listed "$list" "$p")" = true ] && run codex plugin add "$p@$MARKET" --json
  done
}

codex_check() {
  local list p want got version
  list="$(codex_list)"
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) ;;
      false) continue ;;
      *) emit plugin-missing codex "$p" "chezmoi apply"; continue ;;
    esac
    want="$(pinned "$p")"
    version="$(awk -v n="$p" '$1 == n { print $3 }' <<<"$list")"
    got="$(git -C "$CODEX_DIR/plugins/cache/$MARKET/$p/$version" rev-parse HEAD 2>/dev/null)"
    [ -n "$want" ] && [ "$got" != "$want" ] && emit plugin-behind codex "$p" "$REPO/lib/agent-plugins.sh update"
  done
}

# --- pi --------------------------------------------------------------------------------------
# pi has no plugin marketplace: each plugin is a git package pinned to the catalogue's SHA.
pi_ref() { echo "git:github.com/pixeloven/$1"; }

pi_entry() { # <name> : the settings entry for name (a source string, from an object entry too); fail when absent
  jq -r '(.packages // [])[] | if type == "object" then .source else . end' "$PI_DIR/settings.json" 2>/dev/null |
    awk -v r="$(pi_ref "$1")" 'index($0, r) == 1 && (length($0) == length(r) || substr($0, length(r) + 1, 1) == "@") { print; found = 1; exit }
      END { exit !found }'
}

pi_ensure() {
  local p sha
  for p in $(names); do
    pi_entry "$p" >/dev/null && continue
    catalogue || return 0
    sha="$(pinned "$p")"
    [ -n "$sha" ] || { say "pi: $p is not in the $MARKET catalogue; skipping"; continue; }
    run pi install "$(pi_ref "$p")@$sha"
  done
}

pi_update() { # re-pinning replaces the entry in place and keeps any `pi config` filters on it
  local p entry sha
  catalogue fetch || return 0
  for p in $(names); do
    entry="$(pi_entry "$p")" || continue
    sha="$(pinned "$p")"
    [ -n "$sha" ] && [ "$entry" != "$(pi_ref "$p")@$sha" ] && run pi install "$(pi_ref "$p")@$sha"
  done
}

pi_check() {
  local p entry want
  for p in $(names); do
    entry="$(pi_entry "$p")" || { emit plugin-missing pi "$p" "chezmoi apply"; continue; }
    want="$(pinned "$p")"
    [ -n "$want" ] && [ "$entry" != "$(pi_ref "$p")@$want" ] && emit plugin-behind pi "$p" "$REPO/lib/agent-plugins.sh update"
  done
}

case "$MODE" in
  ensure | update | check) ;;
  *) echo "usage: agent-plugins.sh ensure|update|check" >&2; exit 2 ;;
esac
[ "$MODE" = check ] && catalogue
for tool in claude codex pi; do
  have "$tool" || { [ "$MODE" = check ] || say "$tool not found; skipping"; continue; }
  case "$tool $MODE" in
    "claude ensure") claude_ensure ;; "claude update") claude_update ;; "claude check") claude_check ;;
    "codex ensure") codex_ensure ;;   "codex update") codex_update ;;   "codex check") codex_check ;;
    "pi ensure") pi_ensure ;;         "pi update") pi_update ;;         "pi check") pi_check ;;
  esac
done
[ "$MODE" = check ] && exit 0
exit "$FAILED"
