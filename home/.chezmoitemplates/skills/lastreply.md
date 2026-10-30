---
name: lastreply
description: Use when the user runs {{ .invoke }}lastreply or asks to see the agent's replies rendered, in a side pane, or with rich markdown in herdr. Opens a herdr split beside this session that renders each reply with glow.
---

# Open a rendered-reply pane for this session

Shared by Claude Code and Codex; the source is `home/.chezmoitemplates/skills/lastreply.md` in ~/Development/dotfiles.

Run this once with your shell tool. It splits the current herdr pane to the right and starts `lastreply --watch` there, pinned to this session through `{{ .session_var }}`:

```sh
lastreply --open
```

- On success it prints the new pane's id. Tell the user the pane is open at the latest reply, with earlier ones already read (p steps back to them); new replies wait behind an unread count rather than replacing the view. The pane keeps the newest 50 replies.
- Keys in that pane: Space/n/→ next (marks read), p/← previous, u oldest unread, G/End latest (marks all read), q quits. A long reply scrolls in place: ↓/j/Enter and ↑/k a line, PgDn/PgUp a page, Ctrl-d/Ctrl-u half a page, g/Home/< its top, > its bottom.
- If it says it needs a herdr pane, the session isn't running inside herdr. Tell the user to run `lastreply --watch {{ if eq .agent "codex" }}--codex {{ end }}--session <id>` in any terminal, giving them the value of `{{ .session_var }}`.
- Don't open a second pane if one is already showing this session; ask first.
