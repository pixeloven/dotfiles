#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_local/bin/executable_lastreply"
FIX="$BATS_TEST_DIRNAME/fixtures"

setup() {
  export HOME="$(mktemp -d)"
  WORK="$HOME/work/my.proj"
  unset HERDR_TAB_ID
  mkdir -p "$WORK"
}

teardown() { [ -z "${pid:-}" ] || kill "$pid" 2>/dev/null; rm -rf "$HOME"; }

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

reader_stubs() { # glow passes the card through, clear marks a new screen, less keeps what it paged
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\ncat\n' > "$HOME/bin/glow"
  printf '#!/bin/sh\necho ---clear---\n' > "$HOME/bin/clear"
  printf '#!/bin/sh\ncat "$2" > "$HOME/paged"\n' > "$HOME/bin/less"
  chmod +x "$HOME/bin/glow" "$HOME/bin/clear" "$HOME/bin/less"
}

turn() { # <file> <time> <prompt> <reply> [stop_reason] : append a prompt and its reply
  printf '%s\n' "{\"type\":\"user\",\"timestamp\":\"$2\",\"message\":{\"content\":\"$3\"}}" \
    "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$4\"}],\"stop_reason\":\"${5:-end_turn}\"}}" >> "$1"
}

start_reader() { # <args> : the reader in the background, keys from a FIFO on fd 7
  reader_stubs
  mkfifo "$HOME/keys"
  PATH="$HOME/bin:$PATH" "$SCRIPT" --watch "$@" < "$HOME/keys" > "$HOME/out" 2>&1 3>&- &
  pid=$!
  exec 7> "$HOME/keys"
  sleep 2
}

press() { printf '%b' "$1" >&7; sleep 1; }

stop_reader() { exec 7>&-; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true; }

screen() { # the last screen the reader drew
  awk '/^---clear---$/ { s = ""; next } { s = s $0 "\n" } END { printf "%s", s }' "$HOME/out"
}

bar() { screen | tail -1; }

@test "watch: a new finished reply only raises the unread count" {
  reader_stubs
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/s.jsonl"
  cp "$FIX/claude-transcript.jsonl" "$T"
  PATH="$HOME/bin:$PATH" "$SCRIPT" --watch < /dev/null > "$HOME/out" 2>&1 3>&- &
  pid=$!
  # The reply has to arrive after the pane opened, or opening marks it read too.
  for i in $(seq 1 20); do grep -q 'caught up' "$HOME/out" 2>/dev/null && break; sleep 0.5; done
  turn "$T" 2026-10-24T07:02:00.000Z third "Fresh reply."
  sleep 3
  kill "$pid"
  screen | grep -q '^## Result'
  ! screen | grep -q 'Fresh reply.' || false
  [[ "$(bar)" == " 2/3  ● 1 unread"* ]] || false
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

@test "reader keys step through replies and move the read marker" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/q.jsonl"
  for i in 1 2 3; do turn "$T" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply $i."; done
  start_reader --session q
  [[ "$(bar)" == " 3/3  ✓ caught up"* ]] || false
  for i in 4 5 6; do turn "$T" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply $i."; done
  sleep 3
  screen | grep -q '^Reply 3.$'
  [[ "$(bar)" == " 3/6  ● 3 unread"* ]] || false
  press n
  screen | grep -q '^Reply 4.$'
  [[ "$(bar)" == " 4/6  ● 3 unread"* ]] || false
  press ' '
  [[ "$(bar)" == " 5/6  ● 2 unread"* ]] || false
  press p
  [[ "$(bar)" == " 4/6  ● 2 unread"* ]] || false
  press '\033[D'
  [[ "$(bar)" == " 3/6  ● 2 unread"* ]] || false
  press u
  screen | grep -q '^Reply 5.$'
  press '\033[C'
  [[ "$(bar)" == " 6/6  ● 1 unread"* ]] || false
  press p
  press '\033[F'
  [[ "$(bar)" == " 6/6  ✓ caught up"* ]] || false
  press q
  wait "$pid"
  exec 7>&-
}

