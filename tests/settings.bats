#!/usr/bin/env bats
# The settings file, schema v1 (docs/settings.md): the dotfiles-settings partial that validates and
# normalizes it, the fixtures in tests/fixtures/settings, and the dotfiles-settings command. Each
# bad-*.toml fixture's first line is "# expect: <the message it must fail with>". chezmoi runs with a
# throwaway HOME and config, so the real settings file is never read.

REPO="$BATS_TEST_DIRNAME/.."
FIXTURES="$BATS_TEST_DIRNAME/fixtures/settings"
CMD="$REPO/home/dot_local/bin/executable_dotfiles-settings"

setup() {
  export HOME="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-settings-XXXXXXXX")"
  export XDG_CONFIG_HOME="$HOME/.config"
  REAL_CHEZMOI="$(command -v chezmoi)"
  mkdir -p "$HOME/bin"
  # dotfiles-settings calls chezmoi; this one reads the repo as its source, with a throwaway config and state.
  printf '#!/bin/sh\nexec "%s" --source "%s" --config "%s/none.toml" --persistent-state "%s/state.boltdb" "$@"\n' \
    "$REAL_CHEZMOI" "$REPO" "$HOME" "$HOME" > "$HOME/bin/chezmoi"
  chmod +x "$HOME/bin/chezmoi"
  export PATH="$HOME/bin:$PATH"
}

teardown() { case "${HOME:-}" in */dotfiles-settings-*) rm -rf "$HOME" ;; esac; }

settings() { # [file] : the partial's JSON for <file>, or for the default path
  local data='{}'
  [ -z "${1:-}" ] || data="{\"dotfilesSettingsFile\":\"$1\"}"
  chezmoi execute-template --override-data "$data" '{{ includeTemplate "dotfiles-settings" . }}'
}

@test "no settings file: every feature is off" {
  run settings
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.present, .nfsShares, .cache, .comfyui.modelsDirs]' <<<"$output")" = '[false,[],false,[]]' ]
  [ "$(jq -r .file <<<"$output")" = "$HOME/.config/dotfiles/settings.toml" ]
}

@test "the default path follows XDG_CONFIG_HOME, and ~/.config when it is unset or relative; check names it" {
  XDG_CONFIG_HOME="$HOME/xdg" run "$CMD" path
  [ "$output" = "$HOME/xdg/dotfiles/settings.toml" ]
  XDG_CONFIG_HOME="$HOME/xdg" run "$CMD" check
  [ "$output" = "dotfiles-settings: no settings file at $HOME/xdg/dotfiles/settings.toml; every feature is off" ]
  for x in unset "" relative/dir; do
    if [ "$x" = unset ]; then run env -u XDG_CONFIG_HOME "$CMD" path; else XDG_CONFIG_HOME="$x" run "$CMD" path; fi
    [ "$output" = "$HOME/.config/dotfiles/settings.toml" ] || { echo "XDG_CONFIG_HOME=$x: $output"; false; }
    if [ "$x" = unset ]; then run env -u XDG_CONFIG_HOME "$CMD" check; else XDG_CONFIG_HOME="$x" run "$CMD" check; fi
    [ "$output" = "dotfiles-settings: no settings file at $HOME/.config/dotfiles/settings.toml; every feature is off" ]
  done
  mkdir -p "$HOME/xdg/dotfiles"
  cp "$FIXTURES/minimal.toml" "$HOME/xdg/dotfiles/settings.toml"
  XDG_CONFIG_HOME="$HOME/xdg" run "$CMD" check
  [ "$output" = "dotfiles-settings: $HOME/xdg/dotfiles/settings.toml is valid (schema v1): 0 NFS share(s), 0 Comfy models folder(s)" ]
}

