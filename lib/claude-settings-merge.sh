#!/usr/bin/env bash
# Merge the hooks we own into a settings file that has a top-level "hooks" object (Claude
# Code's settings.json, Codex's hooks.json) without tracking that file.
# Usage: claude-settings-merge.sh <settings-path> <fragment-path> [applied-path]
# Appends each fragment hook entry whose commands are not already present; touches nothing else.
# With applied-path (a copy of the last fragment merged), entries whose commands were in the
# last fragment but are gone from this one are removed, so changing an owned hook never duplicates it.
# Exit 0 on write or no-op, 2 when the existing settings file is not valid JSON.
set -euo pipefail

settings="$1"
fragment="$2"
applied="${3:-}"

record_applied() {
  [ -n "$applied" ] || return 0
  mkdir -p "$(dirname "$applied")"
  cp "$fragment" "$applied"
}

if [ ! -e "$settings" ]; then
  mkdir -p "$(dirname "$settings")"
  jq -n --slurpfile f "$fragment" '{hooks: $f[0].hooks}' > "$settings"
  record_applied
  exit 0
fi

if ! jq -e . "$settings" > /dev/null 2>&1; then
  echo "claude-settings-merge: $settings is not valid JSON; leaving it untouched" >&2
  exit 2
fi

tmp="$(mktemp "$settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

prev='{"hooks":{}}'
[ -n "$applied" ] && [ -f "$applied" ] && prev="$(cat "$applied")"

jq --slurpfile f "$fragment" --argjson prev "$prev" '
  ([$prev.hooks[][].hooks[].command] - [$f[0].hooks[][].hooks[].command]) as $retired
  | if ($retired | length) > 0 and .hooks then
      # Drop only the retired commands; a group is removed only when nothing is left in it.
      .hooks |= with_entries(.value |= map(
        .hooks |= map(select(. as $h | ($retired | index([$h.command])) == null))
        | select((.hooks | length) > 0)))
    else . end
  | reduce ($f[0].hooks | to_entries[]) as $ev (.;
    reduce $ev.value[] as $entry (.;
      [.hooks[$ev.key][]?.hooks[]?.command] as $have
      | if all($entry.hooks[].command; . as $c | any($have[]; . == $c))
        then .
        else .hooks[$ev.key] += [$entry]
        end))
' "$settings" > "$tmp"

if [ "$(jq -cS . "$settings")" = "$(jq -cS . "$tmp")" ]; then
  record_applied
  exit 0
fi

cp -p "$settings" "$settings.bak-$(date +%Y%m%d%H%M%S)"
mv "$tmp" "$settings"
trap - EXIT
record_applied
