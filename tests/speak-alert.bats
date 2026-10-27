#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="$REPO/home/dot_claude/hooks/executable_speak-alert.sh"

setup() {
  export HOME="$(mktemp -d)"
  export SPEAK_ALERT_DRY_RUN=1
  unset FM_TASK_ID CLAUDE_CODE_ENTRYPOINT
}

teardown() { rm -rf "$HOME"; }

@test "calm done line on stop" {
  run bash -c "echo '{\"cwd\":\"/x/operator\"}' | '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ "$output" = "All done. Ready for you." ]
}

@test "speaks Claude's own reason on notify" {
  run bash -c "echo '{\"message\":\"Claude needs your permission to use Bash\"}' | '$SCRIPT' notify"
  [ "$output" = "Claude needs your permission to use Bash." ]
}

@test "generic needs-you line when notify has no message" {
  run bash -c "echo '{}' | '$SCRIPT' notify"
  [ "$output" = "Claude needs you." ]
}

@test "speak-alert is silent when FM_TASK_ID is set" {
  run bash -c "echo '{\"cwd\":\"/x/operator\"}' | FM_TASK_ID=t1 '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent for headless claude -p runs" {
  run bash -c "echo '{}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "speaks in an interactive session" {
  run bash -c "echo '{}' | CLAUDE_CODE_ENTRYPOINT=cli '$SCRIPT' stop"
  [ "$output" = "All done. Ready for you." ]
}

@test "silent when muted file exists" {
  mkdir -p "$HOME/.config/speak-alert"
  touch "$HOME/.config/speak-alert/muted"
  run bash -c "echo '{\"cwd\":\"/x/operator\"}' | '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 on garbage stdin" {
  run bash -c "echo 'garbage' | '$SCRIPT' stop"
  [ "$status" -eq 0 ]
}

stub_say() { # <say -v '?' lines> : a macOS machine (uname says Darwin) whose say lists these voices
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$1" > "$HOME/bin/say"
  printf '#!/bin/sh\necho Darwin\n' > "$HOME/bin/uname"
  chmod +x "$HOME/bin/say" "$HOME/bin/uname"
}

@test "silent and logged when no say is installed" {
  # A PATH holding only what the hook needs, so the host's own say (macOS) is hidden.
  mkdir -p "$HOME/nosay"
  for c in bash jq date mkdir wc tail mv cat; do ln -s "$(command -v "$c")" "$HOME/nosay/$c"; done
  run env -u SPEAK_ALERT_DRY_RUN PATH="$HOME/nosay" "$HOME/nosay/bash" "$SCRIPT" stop </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'stop silent: no speech backend$' "$HOME/.local/state/speak-alert/events.log"
  ! grep -q 'spoke:' "$HOME/.local/state/speak-alert/events.log"
}

@test "prefers an installed Premium English voice" {
  stub_say "'Samantha            en_US    # Hello' 'Zoe (Premium)       en_US    # Hello' 'Amélie (Premium)    fr_CA    # Bonjour'"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=voice '$SCRIPT' stop"
  [ "$output" = "Zoe (Premium)" ]
}

@test "falls back to the system voice without a Premium voice" {
  stub_say "'Samantha            en_US    # Hello'"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=voice '$SCRIPT' stop"
  [ "$output" = "system" ]
}

@test "SPEAK_ALERT_VOICE overrides the choice" {
  stub_say "'Zoe (Premium)       en_US    # Hello'"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_VOICE=Daniel SPEAK_ALERT_DRY_RUN=voice '$SCRIPT' stop"
  [ "$output" = "Daniel" ]
}

codex_transcript() { # <originator> : a rollout whose first line says how the session started
  printf '{"type":"session_meta","payload":{"originator":"%s","source":"%s"}}\n' "$1" "$2" > "$HOME/rollout.jsonl"
}

@test "codex: done line when an interactive Codex turn stops" {
  codex_transcript codex-tui cli
  run bash -c "echo '{\"transcript_path\":\"$HOME/rollout.jsonl\",\"last_assistant_message\":\"x\"}' | '$SCRIPT' codex-stop"
  [ "$output" = "All done. Ready for you." ]
}

@test "codex: silent for headless codex exec runs" {
  codex_transcript codex_exec exec
  run bash -c "echo '{\"transcript_path\":\"$HOME/rollout.jsonl\"}' | '$SCRIPT' codex-stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "codex: permission request names the tool" {
  codex_transcript codex-tui cli
  run bash -c "echo '{\"transcript_path\":\"$HOME/rollout.jsonl\",\"tool_name\":\"Bash\"}' | '$SCRIPT' codex-permission"
  [ "$output" = "Codex needs your permission to use Bash." ]
}

@test "codex: permission request without a tool name" {
  run bash -c "echo '{}' | '$SCRIPT' codex-permission"
  [ "$output" = "Codex needs your permission." ]
}

@test "codex: silent when FM_TASK_ID is set" {
  codex_transcript codex-tui cli
  run bash -c "echo '{\"transcript_path\":\"$HOME/rollout.jsonl\"}' | FM_TASK_ID=t1 '$SCRIPT' codex-stop"
  [ -z "$output" ]
}

@test "logs what it decided" {
  codex_transcript codex_exec exec
  echo "{\"transcript_path\":\"$HOME/rollout.jsonl\"}" | "$SCRIPT" codex-stop
  echo '{}' | "$SCRIPT" stop
  grep -q 'codex-stop silent: headless codex exec$' "$HOME/.local/state/speak-alert/events.log"
  grep -q 'stop spoke: All done. Ready for you.$' "$HOME/.local/state/speak-alert/events.log"
}

@test "notify speaks permission, idle and elicitation prompts" {
  for t in permission_prompt idle_prompt elicitation_dialog agent_needs_input; do
    run bash -c "echo '{\"message\":\"Claude is waiting for your input\",\"notification_type\":\"$t\"}' | '$SCRIPT' notify"
    [ "$output" = "Claude is waiting for your input." ]
  done
}

@test "notify stays silent for other notification types, such as auth_success" {
  run bash -c "echo '{\"message\":\"Signed in\",\"notification_type\":\"auth_success\"}' | '$SCRIPT' notify"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'notify silent: notification auth_success$' "$HOME/.local/state/speak-alert/events.log"
}

# Engines. Nothing here plays audio: SPEAK_ALERT_DRY_RUN=engine, =cache and =play stop short of it.

os_is() { # <Darwin|Linux> : what uname reports
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\necho %s\n' "$1" > "$HOME/bin/uname"
  chmod +x "$HOME/bin/uname"
}

kokoro_installed() { # a stub speak-kokoro that logs each render, plus the model files it needs
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/kokoro"
  : > "$HOME/.local/share/kokoro/kokoro-v1.0.onnx"
  : > "$HOME/.local/share/kokoro/voices-v1.0.bin"
  cat > "$HOME/.local/bin/speak-kokoro" <<STUB
#!/bin/sh
echo "\$*" >> "$HOME/kokoro-calls"
while [ \$# -gt 1 ]; do [ "\$1" = --out ] && out="\$2"; shift; done
printf 'RIFF' > "\$out"
STUB
  chmod +x "$HOME/.local/bin/speak-kokoro"
}

players() { # stub paplay, afplay and an ffmpeg that copies its input to its output
  mkdir -p "$HOME/bin"
  for p in paplay afplay; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/played"\n' "$p" "$HOME" > "$HOME/bin/$p"
  done
  cat > "$HOME/bin/ffmpeg" <<'STUB'
#!/bin/sh
in=""; for a; do [ "$prev" = -i ] && in="$a"; prev="$a"; out="$a"; done
cp "$in" "$out"
STUB
  chmod +x "$HOME/bin/paplay" "$HOME/bin/afplay" "$HOME/bin/ffmpeg"
}

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

@test "engine: macOS uses say" {
  stub_say "'Samantha            en_US    # Hello'"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ "$output" = "say" ]
}

@test "engine: Linux uses Kokoro when its model is installed" {
  os_is Linux
  players
  kokoro_installed
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ "$output" = "kokoro" ]
}

@test "engine: Linux without the Kokoro model stays silent with the usual log line" {
  os_is Linux
  kokoro_installed
  rm "$HOME/.local/share/kokoro/kokoro-v1.0.onnx"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'stop silent: no speech backend$' "$HOME/.local/state/speak-alert/events.log"
  ! grep -q 'spoke:' "$HOME/.local/state/speak-alert/events.log"
}

@test "engine: SPEAK_ALERT_ENGINE=none is silent, even on macOS" {
  stub_say "'Samantha            en_US    # Hello'"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_ENGINE=none SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ -z "$output" ]
  grep -q 'stop silent: no speech backend$' "$HOME/.local/state/speak-alert/events.log"
}

