#!/usr/bin/env bats
# lib/comfyui-settings.sh: Comfy Desktop's folders under comfyui.root before its first run, and the
# comfyui.modelsDirs folders in its Shared Models. It edits a scratch settings.json in a throwaway HOME;
# a stub pgrep stands in for a running Comfy Desktop, and a stub comfyui-desktop-2 for an installed one.

REPO="$BATS_TEST_DIRNAME/.."
CMD="$REPO/lib/comfyui-settings.sh"

setup() {
  export HOME="$(mktemp -d "${TMPDIR:-/tmp}/comfyui-settings-XXXXXXXX")"
  export DOTFILES_COMFY_SETTINGS="$HOME/comfy/settings.json"
  export DOTFILES_COMFY_INSTALLATIONS="$HOME/comfy/installations.json"
  export DOTFILES_COMFY_APP="$HOME/bin/comfyui-desktop-2"
  unset COMFY_RUNNING
  mkdir -p "$HOME/bin" "$HOME/comfy" "$HOME/nas/models" "$HOME/more"
  printf '#!/bin/sh\n[ -n "${COMFY_RUNNING:-}" ]\n' > "$HOME/bin/pgrep"
  chmod +x "$HOME/bin/pgrep"
  export PATH="$HOME/bin:$PATH"
  M="$HOME/nas/models"
  R="$HOME/ComfyUI"
}

installed() { printf '#!/bin/sh\nexit 0\n' > "$HOME/bin/comfyui-desktop-2"; chmod +x "$HOME/bin/comfyui-desktop-2"; }
folders() { jq -c '[.installDir, .modelsDirs, .inputDir, .outputDir, .cacheDir]' "$DOTFILES_COMFY_SETTINGS"; }
under_root() { jq -nc --arg r "$R" '[$r + "/installs", [$r + "/models"], $r + "/input", $r + "/output", $r + "/cache"]'; }

teardown() { case "${HOME:-}" in */comfyui-settings-*) rm -rf "$HOME" ;; esac; }

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

@test "a folder whose share does not answer is skipped after 5 s instead of stalling apply" {
  command -v timeout >/dev/null 2>&1 || skip "no timeout(1) here, so the check is not bounded"
  comfy_settings '{"modelsDirs":["/a"]}'
  printf '#!/bin/sh\nsleep 60\n' > "$HOME/bin/test"
  chmod +x "$HOME/bin/test"
  start=$SECONDS
  run "$CMD" "$M"
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -lt 20 ]
  [[ "$output" == *"no $M yet (or its share did not answer in 5 s)"* ]] || false
  [ "$(dirs)" = '["/a"]' ]
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

@test "before the first run, --root writes a settings.json with only the folder keys and creates each folder" {
  installed
  rm -rf "$HOME/comfy"
  run "$CMD" --quiet --root "$R/"
  [ "$status" -eq 0 ]
  [[ "$output" == *"folders are now under $R (installs, models, input, output, cache)"* ]] || false
  [ "$(folders)" = "$(under_root)" ]
  [ "$(jq -c 'keys' "$DOTFILES_COMFY_SETTINGS")" = '["cacheDir","inputDir","installDir","modelsDirs","outputDir"]' ]
  for d in installs models input output cache; do [ -d "$R/$d" ]; done
  [ ! -e "$HOME/ComfyUI-Shared" ]
}

