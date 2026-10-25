#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_local/bin/executable_lastreply"
FIX="$BATS_TEST_DIRNAME/fixtures"

setup() {
  export HOME="$(mktemp -d)"
  WORK="$HOME/work/my.proj"
  unset HERDR_TAB_ID
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
  [[ "$output" == *"Checking now."* ]] || false
  [[ "$output" == *'```sh'* ]] || false
  [[ "$output" != *"Old answer."* ]] || false
  [[ "$output" != *"hidden"* ]] || false
  [[ "$output" != *"Subagent chatter."* ]] || false
}

@test "falls back to the newest transcript in any project" {
  claude_session other-project s2
  run bash -c "cd '$WORK' && '$SCRIPT' --raw"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Result"* ]] || false
}

@test "prints the latest Codex reply" {
  mkdir -p "$HOME/.codex/sessions/2026/10/23"
  cp "$FIX/codex-rollout.jsonl" "$HOME/.codex/sessions/2026/10/23/rollout-x.jsonl"
  run "$SCRIPT" --codex --raw
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Codex result"* ]] || false
  [[ "$output" == *"> second"* ]] || false
  [[ "$output" != *"Old codex answer."* ]] || false
}

@test "explains when there is no transcript" {
  run "$SCRIPT" --raw
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude transcript"* ]] || false
}

@test "explains when there is no transcript, run from a non-empty folder" {
  mkdir -p "$WORK/tests"
  : > "$WORK/notes.txt"
  run bash -c "cd '$WORK' && '$SCRIPT' --raw"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude transcript found"* ]] || false
  run bash -c "cd '$WORK' && '$SCRIPT' --codex --raw"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Codex transcript found"* ]] || false
}

@test "rejects unknown options" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "watch re-renders when a new reply arrives" {
  mkdir -p "$HOME/bin" "$HOME/.claude/projects/p"
  printf '#!/bin/sh\nsed "s/^/RENDER: /"\n' > "$HOME/bin/glow"
  printf '#!/bin/sh\n' > "$HOME/bin/clear"
  chmod +x "$HOME/bin/glow" "$HOME/bin/clear"
  T="$HOME/.claude/projects/p/s.jsonl"
  cp "$FIX/claude-transcript.jsonl" "$T"
  PATH="$HOME/bin:$PATH" "$SCRIPT" --watch > "$HOME/out" 2>&1 &
  pid=$!
  sleep 1
  touch -t 203001010000 "$T"
  echo '{"type":"user","message":{"content":"third"}}' >> "$T"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Fresh reply."}]}}' >> "$T"
  touch -t 203001010001 "$T"
  sleep 3
  kill "$pid"
  grep -q 'RENDER: ## Result' "$HOME/out"
  grep -q 'RENDER: Fresh reply.' "$HOME/out"
}

@test "watch rereads after a one-byte append, and not while the file is unchanged" {
  mkdir -p "$HOME/bin" "$HOME/.claude/projects/p"
  # Log each card read (the slurping jq call), then hand off to the real jq.
  printf '#!/bin/sh\n[ "$1" = -rs ] && echo read >> "%s/reads"\nexec %s "$@"\n' "$HOME" "$(command -v jq)" > "$HOME/bin/jq"
  printf '#!/bin/sh\ncat\n' > "$HOME/bin/glow"
  printf '#!/bin/sh\n' > "$HOME/bin/clear"
  chmod +x "$HOME/bin/jq" "$HOME/bin/glow" "$HOME/bin/clear"
  T="$HOME/.claude/projects/p/s.jsonl"
  cp "$FIX/claude-transcript.jsonl" "$T"
  PATH="$HOME/bin:$PATH" "$SCRIPT" --watch > "$HOME/out" 2>&1 &
  pid=$!
  sleep 5
  idle="$(grep -c . "$HOME/reads")"
  printf ' ' >> "$T"
  sleep 3
  kill "$pid"
  [ "$idle" -eq 1 ]
  [ "$(grep -c . "$HOME/reads")" -eq 2 ]
}

stub_herdr() { # <agent> <session-id> <tab-id> : herdr agent list reports one agent
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/herdr" <<STUB
#!/bin/sh
echo '{"result":{"agents":[{"agent":"$1","agent_session":{"value":"$2"},"tab_id":"$3"}]}}'
STUB
  chmod +x "$HOME/bin/herdr"
}

@test "in herdr, follows the session in the same tab, not the newest one" {
  claude_session p mine
  claude_session p other
  echo '{"type":"user","message":{"content":"x"}}' >> "$HOME/.claude/projects/p/other.jsonl"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Other session."}]}}' >> "$HOME/.claude/projects/p/other.jsonl"
  stub_herdr claude mine w1:tA
  run env PATH="$HOME/bin:$PATH" HERDR_TAB_ID=w1:tA "$SCRIPT" --raw
  [[ "$output" == *"## Result"* ]] || false
  [[ "$output" != *"Other session."* ]] || false
}

@test "--session picks a Claude session by id" {
  claude_session p wanted
  claude_session p newer
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Newer."}]}}' >> "$HOME/.claude/projects/p/newer.jsonl"
  run "$SCRIPT" --raw --session wanted
  [[ "$output" == *"## Result"* ]] || false
}