@test "reader opens at the latest reply with every earlier one read" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/r.jsonl"
  for i in 1 2 3 4; do turn "$T" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply $i."; done
  start_reader --session r
  screen | grep -q '^Reply 4.$'
  [[ "$(bar)" == " 4/4  ✓ caught up"* ]] || false
  press p
  screen | grep -q '^Reply 3.$'
  [[ "$(bar)" == " 3/4  ✓ caught up"* ]] || false
  press u
  stop_reader
  [[ "$(bar)" == " 3/4  ✓ caught up"* ]] || false
}

@test "reader keeps only the newest 50 replies and stays on the one it shows" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/c.jsonl"
  for i in $(seq 1 55); do turn "$T" "$(printf '2026-10-24T08:%02d:00.000Z' "$i")" "ask $i" "Reply $i."; done
  start_reader --session c
  [[ "$(bar)" == " 50/50  ✓ caught up"* ]] || false
  for i in $(seq 1 49); do printf p >&7; done
  for i in $(seq 1 40); do [[ "$(bar)" == " 1/50 "* ]] && break; sleep 0.5; done
  screen | grep -q '^Reply 6.$'
  [[ "$(bar)" == " 1/50  ✓ caught up"* ]] || false
  press p
  screen | grep -q '^Reply 6.$'
  press G
  for i in 56 57; do turn "$T" "2026-10-24T08:$i:00.000Z" "ask $i" "Reply $i."; done
  sleep 3
  screen | grep -q '^Reply 55.$'
  [[ "$(bar)" == " 48/50  ● 2 unread"* ]] || false
  press G
  stop_reader
  screen | grep -q '^Reply 57.$'
  [[ "$(bar)" == " 50/50  ✓ caught up"* ]] || false
}

@test "reader: a Claude reply counts only once the turn has ended" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/w.jsonl"
  turn "$T" 2026-10-24T07:01:00.000Z "ask 1" "Reply 1."
  turn "$T" 2026-10-24T07:02:00.000Z "ask 2" "Working on it." tool_use
  start_reader --session w
  [[ "$(bar)" == " 1/1  ✓ caught up · ✎ writing"* ]] || false
  ! screen | grep -q 'Working on it.' || false
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}],"stop_reason":"end_turn"}}' >> "$T"
  sleep 3
  stop_reader
  [[ "$(bar)" == " 1/2  ● 1 unread"* ]] || false
  screen | grep -q '^Reply 1.$'
}

@test "reader: a Codex reply counts only after task_complete" {
  codex_rollout c1 /nowhere
  start_reader --codex --session c1
  [[ "$(bar)" == " 0/0  ✓ caught up · ✎ writing"* ]] || false
  grep -q 'No finished reply yet.' "$HOME/out"
  echo '{"type":"event_msg","payload":{"type":"task_complete"}}' >> "$HOME/.codex/sessions/2026/10/24/rollout-2026-10-24-c1.jsonl"
  sleep 3
  [[ "$(bar)" == " 0/1  ● 1 unread"* ]] || false
  press n
  stop_reader
  screen | grep -q 'Final from c1.'
}

@test "wakes and compactions are labelled instead of (no text)" {
  mkdir -p "$HOME/.claude/projects/p"
  printf '%s\n' \
    '{"type":"user","message":{"content":"<task-notification>\n<summary>Stop hook feedback</summary>\n</task-notification>\n<system-reminder>wake</system-reminder>"}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Handled."}],"stop_reason":"end_turn"}}' > "$HOME/.claude/projects/p/k.jsonl"
  run "$SCRIPT" --raw --session k
  [[ "$output" == "**Wake** · "*"> ⚑ Stop hook feedback"* ]] || false
  printf '%s\n' \
    '{"type":"user","isCompactSummary":true,"message":{"content":"This session is being continued. <summary>long</summary>"}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Continuing."}],"stop_reason":"end_turn"}}' >> "$HOME/.claude/projects/p/k.jsonl"
  run "$SCRIPT" --raw --session k
  [[ "$output" == *"> (context compacted)"* ]] || false
  [[ "$output" != *"being continued"* ]] || false
}

