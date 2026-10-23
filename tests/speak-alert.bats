#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_claude/hooks/executable_speak-alert.sh"

setup() {
  export HOME="$(mktemp -d)"
  export SPEAK_ALERT_DRY_RUN=1
  unset FM_TASK_ID
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