@test "--root merges only the folder keys over Comfy's defaults, keeps the rest, and is idempotent" {
  installed
  comfy_settings "{\"telemetryEnabled\":false,\"dashboardWorkspaceId\":\"ws-1\",\"installDir\":\"$HOME/ComfyUI-Installs\",\"modelsDirs\":[\"$HOME/ComfyUI-Shared/models\",\"/extra\"],\"inputDir\":\"$HOME/ComfyUI-Shared/input\",\"outputDir\":\"$HOME/ComfyUI-Shared/output\",\"cacheDir\":\"$HOME/.cache/comfyui-desktop-2/download-cache\",\"homeTourAudience\":\"new\"}"
  chmod 640 "$DOTFILES_COMFY_SETTINGS"
  run "$CMD" --root "$R"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.installDir, .modelsDirs]' "$DOTFILES_COMFY_SETTINGS")" = "[\"$R/installs\",[\"$R/models\",\"/extra\"]]" ]
  [ "$(jq -c '[.telemetryEnabled, .dashboardWorkspaceId, .homeTourAudience]' "$DOTFILES_COMFY_SETTINGS")" = '[false,"ws-1","new"]' ]
  [ "$(stat -c %a "$DOTFILES_COMFY_SETTINGS" 2>/dev/null || stat -f %Lp "$DOTFILES_COMFY_SETTINGS")" = 640 ]
  before="$(cat "$DOTFILES_COMFY_SETTINGS")"
  run "$CMD" --root "$R"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$DOTFILES_COMFY_SETTINGS")" = "$before" ]
}

@test "--root then models folders: each folder goes after the root's models folder, the primary" {
  installed
  rm -f "$DOTFILES_COMFY_SETTINGS"
  run "$CMD" --quiet --root "$R" "$M"
  [ "$status" -eq 0 ]
  [ "$(dirs)" = "[\"$R/models\",\"$M\"]" ]
  run "$CMD" --quiet --root "$R" "$M"
  [ -z "$output" ]
  [ "$(dirs)" = "[\"$R/models\",\"$M\"]" ]
}

@test "after Comfy's first run, or with an install recorded, --root leaves its folders alone" {
  installed
  comfy_settings '{"firstUseCompleted":true,"installDir":"/i","modelsDirs":["/m"]}'
  run "$CMD" --root "$R"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -c '[.installDir, .modelsDirs]' "$DOTFILES_COMFY_SETTINGS")" = '["/i",["/m"]]' ]
  comfy_settings '{"installDir":"/i","modelsDirs":["/m"]}'
  echo '[{"id":"inst-1"}]' > "$DOTFILES_COMFY_INSTALLATIONS"
  run "$CMD" --root "$R"
  [ -z "$output" ]
  [ "$(jq -c '[.installDir, .modelsDirs]' "$DOTFILES_COMFY_SETTINGS")" = '["/i",["/m"]]' ]
  [ ! -e "$R" ]
  echo '[]' > "$DOTFILES_COMFY_INSTALLATIONS"
  run "$CMD" --root "$R"
  [ "$(jq -r .installDir "$DOTFILES_COMFY_SETTINGS")" = "$R/installs" ]
}

@test "--root does nothing without Comfy Desktop, waits while it runs, and leaves a file it doesn't expect alone" {
  rm -f "$DOTFILES_COMFY_SETTINGS"
  run "$CMD" --root "$R"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$DOTFILES_COMFY_SETTINGS" ]
  [ ! -e "$R" ]
  installed
  COMFY_RUNNING=1 run "$CMD" --root "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comfy Desktop is running"* ]] || false
  [ ! -e "$DOTFILES_COMFY_SETTINGS" ]
  comfy_settings '["not", "an object"]'
  run "$CMD" --root "$R"
  [ "$status" -eq 1 ]
  [ "$(cat "$DOTFILES_COMFY_SETTINGS")" = '["not", "an object"]' ]
  run "$CMD" --root relative/dir
  [ "$status" -eq 1 ]
}

@test "--root changed before the first run drops the models folder an earlier root wrote" {
  installed
  rm -f "$DOTFILES_COMFY_SETTINGS"
  run "$CMD" --quiet --root "$R" "$M"
  [ "$status" -eq 0 ]
  [ "$(dirs)" = "[\"$R/models\",\"$M\"]" ]
  N="$HOME/data/ComfyUI"
  run "$CMD" --quiet --root "$N" "$M"
  [ "$status" -eq 0 ]
  [ "$(folders)" = "$(jq -nc --arg n "$N" --arg m "$M" '[$n + "/installs", [$n + "/models", $m], $n + "/input", $n + "/output", $n + "/cache"]')" ]
}
