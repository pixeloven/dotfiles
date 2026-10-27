#!/usr/bin/env bats
# voice: mute, unmute, toggle and status for spoken alerts. Nothing here plays audio.

REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="$REPO/home/dot_local/bin/executable_voice"
HOOK="$REPO/home/dot_claude/hooks/executable_speak-alert.sh"

setup() {
  export HOME="$(mktemp -d)"
  unset FM_TASK_ID CLAUDE_CODE_ENTRYPOINT SPEAK_ALERT_ENGINE SPEAK_ALERT_DRY_RUN VOICE_CLOUD_KEY VOICE_CLOUD_OP_REF
  # Installed the way chezmoi lays them out.
  mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$HOME/bin"
  ln -s "$HOOK" "$HOME/.claude/hooks/speak-alert.sh"
  ln -s "$REPO/home/dot_local/bin/executable_voice-cloud" "$HOME/.local/bin/voice-cloud"
  # A Linux machine with no Kokoro model, no key stores, and a notify-send that logs.
  printf '#!/bin/sh\necho Linux\n' > "$HOME/bin/uname"
  for s in security secret-tool op; do printf '#!/bin/sh\nexit 1\n' > "$HOME/bin/$s"; done
  printf '#!/bin/sh\necho "$*" >> "%s/notes"\n' "$HOME" > "$HOME/bin/notify-send"
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
}

teardown() { rm -rf "$HOME"; }

@test "mute and unmute manage the mute file" {
  run "$SCRIPT" mute
  [ "$status" -eq 0 ]
  [ -e "$HOME/.config/speak-alert/muted" ]
  [[ "$output" == *muted* ]] || false
  run "$SCRIPT" unmute
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/speak-alert/muted" ]
  run "$SCRIPT" unmute
  [ "$status" -eq 0 ]
}

@test "toggle flips mute and shows a desktop notification, for a key binding" {
  run "$SCRIPT" toggle
  [ "$output" = "voice: muted" ]
  [ -e "$HOME/.config/speak-alert/muted" ]
  run "$SCRIPT" toggle
  [ "$output" = "voice: unmuted" ]
  [ ! -e "$HOME/.config/speak-alert/muted" ]
  [ "$(sed -n 1p "$HOME/notes")" = "-a voice -t 2000 Voice muted" ]
  [ "$(sed -n 2p "$HOME/notes")" = "-a voice -t 2000 Voice unmuted" ]
}

@test "toggle needs nothing but a shell: runs with only coreutils on PATH" {
  mkdir -p "$HOME/min"
  for c in sh mkdir rm touch; do ln -s "$(command -v "$c")" "$HOME/min/$c"; done
  run env PATH="$HOME/min" "$(command -v bash)" "$SCRIPT" toggle
  [ "$status" -eq 0 ]
  [ -e "$HOME/.config/speak-alert/muted" ]
}

@test "muting silences alerts and summaries for Claude and Codex" {
  "$SCRIPT" mute
  touch "$HOME/.config/speak-alert/summaries"
  for m in stop notify summary codex-stop codex-permission codex-summary; do
    run bash -c "echo '{\"last_assistant_message\":\"Done.\"}' | SPEAK_ALERT_DRY_RUN=1 '$HOOK' $m"
    [ -z "$output" ]
  done
  [ "$(grep -c 'silent: muted$' "$HOME/.local/state/speak-alert/events.log")" -eq 6 ]
  "$SCRIPT" unmute
  run bash -c "echo '{}' | SPEAK_ALERT_DRY_RUN=1 '$HOOK' notify"
  [ "$output" = "Claude needs you." ]
}

@test "status: engine, summaries, mute and key source" {
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"engine: kokoro (not set up"* ]] || false
  [[ "$output" == *"summaries: off"* ]] || false
  [[ "$output" == *"muted: no"* ]] || false
  [[ "$output" == *"cloud key: none"* ]] || false
  "$SCRIPT" mute
  touch "$HOME/.config/speak-alert/summaries"
  run "$SCRIPT" status
  [[ "$output" == *"engine: kokoro (not set up"* ]] || false
  [[ "$output" == *"summaries: on"* ]] || false
  [[ "$output" == *"muted: yes"* ]] || false
}

@test "status says when the engine is ready" {
  printf '#!/bin/sh\necho Darwin\n' > "$HOME/bin/uname"
  printf '#!/bin/sh\n' > "$HOME/bin/say"
  chmod +x "$HOME/bin/say"
  run "$SCRIPT" status
  [[ "$output" == *"engine: say (ready)"* ]] || false
}

@test "status names where the key comes from, never the key" {
  VOICE_CLOUD_KEY=sk-secret-123 run "$SCRIPT" status
  [[ "$output" == *"cloud key: env"* ]] || false
  [[ "$output" != *sk-secret-123* ]] || false
}

@test "status works for fleet workers and while muted (it speaks nothing)" {
  "$SCRIPT" mute
  FM_TASK_ID=t1 run "$SCRIPT" status
  [[ "$output" == *"engine: kokoro"* ]] || false
  [ ! -e "$HOME/.local/state/speak-alert/events.log" ]
}

@test "rejects unknown commands" {
  run "$SCRIPT" bogus
  [ "$status" -eq 2 ]
}
