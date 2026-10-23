#!/usr/bin/env bash
# Merge the hooks we own into Claude Code's settings.json without tracking that file.
# Usage: claude-settings-merge.sh <settings-path> <fragment-path>
# Appends each fragment hook entry whose commands are not already present; touches nothing else.
# Exit 0 on write or no-op, 2 when the existing settings file is not valid JSON.
set -euo pipefail

settings="$1"
fragment="$2"

if [ ! -e "$settings" ]; then
  mkdir -p "$(dirname "$settings")"
  jq -n --slurpfile f "$fragment" '{hooks: $f[0].hooks}' > "$settings"
  exit 0
fi

if ! jq -e . "$settings" > /dev/null 2>&1; then
  echo "claude-settings-merge: $settings is not valid JSON; leaving it untouched" >&2
  exit 2
fi

tmp="$(mktemp "$settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq --slurpfile f "$fragment" '
  reduce ($f[0].hooks | to_entries[]) as $ev (.;
    reduce $ev.value[] as $entry (.;
      [.hooks[$ev.key][]?.hooks[]?.command] as $have
      | if all($entry.hooks[].command; . as $c | any($have[]; . == $c))
        then .
        else .hooks[$ev.key] += [$entry]
        end))
' "$settings" > "$tmp"

if [ "$(jq -cS . "$settings")" = "$(jq -cS . "$tmp")" ]; then
  exit 0
fi

cp -p "$settings" "$settings.bak-$(date +%Y%m%d%H%M%S)"
mv "$tmp" "$settings"
trap - EXIT
