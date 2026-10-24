---
name: lastreply
description: Use when the user runs /lastreply or asks to see Claude's replies rendered, in a side pane, or with rich markdown in herdr. Opens a herdr split beside this session that renders each reply with glow.
---

# Open a rendered-reply pane for this session

Run this once with Bash. It splits the current herdr pane to the right and starts `lastreply --watch` there, pinned to this session through `$CLAUDE_CODE_SESSION_ID`:

```sh
lastreply --open
```

- On success it prints the new pane's id. Tell the user the pane is open and redraws after each reply.
- If it says it needs a herdr pane, the session isn't running inside herdr. Tell the user to run `lastreply --watch --session <id>` in any terminal, giving them the value of `$CLAUDE_CODE_SESSION_ID`.
- Don't open a second pane if one is already showing this session; ask first.
