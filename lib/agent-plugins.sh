#!/usr/bin/env bash
# Keep the plugins in lib/agent-plugins.txt installed at user scope for Claude Code, Codex and pi,
# all at one release of pixeloven/crew: that repo serves crew and its packs as the pixeloven
# marketplace, and the release tag in lib/agent-plugins.txt (its @ line) is the only pin.
# A tool that isn't installed is skipped.
#
# Usage: agent-plugins.sh ensure|update|check
#   ensure  point each tool at the pinned release, install what is missing, and bring each installed,
#           enabled plugin that isn't at the pin up to it (run by chezmoi apply). A plugin you disabled
#           stays disabled. A machine still on the old pixeloven/marketplace catalogue moves here too.
#   update  as ensure for what is installed, refreshing even what looks current; installs nothing new
#   check   read-only and offline; one drift line per finding, as bin/drift prints them:
#           plugin-missing / plugin-behind <tab> <tool> <name>@pixeloven <tab> <suggested action>
#           plugin-behind means not at the pinned release's commit: Claude Code's marketplace is on
#           another source or ref, or a plugin's gitCommitSha isn't that marketplace clone's commit;
#           Codex's marketplace is declared or cloned at another source or ref; pi's crew package
#           entry isn't crew at the tag, or an old per-pack package entry is still there.
# Exit 0, or 1 when a step failed (check always exits 0).
# CLAUDE_CONFIG_DIR, CODEX_HOME and PI_CODING_AGENT_DIR move each tool's home, as the tools themselves do.
#
# Moving the pin never uses `claude plugin marketplace remove`: it uninstalls every plugin from that
# marketplace. Claude Code needs the settings declaration changed first, then `marketplace add` of the
# same source; Codex needs its config table rewritten, then `marketplace upgrade`.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$REPO/lib/agent-plugins.txt"
MARKET=pixeloven
SOURCE=pixeloven/crew
CREW="${SOURCE#*/}"                       # the plugin the source repo itself is
GIT_URL="https://github.com/$SOURCE.git"  # how Codex records an owner/repo source
PI_PKG="git:github.com/$SOURCE"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
MODE="${1:-}"
FAILED=0
REF="$(sed -nE 's/^[[:space:]]*@[[:space:]]*([^[:space:]]+).*/\1/p' "$LIST" 2>/dev/null | head -n 1)"

names() { grep -vE '^[[:space:]]*(#|@|$)' "$LIST"; }
say() { echo "agent plugins: $*" >&2; }
BEHIND="not at the pinned crew release $REF; run $REPO/lib/agent-plugins.sh update"
emit() { printf '%s\t%s\t%s\n' "$1" "$2 $3@$MARKET" "$4"; }
have() { command -v "$1" >/dev/null 2>&1; }

run() { # run a tool command quietly, reporting it and any failure; returns its status
  say "$*"
  "$@" </dev/null >/dev/null && return 0
  say "failed: $*"; FAILED=1; return 1
}

json_write() { # <file> <jq args...> : rewrite a JSON file in place through jq, keeping its inode and mode
  local f="$1" tmp; shift
  tmp="$(mktemp "$f.XXXXXX")" || return 1
  jq "$@" "$f" > "$tmp" && cat "$tmp" > "$f"
  local rc=$?; rm -f "$tmp"; return "$rc"
}

listed() { # <list> <name> : print name's enabled flag from "<name> <enabled>" lines; fail when absent
  awk -v n="$2" '$1 == n { print $2; found = 1 } END { exit !found }' <<<"$1"
}

# --- Claude Code -----------------------------------------------------------------------------
claude_list() { # "<name> <enabled>" for each pixeloven plugin installed at user scope
  claude plugin list --json 2>/dev/null |
    jq -r --arg m "@$MARKET" '.[]? | select(.scope == "user" and (.id | endswith($m))) | "\(.id | rtrimstr($m)) \(.enabled)"'
}

claude_head() { # the commit of Claude Code's marketplace clone when it is the pinned release; else nothing
  local known="$CLAUDE_DIR/plugins/known_marketplaces.json" dir
  dir="$(jq -r --arg m "$MARKET" --arg r "$SOURCE" --arg ref "$REF" \
    '.[$m] | select(.source.repo == $r and .source.ref == $ref) | .installLocation // empty' "$known" 2>/dev/null)" || return 0
  [ -n "$dir" ] && git -C "$dir" rev-parse HEAD 2>/dev/null
}