@test "reader shows a tall card from its top and Enter pages all of it" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/l.jsonl"
  turn "$T" 2026-10-24T07:01:00.000Z "long one" "$(seq -f 'line %g' 1 100 | awk '{printf "%s\\n", $0}')"
  start_reader --session l
  screen | grep -q '^> long one$'
  ! screen | grep -q '^line 100$' || false
  [[ "$(bar)" == *"▼ "*" more lines, Enter"* ]] || false
  [ "$(screen | wc -l)" -eq 40 ]
  press '\n'
  stop_reader
  grep -q '^line 100$' "$HOME/paged"
}

@test "reader: arrow keys and terminal answers leave no stray characters on screen" {
  reader_stubs
  # Like glow 3.0: ask the terminal for its colours and cursor on every render, unless TERM is
  # dumb, and take a moment so a key can arrive while the card is being drawn.
  printf '#!/bin/sh\n[ "$TERM" = dumb ] || printf %s > /dev/tty\nsleep 0.3\ncat\n' \
    "'\033]10;?\033\\\\\033[6n\033]11;?\033\\\\\033[6n'" > "$HOME/bin/glow"
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/a.jsonl"
  for i in 1 2 3 4; do turn "$T" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply $i."; done
  keys='[[2,"\u001b[D"],[0.1,"\u001b[D"],[1.5,"\u001b[C"],[1.5,"p"],[1.5,"q"]]'
  PATH="$HOME/bin:$PATH" TERM=xterm-256color python3 -I "$FIX/answering-terminal.py" "$HOME/out" "$keys" \
    "$SCRIPT" --watch --session a
  [[ "$(bar)" == *" 2/4  ✓ caught up"* ]] || false
  ! grep -qF ']11;?' "$HOME/out" || false
  ! grep -q 'rgb:' "$HOME/out" || false
  ! grep -q '25R' "$HOME/out" || false
  ! grep -q '\^\[' "$HOME/out" || false
}

@test "reader: a terminal's answers read as keys neither move the view nor eat the next key" {
  mkdir -p "$HOME/.claude/projects/p"
  T="$HOME/.claude/projects/p/e.jsonl"
  for i in 1 2 3; do turn "$T" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply $i."; done
  start_reader --session e
  press p
  press '\033]10;rgb:cdcd/d6d6/f4f4\033\\\033[74;25R\033]11;rgb:2828/2c2c/3434\007\033[74;25Rp'
  [[ "$(bar)" == " 1/3  ✓ caught up"* ]] || false
  press q
  wait "$pid"
  exec 7>&-
}

@test "reader: switching to another session and back keeps unread replies unread and the view" {
  mkdir -p "$HOME/bin" "$HOME/.claude/projects/p"
  # herdr agent list reports whichever session id is in tab-session.
  printf '#!/bin/sh\nprintf %s "$(cat "$HOME/tab-session")"\n' \
    "'{\"result\":{\"agents\":[{\"agent\":\"claude\",\"agent_session\":{\"value\":\"%s\"},\"tab_id\":\"w1:tA\"}]}}'" > "$HOME/bin/herdr"
  chmod +x "$HOME/bin/herdr"
  A="$HOME/.claude/projects/p/a.jsonl" B="$HOME/.claude/projects/p/b.jsonl"
  for i in 1 2 3; do turn "$A" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply A$i."; done
  for i in 1 2; do turn "$B" "2026-10-24T08:0$i:00.000Z" "ask $i" "Reply B$i."; done
  echo a > "$HOME/tab-session"
  export HERDR_TAB_ID=w1:tA
  start_reader
  for i in 4 5; do turn "$A" "2026-10-24T07:0$i:00.000Z" "ask $i" "Reply A$i."; done
  sleep 3
  press p
  screen | grep -q '^Reply A2.$'
  [[ "$(bar)" == " 2/5  ● 2 unread"* ]] || false
  echo b > "$HOME/tab-session"
  sleep 3
  screen | grep -q '^Reply B2.$'
  [[ "$(bar)" == " 2/2  ✓ caught up"* ]] || false
  echo a > "$HOME/tab-session"
  sleep 3
  stop_reader
  screen | grep -q '^Reply A2.$'
  [[ "$(bar)" == " 2/5  ● 2 unread"* ]] || false
  ! screen | grep -q 'caught up' || false
}
