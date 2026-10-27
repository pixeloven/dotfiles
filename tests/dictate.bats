#!/usr/bin/env bats
# dictate: the push-to-talk toggle. The recorder, whisper-cli, herdr, the clipboard and
# notifications are all stubs, so nothing records or plays audio.

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_local/bin/executable_dictate"

setup() {
  export HOME="$(mktemp -d)"
  export XDG_RUNTIME_DIR="$HOME/run"
  unset DICTATE_ENGINE DICTATE_MODEL DICTATE_PROMPT VOICE_CLOUD_URL
  mkdir -p "$HOME/bin" "$HOME/.local/share/whisper" "$XDG_RUNTIME_DIR"
  : > "$HOME/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin"
  # parecord: note the args, write a WAV, run until stopped.
  cat > "$HOME/bin/parecord" <<STUB
#!/bin/sh
printf '%s\n' "\$*" > "$HOME/rec-args"
for a; do out="\$a"; done
printf 'RIFF' > "\$out"
trap 'echo stopped > "$HOME/rec-stopped"; exit 0' TERM INT
while :; do sleep 0.1; done
STUB
  # whisper-cli prints what it heard (TRANSCRIPT), padded the way whisper.cpp pads it.
  cat > "$HOME/bin/whisper-cli" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$HOME/stt-args"
printf ' %s\n' "\${TRANSCRIPT-run the tests}"
STUB
  cat > "$HOME/bin/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "pane list") cat "$HOME/panes.json" 2>/dev/null || exit 1 ;;
  "pane send-text") printf '%s|%s\n' "\$3" "\$4" >> "$HOME/sent" ;;
esac
STUB
  printf '#!/bin/sh\ncat > "%s/clipboard"\n' "$HOME" > "$HOME/bin/wl-copy"
  printf '#!/bin/sh\necho "$*" >> "%s/notes"\n' "$HOME" > "$HOME/bin/notify-send"
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
  echo '{"result":{"panes":[{"pane_id":"w1:p1","focused":false},{"pane_id":"w2:p3","focused":true}]}}' > "$HOME/panes.json"
}

teardown() {
  [ -f "$XDG_RUNTIME_DIR/dictate/recorder.pid" ] && kill "$(cat "$XDG_RUNTIME_DIR/dictate/recorder.pid")" 2>/dev/null
  rm -rf "$HOME"
}

@test "first press starts recording 16 kHz mono, second press types into the focused herdr pane" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$XDG_RUNTIME_DIR/dictate/recorder.pid" ]
  grep -q -- '--rate=16000' "$HOME/rec-args"
  grep -q -- '--channels=1' "$HOME/rec-args"
  grep -q 'Listening' "$HOME/notes"
  [ ! -e "$HOME/sent" ]
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$HOME/rec-stopped" ]
  [ "$(cat "$HOME/sent")" = "w2:p3|run the tests" ]
  [ ! -e "$XDG_RUNTIME_DIR/dictate/recorder.pid" ]
  [ ! -e "$HOME/clipboard" ]
}

@test "whisper gets the model, English and a vocabulary prompt" {
  "$SCRIPT"
  "$SCRIPT"
  grep -qx "$HOME/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin" "$HOME/stt-args"
  grep -qx -- '--prompt' "$HOME/stt-args"
  grep -q 'herdr' "$HOME/stt-args"
  grep -qx 'en' "$HOME/stt-args"
}

@test "DICTATE_PROMPT and DICTATE_MODEL override the defaults" {
  : > "$HOME/small.bin"
  DICTATE_MODEL="$HOME/small.bin" DICTATE_PROMPT="pixeloven, Bazzite" "$SCRIPT"
  DICTATE_MODEL="$HOME/small.bin" DICTATE_PROMPT="pixeloven, Bazzite" "$SCRIPT"
  grep -qx "$HOME/small.bin" "$HOME/stt-args"
  grep -qx 'pixeloven, Bazzite' "$HOME/stt-args"
}

@test "without herdr running, the text goes to the clipboard with a notification" {
  rm "$HOME/panes.json"
  "$SCRIPT"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/clipboard")" = "run the tests" ]
  grep -q 'clipboard' "$HOME/notes"
  [ ! -e "$HOME/sent" ]
}

@test "with no focused pane, the text goes to the clipboard" {
  echo '{"result":{"panes":[{"pane_id":"w1:p1","focused":false}]}}' > "$HOME/panes.json"
  "$SCRIPT"
  "$SCRIPT"
  [ "$(cat "$HOME/clipboard")" = "run the tests" ]
}

@test "whisper's blank-audio marker means nothing is typed" {
  "$SCRIPT"
  TRANSCRIPT="[BLANK_AUDIO]" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/sent" ]
  [ ! -e "$HOME/clipboard" ]
  grep -q 'Heard nothing' "$HOME/notes"
}

@test "no model: says so and records nothing" {
  rm "$HOME/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/rec-args" ]
  grep -q 'RUNBOOK' "$HOME/notes"
}

@test "--cancel stops the recording and types nothing" {
  "$SCRIPT"
  run "$SCRIPT" --cancel
  [ "$status" -eq 0 ]
  [ -e "$HOME/rec-stopped" ]
  [ ! -e "$HOME/sent" ]
  [ ! -e "$HOME/stt-args" ]
  [ ! -e "$XDG_RUNTIME_DIR/dictate/recorder.pid" ]
}

@test "a stale recorder pid starts a new recording" {
  mkdir -p "$XDG_RUNTIME_DIR/dictate"
  echo 999999 > "$XDG_RUNTIME_DIR/dictate/recorder.pid"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'Listening' "$HOME/notes"
  [ ! -e "$HOME/stt-args" ]
}

@test "DICTATE_ENGINE=openai-compatible transcribes through voice-cloud" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/cloud-args"\necho "cloud words"\n' "$HOME" > "$HOME/.local/bin/voice-cloud"
  chmod +x "$HOME/.local/bin/voice-cloud"
  export DICTATE_ENGINE=openai-compatible VOICE_CLOUD_URL=http://localhost:8000/v1
  "$SCRIPT"
  "$SCRIPT"
  [ "$(cat "$HOME/sent")" = "w2:p3|cloud words" ]
  grep -qx stt "$HOME/cloud-args"
  grep -qx -- '--prompt' "$HOME/cloud-args"
  [ ! -e "$HOME/stt-args" ]
}

@test "openai-compatible without VOICE_CLOUD_URL records nothing" {
  DICTATE_ENGINE=openai-compatible run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/rec-args" ]
}

@test "rejects unknown options" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "a recorder that exits at once says so and leaves no recording" {
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/rec-args"\nexit 1\n' "$HOME" > "$HOME/bin/parecord"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -e "$HOME/rec-args" ]
  [ ! -e "$XDG_RUNTIME_DIR/dictate/recorder.pid" ]
  grep -q 'could not start recording' "$HOME/notes"
  ! grep -q 'Listening' "$HOME/notes"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/stt-args" ]
}