claude_sha() { # <name> : the commit Claude Code installed name from
  jq -r --arg id "$1@$MARKET" '.plugins[$id][]? | select(.scope == "user") | .gitCommitSha // empty' \
    "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null
}

claude_declare() { # declare the pinned source in settings; `marketplace add` refuses one that differs from it
  local f="$CLAUDE_DIR/settings.json" want
  want="$(jq -cn --arg r "$SOURCE" --arg ref "$REF" '{source: "github", repo: $r, ref: $ref}')"
  [ -e "$f" ] || { mkdir -p "$CLAUDE_DIR" && echo '{}' > "$f"; }
  jq -e --arg m "$MARKET" --argjson w "$want" '.extraKnownMarketplaces[$m].source == $w' "$f" >/dev/null 2>&1 && return 0
  jq -e . "$f" >/dev/null 2>&1 || { say "$f is not valid JSON; leaving it and Claude Code's plugins alone"; FAILED=1; return 1; }
  say "declaring the $MARKET marketplace as $SOURCE at $REF in $f"
  # shellcheck disable=SC2016  # jq variables
  json_write "$f" --arg m "$MARKET" --argjson w "$want" '.extraKnownMarketplaces[$m].source = $w' ||
    { say "failed: could not write $f"; FAILED=1; return 1; }
}

claude_sync() {
  local list p head
  list="$(claude_list)"
  [ "$MODE" = update ] && [ -z "$list" ] && return 0
  claude_declare || return 0
  if [ -z "$(claude_head)" ]; then
    run claude plugin marketplace add "$SOURCE#$REF" --json
  elif [ "$MODE" = update ]; then
    run claude plugin marketplace update "$MARKET" --json
  fi
  head="$(claude_head)" # empty when the marketplace couldn't move (offline): install only, update nothing
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) [ -n "$head" ] && { [ "$MODE" = update ] || [ "$(claude_sha "$p")" != "$head" ]; } &&
        run claude plugin update "$p@$MARKET" --scope user --json ;;
      false) ;;
      *) [ "$MODE" = ensure ] && run claude plugin install "$p@$MARKET" --scope user --json ;;
    esac
  done
}

claude_check() {
  local list p head
  list="$(claude_list)"
  head="$(claude_head)"
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) ;;
      false) continue ;;
      *) emit plugin-missing claude "$p" "chezmoi apply"; continue ;;
    esac
    [ -n "$head" ] && [ "$(claude_sha "$p")" = "$head" ] || emit plugin-behind claude "$p" "$BEHIND"
  done
}

# --- Codex -----------------------------------------------------------------------------------
codex_list() { # "<name> <enabled> <version>" for each installed pixeloven plugin
  codex plugin list --marketplace "$MARKET" --json 2>/dev/null |
    jq -r '.installed[]? | select(.installed != false) | "\(.name) \(.enabled) \(.version)"'
}

codex_get() { "$REPO/lib/toml-set.sh" --get "$CODEX_DIR/config.toml" "marketplaces.$MARKET" "$1" 2>/dev/null; }

codex_declared() { [ "$(codex_get source)" = "\"$GIT_URL\"" ] && [ "$(codex_get ref)" = "\"$REF\"" ]; }

codex_cloned() { # Codex's marketplace clone is the pinned release: its install record names the source
  # and ref, and the clone's HEAD is the commit that record says the ref resolved to
  local dir="$CODEX_DIR/.tmp/marketplaces/$MARKET" rev
  rev="$(jq -r --arg s "$GIT_URL" --arg r "$REF" 'select(.source == $s and .ref_name == $r) | .revision // empty' \
    "$dir/.codex-marketplace-install.json" 2>/dev/null)"
  [ -n "$rev" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$rev" ]
}

codex_declare() { # rewrite the existing [marketplaces.pixeloven] table in place, keeping the rest of the file
  local f="$CODEX_DIR/config.toml" t="marketplaces.$MARKET"
  say "declaring the $MARKET marketplace as $GIT_URL at $REF in $f"
  if ! { "$REPO/lib/toml-set.sh" "$f" "$t" source_type '"git"' && "$REPO/lib/toml-set.sh" "$f" "$t" source "\"$GIT_URL\"" &&
    "$REPO/lib/toml-set.sh" "$f" "$t" ref "\"$REF\""; }; then
    say "failed: could not write $f"; FAILED=1; return 1
  fi
}

codex_sync() { # `codex plugin add` re-enables a disabled plugin, so only missing or enabled ones are added
  local list p
  list="$(codex_list)"
  [ "$MODE" = update ] && [ -z "$list" ] && return 0
  if [ -z "$(codex_get source)" ]; then
    run codex plugin marketplace add "$SOURCE" --ref "$REF" --json
  else
    codex_declared || codex_declare || return 0
  fi
  # The upgrade re-points installed plugins too: a moved marketplace needs no re-add. `marketplace
  # add` writes no install record, so a fresh clone is upgraded once to record its pin.
  { [ "$MODE" = update ] || ! codex_cloned; } && run codex plugin marketplace upgrade "$MARKET" --json
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) [ "$MODE" = update ] && run codex plugin add "$p@$MARKET" --json ;;
      false) ;;
      *) [ "$MODE" = ensure ] && run codex plugin add "$p@$MARKET" --json ;;
    esac
  done
}

