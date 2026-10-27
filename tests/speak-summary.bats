#!/usr/bin/env bats
# Spoken summaries: opt-in through ~/.config/speak-alert/summaries, spoken instead of the done line.

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_claude/hooks/executable_speak-alert.sh"

setup() {
  export HOME="$(mktemp -d)"
  export SPEAK_ALERT_DRY_RUN=1
  unset FM_TASK_ID CLAUDE_CODE_ENTRYPOINT SPEAK_ALERT_SUMMARIZER
  mkdir -p "$HOME/.config/speak-alert" "$HOME/bin"
}

teardown() { rm -rf "$HOME"; }

summaries_on() { touch "$HOME/.config/speak-alert/summaries"; }

payload() { # <reply text> : a Stop hook payload from a session in /x/dotfiles
  jq -cn --arg m "$1" '{cwd: "/x/dotfiles", last_assistant_message: $m}' > "$HOME/payload.json"
}

summary() { # <mode> : run the hook on the payload
  bash -c "PATH='$HOME/bin:$PATH' '$SCRIPT' $1 < '$HOME/payload.json'"
}

@test "summaries are off by default" {
  payload "Fixed the bug."
  run summary summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'summary silent: summaries off$' "$HOME/.local/state/speak-alert/events.log"
  run summary stop
  [ "$output" = "All done. Ready for you." ]
}

@test "with summaries on, the summary replaces the done line" {
  summaries_on
  payload "Fixed the flaky test. It now waits for the socket."
  run summary stop
  [ -z "$output" ]
  grep -q 'stop silent: summary instead$' "$HOME/.local/state/speak-alert/events.log"
  run summary summary
  [ "$output" = "dotfiles. Fixed the flaky test. It now waits for the socket." ]
}

@test "strips code blocks, headings, tables, links and markdown marks" {
  summaries_on
  payload "$(printf '## Result\n\n```sh\nrm -rf /tmp/x\n```\n\n**Done**: the \x60speak-alert.sh\x60 hook now reads [the docs](https://example.com/x).\n\n| a | b |\n|---|---|\n\n- second point')"
  run summary summary
  [ "$output" = "dotfiles. Done: the speak-alert.sh hook now reads the docs. second point." ]
}

@test "speaks at most two sentences" {
  summaries_on
  payload "One. Two. Three. Four."
  run summary summary
  [ "$output" = "dotfiles. One. Two." ]
}

@test "caps a long summary at about 220 characters, on a word boundary" {
  summaries_on
  payload "$(printf 'word%.0s ' $(seq 1 80))end."
  run summary summary
  [ "${#output}" -le 230 ]
  [[ "$output" == "dotfiles. word word"* ]] || false
  [[ "$output" != *"wor" ]] || false
  [[ "$output" != *"end."* ]] || false
}

@test "an empty reply falls back to the done line" {
  summaries_on
  payload ""
  run summary summary
  [ "$output" = "All done. Ready for you." ]
}

@test "mute, fleet workers and headless runs silence summaries too" {
  summaries_on
  payload "Fixed it."
  run bash -c "FM_TASK_ID=t1 '$SCRIPT' summary < '$HOME/payload.json'"
  [ -z "$output" ]
  run bash -c "CLAUDE_CODE_ENTRYPOINT=sdk-cli '$SCRIPT' summary < '$HOME/payload.json'"
  [ -z "$output" ]
  touch "$HOME/.config/speak-alert/muted"
  run summary summary
  [ -z "$output" ]
  grep -q 'summary silent: muted$' "$HOME/.local/state/speak-alert/events.log"
}

stub_claude() { # <script body> : a fake claude CLI that logs its arguments and stdin
  cat > "$HOME/bin/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$*" > "$HOME/claude-args"
cat > "$HOME/claude-stdin"
$1
STUB
  chmod +x "$HOME/bin/claude"
}

@test "SPEAK_ALERT_SUMMARIZER=claude asks Haiku with hooks off" {
  summaries_on
  stub_claude 'echo "Fixed the socket race in the tests."'
  payload "A long reply about the socket race."
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude '$SCRIPT' summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Fixed the socket race in the tests." ]
  grep -q -- '-p' "$HOME/claude-args"
  grep -q -- '--model haiku' "$HOME/claude-args"
  grep -q -- '--no-session-persistence' "$HOME/claude-args"
  grep -q 'disableAllHooks' "$HOME/claude-args"
  [ "$(cat "$HOME/claude-stdin")" = "A long reply about the socket race." ]
}

@test "the Haiku summarizer falls back to the heuristic when it fails" {
  summaries_on
  stub_claude 'echo "Not logged in · Please run /login"; exit 1'
  payload "Fixed it. Then more."
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude '$SCRIPT' summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Fixed it. Then more." ]
}

@test "the Haiku summarizer falls back to the heuristic when it times out" {
  summaries_on
  stub_claude 'exec sleep 30'
  payload "Fixed it."
  start=$SECONDS
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude SPEAK_ALERT_SUMMARY_TIMEOUT=1 '$SCRIPT' summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Fixed it." ]
  [ $((SECONDS - start)) -lt 10 ]
}

@test "the Haiku timeout is not held up by a child that keeps stdout open" {
  summaries_on
  stub_claude 'sleep 30; echo late'
  payload "Fixed it."
  start=$SECONDS
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude SPEAK_ALERT_SUMMARY_TIMEOUT=1 '$SCRIPT' summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Fixed it." ]
  [ $((SECONDS - start)) -lt 10 ]
}

codex_payload() { # <originator> <source> <reply>
  printf '{"type":"session_meta","payload":{"originator":"%s","source":"%s"}}\n' "$1" "$2" > "$HOME/rollout.jsonl"
  jq -cn --arg m "$3" --arg t "$HOME/rollout.jsonl" '{cwd: "/x/dotfiles", transcript_path: $t, last_assistant_message: $m}' > "$HOME/payload.json"
}

@test "codex: summary replaces the done line, and headless exec stays silent" {
  summaries_on
  codex_payload codex-tui cli "Updated the README."
  run summary codex-stop
  [ -z "$output" ]
  run summary codex-summary
  [ "$output" = "dotfiles. Updated the README." ]
  codex_payload codex_exec exec "Updated the README."
  run summary codex-summary
  [ -z "$output" ]
  grep -q 'codex-summary silent: headless codex exec$' "$HOME/.local/state/speak-alert/events.log"
}

@test "codex: Codex replies go to Haiku only with SPEAK_ALERT_SUMMARIZER=claude-all" {
  summaries_on
  stub_claude 'echo "Haiku line."'
  codex_payload codex-tui cli "Heuristic line."
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude '$SCRIPT' codex-summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Heuristic line." ]
  [ ! -e "$HOME/claude-args" ]
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude-all '$SCRIPT' codex-summary < '$HOME/payload.json'"
  [ "$output" = "dotfiles. Haiku line." ]
}

@test "a mute pressed while Haiku summarizes silences that summary" {
  summaries_on
  payload "A long reply about the socket race."
  stub_claude "touch '$HOME/.config/speak-alert/muted'; echo 'Fixed the socket race.'"
  run bash -c "PATH='$HOME/bin:$PATH' SPEAK_ALERT_SUMMARIZER=claude '$SCRIPT' summary < '$HOME/payload.json'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'summary silent: muted$' "$HOME/.local/state/speak-alert/events.log"
  ! grep -q 'spoke:' "$HOME/.local/state/speak-alert/events.log"
}
