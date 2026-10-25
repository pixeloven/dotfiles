#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_claude/hooks/executable_speak-alert.sh"

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

stub_say() {
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$1" > "$HOME/bin/say"
  chmod +x "$HOME/bin/say"
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
