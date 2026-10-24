#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_local/bin/executable_lastreply"
FIX="$BATS_TEST_DIRNAME/fixtures"

setup() {
  export HOME="$(mktemp -d)"
  WORK="$HOME/work/my.proj"
  mkdir -p "$WORK"
}

teardown() { rm -rf "$HOME"; }

claude_session() { # <slug> <name> : copy the fixture into a project folder
  mkdir -p "$HOME/.claude/projects/$1"
  cp "$FIX/claude-transcript.jsonl" "$HOME/.claude/projects/$1/$2.jsonl"
}

@test "prints the latest Claude reply, joining text across tool calls" {
  claude_session "$(printf '%s' "$WORK" | sed 's/[^A-Za-z0-9]/-/g')" s1
  run bash -c "cd '$WORK' && '$SCRIPT' --raw"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking now."* ]]
  [[ "$output" == *'```sh'* ]]
  [[ "$output" != *"Old answer."* ]]
  [[ "$output" != *"hidden"* ]]
  [[ "$output" != *"Subagent chatter."* ]]
}

@test "falls back to the newest transcript in any project" {
  claude_session other-project s2
  run bash -c "cd '$WORK' && '$SCRIPT' --raw"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Result"* ]]
}

@test "prints the latest Codex reply" {
  mkdir -p "$HOME/.codex/sessions/2026/10/23"
  cp "$FIX/codex-rollout.jsonl" "$HOME/.codex/sessions/2026/10/23/rollout-x.jsonl"
  run "$SCRIPT" --codex --raw
  [ "$status" -eq 0 ]
  [ "$output" = "# Codex result" ]
}

@test "explains when there is no transcript" {
  run "$SCRIPT" --raw
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude transcript"* ]]
}

@test "rejects unknown options" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}