@test "engine: openai-compatible needs VOICE_CLOUD_URL" {
  os_is Linux
  players
  mkdir -p "$HOME/.local/bin"
  ln -s "$REPO/home/dot_local/bin/executable_voice-cloud" "$HOME/.local/bin/voice-cloud"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_ENGINE=openai-compatible SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ -z "$output" ]
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' VOICE_CLOUD_URL=http://localhost:8880/v1 SPEAK_ALERT_ENGINE=openai-compatible SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ "$output" = "openai-compatible" ]
}

@test "kokoro voice defaults to af_heart and follows SPEAK_ALERT_VOICE" {
  os_is Linux
  players
  kokoro_installed
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=voice '$SCRIPT' stop"
  [ "$output" = "af_heart" ]
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_VOICE=bf_emma SPEAK_ALERT_DRY_RUN=voice '$SCRIPT' stop"
  [ "$output" = "bf_emma" ]
}

@test "cache key is the sha256 of engine, model, voice, rate, lead-in and text" {
  os_is Linux
  players
  kokoro_installed
  model="$HOME/.local/share/kokoro/kokoro-v1.0.onnx"
  want="$HOME/.cache/speak-alert/$(printf '%s' "kokoro|$model|af_heart|120|800|All done. Ready for you." | sha).wav"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=cache '$SCRIPT' stop"
  [ "$output" = "$want" ]
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_VOICE=bf_emma SPEAK_ALERT_DRY_RUN=cache '$SCRIPT' stop"
  [ "$output" != "$want" ]
  [[ "$output" == "$HOME/.cache/speak-alert/"*.wav ]] || false
}

