#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_claude/hooks/executable_speak-alert.sh"

setup() {
  export HOME="$(mktemp -d)"
  export SPEAK_ALERT_DRY_RUN=1
  unset FM_TASK_ID
}

teardown() { rm -rf "$HOME"; }

@test "speaks project on stop" {
  run bash -c "echo '{\"cwd\":\"/x/operator\"}' | '$SCRIPT' stop"
  [ "$status" -eq 0 ]
  [ "$output" = "operator finished" ]
}

@test "speaks project on notify" {
  run bash -c "echo '{\"cwd\":\"/x/operator\"}' | '$SCRIPT' notify"
  [ "$output" = "operator needs you" ]
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
