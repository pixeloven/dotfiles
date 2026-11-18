#!/usr/bin/env bash
# comfyui-models.sh [--quiet] <folder>... : add each folder to Comfy Desktop's Shared Models.
# Run by home/.chezmoiscripts/run_after_47-comfyui-models.sh.tmpl with comfyui.modelsDirs from the
# settings file (docs/settings.md).
#
# Comfy Desktop (comfyui-desktop-2) keeps its shared model folders in settings.json's modelsDirs; the
# first is the primary, where downloads go. It builds the --extra-model-paths-config file it passes
# ComfyUI from that list at each launch, so settings.json is the file to edit. Each folder is added
# once, after the folders already listed, and the list is never reordered, so "Make primary" in Comfy
# sticks. With an empty list, Comfy's local default (~/ComfyUI-Shared/models) is listed first, so
# downloads stay local. It waits (skips, and says so unless --quiet) until a folder exists, until
# Comfy's first run has written settings.json, and while Comfy is running, since Comfy rewrites the file.
# Checking that a folder exists never mounts an automounted share, so a down server can't stall apply.
# Test seam: DOTFILES_COMFY_SETTINGS.

set -uo pipefail

settings="${DOTFILES_COMFY_SETTINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/comfyui-desktop-2/settings.json}"
quiet=""
[ "${1:-}" = --quiet ] && { quiet=1; shift; }
say() { [ -n "$quiet" ] || echo "comfyui-models: $*"; }

[ "$#" -gt 0 ] || { echo "usage: comfyui-models.sh [--quiet] <folder>..." >&2; exit 2; }
if [ ! -f "$settings" ]; then
  say "no $settings yet; open Comfy Desktop once, finish its first-run setup and quit it, then run chezmoi apply"
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "comfyui-models: jq not found; Comfy Desktop's models folders not set" >&2; exit 1; }
jq -e 'type == "object" and ((.modelsDirs // []) | type == "array")' "$settings" >/dev/null 2>&1 ||
  { echo "comfyui-models: $settings is not the settings file expected; left alone" >&2; exit 1; }

add=()
for dir in "$@"; do
  case "$dir" in /*) ;; *) echo "comfyui-models: '$dir' is not an absolute path; skipped" >&2; continue ;; esac
  jq -e --arg m "$dir" '(.modelsDirs // []) | index($m)' "$settings" >/dev/null && continue
  # Until a share is installed there is no mount point, and Comfy would get a folder that isn't there.
  if [ ! -d "$dir" ]; then
    say "no $dir yet; it is added at the first apply after it exists"
    continue
  fi
  add+=("$dir")
done
[ "${#add[@]}" -gt 0 ] || exit 0

# comfyui-desktop-2, as the kernel's 15-character process name
if pgrep -x comfyui-desktop >/dev/null 2>&1; then
  echo "comfyui-models: Comfy Desktop is running and rewrites its settings; quit it, then run chezmoi apply"
  exit 0
fi

tmp="$settings.dotfiles.tmp"
if ! jq --arg local "$HOME/ComfyUI-Shared/models" --args '
    (.modelsDirs // []) as $d
    | (if ($d | length) == 0 then [$local] else $d end) as $b
    | .modelsDirs = $b + ($ARGS.positional - $b)
  ' "${add[@]}" < "$settings" > "$tmp" || ! chmod "$(stat -c %a "$settings" 2>/dev/null || stat -f %Lp "$settings")" "$tmp" || ! mv "$tmp" "$settings"; then
  rm -f "$tmp"; echo "comfyui-models: could not update $settings" >&2; exit 1
fi
echo "comfyui-models: Comfy Desktop now also reads models from ${add[*]}; downloads still go to its first folder (Settings > Shared Models > Make primary changes that)"
