#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

render() { # <target .tmpl relative to home/>
  : > "$BATS_TEST_TMPDIR/chezmoi.toml"
  chezmoi --source "$REPO" --config "$BATS_TEST_TMPDIR/chezmoi.toml" execute-template < "$REPO/home/$1"
}

@test "lastreply skill renders for Claude and Codex with each session variable" {
  claude="$(render dot_claude/skills/lastreply/SKILL.md.tmpl)"
  codex="$(render dot_agents/skills/lastreply/SKILL.md.tmpl)"
  [[ "$claude" == *'$CLAUDE_CODE_SESSION_ID'* ]] || false
  [[ "$claude" == *"runs /lastreply"* ]] || false
  [[ "$codex" == *'$CODEX_THREAD_ID'* ]] || false
  [[ "$codex" == *'runs $lastreply'* ]] || false
  [[ "$codex" == *"--codex --session"* ]] || false
  [ "$(head -1 <<<"$codex")" = "---" ]
}

@test "codify skill renders for both and stages explicit paths only" {
  for t in dot_claude/skills/codify/SKILL.md.tmpl dot_agents/skills/codify/SKILL.md.tmpl; do
    out="$(render "$t")"
    [ "$(sed -n 2p <<<"$out")" = "name: codify" ]
    [[ "$out" == *"git add -- <each path you changed>"* ]] || false
    [[ "$out" == *"never \`git add -A\`"* ]] || false
  done
}