@test "the full example is valid and fills in the defaults" {
  run settings "$FIXTURES/ok.toml"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.nfsShares[0]' <<<"$output")" = '{"cache":true,"export":"/export/models","mode":"ro","mountPoint":"/var/mnt/nas/models","server":"nas.example.lan"}' ]
  # mode and cache default to rw and false
  [ "$(jq -c '.nfsShares[1]' <<<"$output")" = '{"cache":false,"export":"/export/media","mode":"rw","mountPoint":"/var/mnt/nas/media","server":"192.0.2.10"}' ]
  [ "$(jq -c '.fscache' <<<"$output")" = '{"bcull":25,"brun":30,"bstop":20,"dir":"/var/cache/fscache","fcull":10,"frun":15,"fstop":5}' ]
  [ "$(jq -c '.comfyui.modelsDirs' <<<"$output")" = "[\"/var/mnt/nas/models\",\"$HOME/models-extra\"]" ]
  [ "$(jq .cache <<<"$output")" = true ]
}

@test "the fscache defaults are 30/25/20 percent of free space and of free files on the cache's filesystem" {
  run settings "$FIXTURES/minimal.toml"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.present, .fscache]' <<<"$output")" = '[true,{"bcull":25,"brun":30,"bstop":20,"dir":"/var/cache/fscache","fcull":25,"frun":30,"fstop":20}]' ]
}

@test "each bad fixture fails with its own message" {
  local f want n=0
  for f in "$FIXTURES"/bad-*.toml; do
    want="$(sed -n '1s/^# expect: //p' "$f")"
    [ -n "$want" ] || { echo "$f has no expect line"; false; }
    run settings "$f"
    [ "$status" -ne 0 ] || { echo "$f: passed validation"; false; }
    [[ "$output" == *"$want"* ]] || { echo "$f: want: $want"; echo "got: $output"; false; }
    n=$((n + 1))
  done
  [ "$n" -ge 15 ]
}

@test "the example in docs/settings.md is valid and uses every v1 key" {
  sed -n '/^```toml$/,/^```$/p' "$REPO/docs/settings.md" | sed '1d;$d' > "$HOME/doc.toml"
  run settings "$HOME/doc.toml"
  [ "$status" -eq 0 ]
  doc_keys="$(grep -oE '^[a-zA-Z]+ *=' "$HOME/doc.toml" | tr -d ' =' | LC_ALL=C sort -u | paste -sd ' ' -)"
  [ "$doc_keys" = "bcull brun bstop cache dir export fcull frun fstop mode modelsDirs mountPoint schemaVersion server" ]
}

@test "dotfiles-settings check prints one line: what is on, nothing set, or the one problem" {
  run "$CMD" check
  [ "$status" -eq 0 ]
  [ "$output" = "dotfiles-settings: no settings file at $HOME/.config/dotfiles/settings.toml; every feature is off" ]
  run "$CMD" check "$FIXTURES/ok.toml"
  [ "$status" -eq 0 ]
  [ "$output" = "dotfiles-settings: $FIXTURES/ok.toml is valid (schema v1): 2 NFS share(s), FS-Cache on, 2 Comfy models folder(s)" ]
  run "$CMD" check "$FIXTURES/bad-mode.toml"
  [ "$status" -eq 1 ]
  [ "$output" = "dotfiles settings ($FIXTURES/bad-mode.toml): nfsShares[0].mode must be rw or ro, not rx" ]
  run "$CMD" check "$FIXTURES/bad-syntax.toml"
  [ "$status" -eq 1 ]
  [[ "$output" == "dotfiles settings ($FIXTURES/bad-syntax.toml): toml: line 4"* ]] || false
  run "$CMD" check "$HOME/missing.toml"
  [ "$status" -eq 2 ]
}

@test "dotfiles-settings reads the default file, and show prints what apply reads" {
  mkdir -p "$HOME/.config/dotfiles"
  cp "$FIXTURES/bad-version.toml" "$HOME/.config/dotfiles/settings.toml"
  run "$CMD"
  [ "$status" -eq 1 ]
  [ "$output" = "dotfiles settings ($HOME/.config/dotfiles/settings.toml): schemaVersion 2 is not supported by this dotfiles version (it reads 1)" ]
  cp "$FIXTURES/ok.toml" "$HOME/.config/dotfiles/settings.toml"
  run "$CMD" show
  [ "$status" -eq 0 ]
  [ "$(jq -r '.nfsShares[0].server' <<<"$output")" = nas.example.lan ]
}