@test "kokoro renders once into the cache, then plays the cached file with paplay" {
  os_is Linux
  kokoro_installed
  players
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=play '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  cached="$(bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=cache '$SCRIPT' stop")"
  [ "$output" = "paplay $cached" ]
  [ -s "$cached" ]
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=play '$SCRIPT' stop"
  [ "$output" = "paplay $cached" ]
  [ "$(wc -l < "$HOME/kokoro-calls")" -eq 1 ]
  grep -q -- '--voice af_heart' "$HOME/kokoro-calls"
  grep -q -- '--speed 0.80' "$HOME/kokoro-calls"
  [ ! -e "$HOME/played" ]
}

@test "kokoro on macOS plays with afplay" {
  os_is Darwin
  kokoro_installed
  players
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_ENGINE=kokoro SPEAK_ALERT_DRY_RUN=play '$SCRIPT' stop"
  [[ "$output" == "afplay $HOME/.cache/speak-alert/"*.wav ]] || false
}

@test "guards still come first with an engine installed" {
  os_is Linux
  kokoro_installed
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' FM_TASK_ID=t1 SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ -z "$output" ]
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' CLAUDE_CODE_ENTRYPOINT=sdk-cli SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ -z "$output" ]
  mkdir -p "$HOME/.config/speak-alert" && touch "$HOME/.config/speak-alert/muted"
  run bash -c "echo '{}' | PATH='$HOME/bin:$PATH' SPEAK_ALERT_DRY_RUN=engine '$SCRIPT' stop"
  [ -z "$output" ]
  grep -q 'stop silent: fleet worker$' "$HOME/.local/state/speak-alert/events.log"
  grep -q 'stop silent: headless claude$' "$HOME/.local/state/speak-alert/events.log"
  grep -q 'stop silent: muted$' "$HOME/.local/state/speak-alert/events.log"
  [ ! -e "$HOME/kokoro-calls" ]
}
