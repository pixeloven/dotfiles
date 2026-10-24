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
  [[ "$output" == *"## Result"* ]]
  [[ "$output" != *"Other session."* ]]
}

@test "--session picks a Claude session by id" {
  claude_session p wanted
  claude_session p newer
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Newer."}]}}' >> "$HOME/.claude/projects/p/newer.jsonl"
  run "$SCRIPT" --raw --session wanted
  [[ "$output" == *"## Result"* ]]
}

@test "in herdr, follows the Codex session in the same tab" {
  mkdir -p "$HOME/.codex/sessions/2026/10/23"
  cp "$FIX/codex-rollout.jsonl" "$HOME/.codex/sessions/2026/10/23/rollout-2026-abc123.jsonl"
  echo '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"newest other"}]}}' > "$HOME/.codex/sessions/2026/10/23/rollout-2026-zzz999.jsonl"
  stub_herdr codex abc123 w1:tB
  run env PATH="$HOME/bin:$PATH" HERDR_TAB_ID=w1:tB "$SCRIPT" --codex --raw
  [ "$output" = "# Codex result" ]
}

@test "--session for an unknown id explains itself" {
  run "$SCRIPT" --raw --session nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude transcript"* ]]
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
  [[ "$output" == *"herdr"* ]]
}
