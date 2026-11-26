#!/usr/bin/env bash
# comfyui-settings.sh [--quiet] [--root <folder>] [<models folder>...] : Comfy Desktop's folders.
# Run by home/.chezmoiscripts/run_after_47-comfyui.sh.tmpl with comfyui.root and comfyui.modelsDirs
# from the settings file (docs/settings.md).
#
# Comfy Desktop (comfyui-desktop-2) keeps its folders in settings.json: installDir, modelsDirs (the
# first is the primary, where downloads go), inputDir, outputDir and cacheDir. The same file holds its
# telemetry choice, device and workspace ids and the rest; this script only ever merges the keys named
# here, and leaves every other key as it is.
#
# --root: until Comfy's first run is done, its folders nest under <folder>: installs, models, input,
#   output and cache. Each folder is created first, because at launch Comfy puts inputDir and outputDir
#   back to ~/ComfyUI-Shared when theirs is missing, and ~/ComfyUI-Shared/models first in modelsDirs
#   when none of its models folders exists. The first run is done once settings.json has
#   firstUseCompleted, or Comfy has recorded an install in installations.json; from then on the folders
#   are Comfy's, changed in its Settings, and never by this script. Where Comfy Desktop isn't
#   installed, it does nothing.
# <models folder>: each is added to Comfy's Shared Models once, after the folders already listed, and
#   the list is never reordered, so "Make primary" in Comfy sticks. With an empty list, Comfy's local
#   default (~/ComfyUI-Shared/models) is listed first, so downloads stay local. It waits (skips, and
#   says so unless --quiet) until a folder exists and until settings.json exists. Checking that a
#   folder exists can mount an automounted share, so the check gives up after 5 s and a down server
#   can't stall apply.
# Both wait while Comfy is running, since Comfy rewrites the file. Nothing is moved or deleted.
# Test seams: DOTFILES_COMFY_SETTINGS, DOTFILES_COMFY_INSTALLATIONS, DOTFILES_COMFY_APP (its command).

set -uo pipefail

settings="${DOTFILES_COMFY_SETTINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/comfyui-desktop-2/settings.json}"
installs="${DOTFILES_COMFY_INSTALLATIONS:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui-desktop-2/installations.json}"
usage() { echo "usage: comfyui-settings.sh [--quiet] [--root <folder>] [<models folder>...]" >&2; exit 2; }
quiet="" root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) quiet=1; shift ;;
    --root) [ "$#" -ge 2 ] && [ -n "$2" ] || usage; root="$2"; shift 2 ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ -n "$root" ] || [ "$#" -gt 0 ] || usage
say() { [ -n "$quiet" ] || echo "comfyui-settings: $*"; }
warn() { echo "comfyui-settings: $*" >&2; }
# comfyui-desktop-2, as the kernel's 15-character process name
running() { pgrep -x comfyui-desktop >/dev/null 2>&1; }
need_jq() { command -v jq >/dev/null 2>&1 || { warn "jq not found; Comfy Desktop's folders not set"; return 1; }; }
expected() { # settings.json is the object Comfy writes, with modelsDirs a list if it is there
  jq -e 'type == "object" and ((.modelsDirs // []) | type == "array")' "$settings" >/dev/null 2>&1 ||
    { warn "$settings is not the settings file expected; left alone"; return 1; }
}
merge() { # <jq args>... : apply a jq filter to settings.json (or {} when there is none yet) in place,
  # keeping its mode. Returns 3 when nothing would change, and then writes nothing.
  local tmp="$settings.dotfiles.tmp" mode=""
  if [ -f "$settings" ]; then
    mode="$(stat -c %a "$settings" 2>/dev/null || stat -f %Lp "$settings")"
    jq "$@" < "$settings" > "$tmp" || { rm -f "$tmp"; warn "could not update $settings"; return 1; }
    if [ "$(jq -cS . "$settings")" = "$(jq -cS . "$tmp")" ]; then rm -f "$tmp"; return 3; fi
  elif ! { mkdir -p "$(dirname "$settings")" && echo '{}' | jq "$@" > "$tmp"; }; then
    rm -f "$tmp"; warn "could not write $settings"; return 1
  fi
  if { [ -n "$mode" ] && ! chmod "$mode" "$tmp"; } || ! mv "$tmp" "$settings"; then
    rm -f "$tmp"; warn "could not update $settings"; return 1
  fi
}