@test "in herdr, follows the Codex session in the same tab" {
  mkdir -p "$HOME/.codex/sessions/2026/10/23"
  cp "$FIX/codex-rollout.jsonl" "$HOME/.codex/sessions/2026/10/23/rollout-2026-abc123.jsonl"
  echo '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"newest other"}]}}' > "$HOME/.codex/sessions/2026/10/23/rollout-2026-zzz999.jsonl"
  stub_herdr codex abc123 w1:tB
  run env PATH="$HOME/bin:$PATH" HERDR_TAB_ID=w1:tB "$SCRIPT" --codex --raw
  [[ "$output" == *"# Codex result"* ]] || false
  [[ "$output" != *"newest other"* ]] || false
}

@test "--session for an unknown id explains itself" {
  run "$SCRIPT" --raw --session nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude transcript"* ]] || false
}

@test "--open splits the current herdr pane and runs watch for this session" {
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/herdr" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/herdr.log"
[ "$1 $2" = "pane split" ] && echo '{"result":{"pane":{"pane_id":"w1:pZ"}}}'
exit 0
STUB
  chmod +x "$HOME/bin/herdr"
  run env PATH="$HOME/bin:$PATH" HERDR_PANE_ID=w1:pA CLAUDE_CODE_SESSION_ID=abc-123 "$SCRIPT" --open
  [ "$status" -eq 0 ]
  grep -q '^pane split --current --direction right' "$HOME/herdr.log"
  grep -q '^pane run w1:pZ lastreply --watch --session abc-123$' "$HOME/herdr.log"
}

@test "--open outside herdr explains itself" {
  run env -u HERDR_PANE_ID "$SCRIPT" --open
  [ "$status" -eq 1 ]
  [[ "$output" == *"herdr"* ]] || false
}

@test "shows your prompt above the reply" {
  claude_session p s
  run "$SCRIPT" --raw --session s
  [[ "$output" == *"> second question"* ]] || false
  [[ "$output" != *"first question"* ]] || false
}

@test "slash commands show as the command, not raw tags" {
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"user","message":{"content":"<command-message>lastreply</command-message>\n<command-name>/lastreply</command-name>"}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Opened."}]}}' > "$HOME/.claude/projects/p/c.jsonl"
  run "$SCRIPT" --raw --session c
  [[ "$output" == *"> /lastreply"* ]] || false
  [[ "$output" != *"<command"* ]] || false
}

@test "hidden follow-up entries don't replace your prompt" {
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"[Image #4] Fix the theme"},{"type":"image"}]}}' \
    '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"[Image: source: /tmp/shot.png]"}]}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"On it."}]}}' > "$HOME/.claude/projects/p/m.jsonl"
  run "$SCRIPT" --raw --session m
  [[ "$output" == *"> [Image #4] Fix the theme"* ]] || false
  [[ "$output" != *"shot.png"* ]] || false
}

codex_rollout() { # <name> <cwd> : rollout with a commentary note and a final answer
  mkdir -p "$HOME/.codex/sessions/2026/10/24"
  printf '%s\n' \
    "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$1\",\"cwd\":\"$2\"}}" \
    '{"type":"response_item","timestamp":"2026-10-24T07:00:00.000Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"check it"}]}}' \
    '{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Looking around."}]}}' \
    "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"phase\":\"final_answer\",\"content\":[{\"type\":\"output_text\",\"text\":\"Final from $1.\"}]}}" \
    > "$HOME/.codex/sessions/2026/10/24/rollout-2026-10-24-$1.jsonl"
}

@test "codex: shows only the final answer, not commentary" {
  codex_rollout t1 /nowhere
  run "$SCRIPT" --codex --raw --session t1
  [[ "$output" == *"Final from t1."* ]] || false
  [[ "$output" != *"Looking around."* ]] || false
}

@test "codex: prefers the newest session for the current folder" {
  codex_rollout here "$WORK"
  sleep 1
  codex_rollout elsewhere /somewhere/else
  run bash -c "cd '$WORK' && '$SCRIPT' --codex --raw"
  [[ "$output" == *"Final from here."* ]] || false
}

@test "a half-written last line doesn't blank the reply" {
  claude_session p s
  printf '%s' '{"type":"assistant","message":{"content":[{"type":"te' >> "$HOME/.claude/projects/p/s.jsonl"
  run "$SCRIPT" --raw --session s
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Result"* ]] || false
}

@test "--open inside Codex pins the Codex thread" {
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/herdr" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/herdr.log"
[ "$1 $2" = "pane split" ] && echo '{"result":{"pane":{"pane_id":"w1:pZ"}}}'
exit 0
STUB
  chmod +x "$HOME/bin/herdr"
  run env -u CLAUDE_CODE_SESSION_ID PATH="$HOME/bin:$PATH" HERDR_PANE_ID=w1:pA CODEX_THREAD_ID=019a-thread "$SCRIPT" --open
  [ "$status" -eq 0 ]
  grep -q '^pane run w1:pZ lastreply --watch --codex --session 019a-thread$' "$HOME/herdr.log"
}

@test "rejects a session id with shell characters" {
  run "$SCRIPT" --raw --session 'x; rm -rf ~'
  [ "$status" -eq 2 ]
}