codex_check() {
  local list p pinned=""
  list="$(codex_list)"
  codex_declared && codex_cloned && pinned=1
  for p in $(names); do
    case "$(listed "$list" "$p")" in
      true) ;;
      false) continue ;;
      *) emit plugin-missing codex "$p" "chezmoi apply"; continue ;;
    esac
    [ -n "$pinned" ] || emit plugin-behind codex "$p" "$BEHIND"
  done
}

# --- pi --------------------------------------------------------------------------------------
# pi has no plugin marketplace: crew is one git package at the tag, and its manifest declares every
# pack's skills, so the unfiltered package carries them all. Machines from before the fold have one
# git:github.com/pixeloven/<name>@<sha> package per plugin; ensure replaces those with crew's.
pi_entry() { # <package> : the settings entry for it (a source string, from an object entry too); fail when absent
  jq -r '(.packages // [])[] | if type == "object" then .source else . end' "$PI_DIR/settings.json" 2>/dev/null |
    awk -v r="$1" 'index($0, r) == 1 && (length($0) == length(r) || substr($0, length(r) + 1, 1) == "@") { print; found = 1; exit }
      END { exit !found }'
}

pi_old() { # the plugins, other than crew, that still have their own pre-fold package entry
  local p
  for p in $(names); do
    [ "$p" != "$CREW" ] && pi_entry "git:github.com/pixeloven/$p" >/dev/null && echo "$p"
  done
}

# shellcheck disable=SC2016  # jq variables
PI_MATCH='(if type == "object" then .source else . end | split("@")[0]) == $pkg'

pi_retire() { # <name> : drop name's pre-fold package; crew's stays unfiltered, so a filter on the old one is reported
  local pkg="git:github.com/pixeloven/$1"
  jq -e --arg pkg "$pkg" "any((.packages // [])[]; select($PI_MATCH) | type == \"object\" and (del(.source) | length) > 0)" \
    "$PI_DIR/settings.json" >/dev/null 2>&1 &&
    say "pi: $1 was turned off or filtered; crew's package loads it now, filter packs/$1/ there: https://github.com/pixeloven/crew/blob/$REF/docs/quickstart-pi.md"
  run pi remove "$(pi_entry "$pkg")"
}

pi_sync() {
  local entry p
  entry="$(pi_entry "$PI_PKG")"
  [ "$MODE" = update ] && [ -z "$entry" ] && [ -z "$(pi_old)" ] && return 0
  # Re-installing replaces the entry in place and keeps any `pi config` filters on it.
  [ "$entry" = "$PI_PKG@$REF" ] || run pi install "$PI_PKG@$REF" || return 0
  for p in $(pi_old); do pi_retire "$p"; done
}

pi_check() {
  local entry p
  if entry="$(pi_entry "$PI_PKG")"; then
    [ "$entry" = "$PI_PKG@$REF" ] || emit plugin-behind pi "$CREW" "$BEHIND"
  else
    emit plugin-missing pi "$CREW" "chezmoi apply"
  fi
  for p in $(pi_old); do emit plugin-behind pi "$p" "$BEHIND"; done
}

case "$MODE" in
  ensure | update | check) ;;
  *) echo "usage: agent-plugins.sh ensure|update|check" >&2; exit 2 ;;
esac
if [ -z "$REF" ]; then
  [ "$MODE" = check ] && exit 0
  say "no @<release tag> line in $LIST"; exit 1
fi
for tool in claude codex pi; do
  have "$tool" || { [ "$MODE" = check ] || say "$tool not found; skipping"; continue; }
  case "$tool $MODE" in
    "claude check") claude_check ;; "codex check") codex_check ;; "pi check") pi_check ;;
    "claude "*) claude_sync ;;      "codex "*) codex_sync ;;      "pi "*) pi_sync ;;
  esac
done
[ "$MODE" = check ] && exit 0
exit "$FAILED"
