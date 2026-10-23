#!/usr/bin/env bats
# The phrase dry run must never call `say` (it can hang on headless CI runners).

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_claude/hooks/executable_speak-alert.sh"

@test "phrase dry run never calls say" {
  export HOME="$(mktemp -d)"
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\necho called > "%s/say-called"\n' "$HOME" > "$HOME/bin/say"
  chmod +x "$HOME/bin/say"
  run bash -c "echo '{\"cwd\":\"/x/y\"}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=1 '$SCRIPT' stop"
  [ "$output" = "y finished" ]
  [ ! -e "$HOME/say-called" ]
  rm -rf "$HOME"
}
