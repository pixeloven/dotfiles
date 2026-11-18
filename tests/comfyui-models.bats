#!/usr/bin/env bats
# lib/comfyui-models.sh: the comfyui.modelsDirs folders in Comfy Desktop's Shared Models. It edits a
# scratch settings.json in a throwaway HOME; a stub pgrep stands in for a running Comfy Desktop.

REPO="$BATS_TEST_DIRNAME/.."
CMD="$REPO/lib/comfyui-models.sh"

setup() {
  export HOME="$(mktemp -d "${TMPDIR:-/tmp}/comfyui-models-XXXXXXXX")"
  export DOTFILES_COMFY_SETTINGS="$HOME/comfy/settings.json"
  unset COMFY_RUNNING
  mkdir -p "$HOME/bin" "$HOME/comfy" "$HOME/nas/models" "$HOME/more"
  printf '#!/bin/sh\n[ -n "${COMFY_RUNNING:-}" ]\n' > "$HOME/bin/pgrep"
  chmod +x "$HOME/bin/pgrep"
  export PATH="$HOME/bin:$PATH"
  M="$HOME/nas/models"
}

teardown() { case "${HOME:-}" in */comfyui-models-*) rm -rf "$HOME" ;; esac; }

comfy_settings() { printf '%s\n' "$1" > "$DOTFILES_COMFY_SETTINGS"; }
dirs() { jq -c .modelsDirs "$DOTFILES_COMFY_SETTINGS"; }

@test "adds each folder after the folders already listed, once, keeping the rest of the file" {
  comfy_settings '{"cacheDir":"/c","modelsDirs":["/home/u/ComfyUI-Shared/models","/extra"],"installDir":"/i"}'
  run "$CMD" "$M" "$HOME/more"
  [ "$status" -eq 0 ]
  [[ "$output" == *"also reads models from $M $HOME/more"* ]] || false
  [ "$(dirs)" = "[\"/home/u/ComfyUI-Shared/models\",\"/extra\",\"$M\",\"$HOME/more\"]" ]
  [ "$(jq -c 'del(.modelsDirs)' "$DOTFILES_COMFY_SETTINGS")" = '{"cacheDir":"/c","installDir":"/i"}' ]
  run "$CMD" --quiet "$M" "$HOME/more"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq '.modelsDirs | length' "$DOTFILES_COMFY_SETTINGS")" -eq 4 ]
}

@test "keeps Comfy's local default first when the list is missing or empty" {
  for settings in '{"onAppClose":"quit"}' '{"modelsDirs":[]}'; do
    comfy_settings "$settings"
    run "$CMD" "$M"
    [ "$status" -eq 0 ]
    [ "$(dirs)" = "[\"$HOME/ComfyUI-Shared/models\",\"$M\"]" ]
  done
}

@test "never reorders a folder already listed, so Make primary sticks" {
  comfy_settings "{\"modelsDirs\":[\"$M\",\"/a\"]}"
  run "$CMD" "$M"
  [ "$status" -eq 0 ]
  [ "$(dirs)" = "[\"$M\",\"/a\"]" ]
}

@test "waits for each folder, for Comfy's first run and for it to quit, and leaves a file it doesn't expect alone" {
  comfy_settings '{"modelsDirs":["/a"]}'
  run "$CMD" "$HOME/not-mounted-yet" "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no $HOME/not-mounted-yet yet"* ]] || false
  [ "$(dirs)" = "[\"/a\",\"$M\"]" ]
  rm "$DOTFILES_COMFY_SETTINGS"
  run "$CMD" "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"open Comfy Desktop once"* ]] || false
  run "$CMD" --quiet "$M"
  [ -z "$output" ]
  comfy_settings '{"modelsDirs":["/a"]}'
  COMFY_RUNNING=1 run "$CMD" "$M"
  [[ "$output" == *"Comfy Desktop is running"* ]] || false
  [ "$(dirs)" = '["/a"]' ]
  comfy_settings 'not json'
  run "$CMD" "$M"
  [ "$status" -eq 1 ]
  [ "$(cat "$DOTFILES_COMFY_SETTINGS")" = 'not json' ]
}