set_folders() { # --root: Comfy's folder keys under $root, before its first run
  command -v "${DOTFILES_COMFY_APP:-comfyui-desktop-2}" >/dev/null 2>&1 || return 0
  case "$root" in /*) ;; *) warn "'$root' is not an absolute path; folders not set"; return 1 ;; esac
  root="${root%/}"
  need_jq || return 1
  if [ -f "$settings" ]; then
    expected || return 1
    jq -e '.firstUseCompleted == true' "$settings" >/dev/null 2>&1 && return 0
  fi
  if [ -e "$installs" ] && ! jq -e 'type == "array" and length == 0' "$installs" >/dev/null 2>&1; then
    return 0
  fi
  if running; then
    echo "comfyui-settings: Comfy Desktop is running and rewrites its settings; quit it, then run chezmoi apply"
    return 0
  fi
  local d
  for d in installs models input output cache; do
    mkdir -p "$root/$d" || { warn "could not create $root/$d; folders not set"; return 1; }
  done
  # shellcheck disable=SC2016 # a jq filter: $r, $shared and $old are jq's
  merge --arg r "$root" --arg shared "$HOME/ComfyUI-Shared/models" '
      (.installDir | if type == "string" and endswith("/installs") then [.[:-9] + "/models"] else [] end) as $old
      | .installDir = ($r + "/installs") | .inputDir = ($r + "/input") | .outputDir = ($r + "/output")
      | .cacheDir = ($r + "/cache")
      | .modelsDirs = [$r + "/models"] + ((.modelsDirs // []) - [$r + "/models", $shared] - $old)
    '
  case $? in
    0) echo "comfyui-settings: Comfy Desktop's folders are now under $root (installs, models, input, output, cache) for its first run" ;;
    3) ;;
    *) return 1 ;;
  esac
}

add_models() { # <folder>... : each folder in Comfy's Shared Models, once, after the folders listed
  if [ ! -f "$settings" ]; then
    say "no $settings yet; open Comfy Desktop once, finish its first-run setup and quit it, then run chezmoi apply"
    return 0
  fi
  need_jq && expected || return 1
  if command -v timeout >/dev/null 2>&1; then found() { timeout -k 2 5 test -d "$1"; }; else found() { test -d "$1"; }; fi
  local dir add=()
  for dir in "$@"; do
    case "$dir" in /*) ;; *) warn "'$dir' is not an absolute path; skipped"; continue ;; esac
    jq -e --arg m "$dir" '(.modelsDirs // []) | index($m)' "$settings" >/dev/null && continue
    # Until a share is installed there is no mount point, and Comfy would get a folder that isn't there.
    if ! found "$dir"; then
      say "no $dir yet (or its share did not answer in 5 s); it is added at the first apply after it exists"
      continue
    fi
    add+=("$dir")
  done
  [ "${#add[@]}" -gt 0 ] || return 0
  if running; then
    echo "comfyui-settings: Comfy Desktop is running and rewrites its settings; quit it, then run chezmoi apply"
    return 0
  fi
  # shellcheck disable=SC2016 # a jq filter: $d, $b and $ARGS are jq's
  merge --arg local "$HOME/ComfyUI-Shared/models" --args '
      (.modelsDirs // []) as $d
      | (if ($d | length) == 0 then [$local] else $d end) as $b
      | .modelsDirs = $b + ($ARGS.positional - $b)
    ' "${add[@]}" || return 1
  echo "comfyui-settings: Comfy Desktop now also reads models from ${add[*]}; downloads still go to its first folder (Settings > Shared Models > Make primary changes that)"
}

rc=0
if [ -n "$root" ]; then set_folders || rc=1; fi
if [ "$#" -gt 0 ]; then add_models "$@" || rc=1; fi
exit "$rc"
