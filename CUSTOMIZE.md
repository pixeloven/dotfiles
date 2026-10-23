# Customize

Every tool follows the same loop: **change it → try it → keep it**. To keep a change, either edit the repo copy with `chezmoi edit <live path>` and then `chezmoi apply`, or edit the live file and run `/codify` in Claude Code.

## Ghostty

- **Where it lives:** `home/dot_config/ghostty/config.ghostty` → `~/.config/ghostty/config.ghostty`
- **Common changes:**
  - Theme: `theme = Rose Pine`. Browse themes with `ghostty +list-themes` (interactive; press `d` for dark only). To follow macOS light/dark instead: `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`.
  - Font: `font-family = Monaspace Neon`, `font-size = 15`. Installed fonts: `ghostty +list-fonts`.
  - Ligatures on: delete the two `font-feature = -calt` / `-liga` lines.
  - Transparency: `background-opacity = 0.9`.
  - A keybind: `keybind = cmd+shift+enter=toggle_split_zoom`.
- **Try it:** `cmd+shift+,` reloads.
- **Keep it:** `/codify` or `chezmoi edit ~/.config/ghostty/config.ghostty`
- **Reference:** `ghostty +show-config --default --docs`, https://ghostty.org/docs/config

## herdr

- **Where it lives:** `home/dot_config/herdr/config.toml` → `~/.config/herdr/config.toml`
- **Common changes:**
  - Theme: `[theme] name = "tokyo-night"`. Built-ins: catppuccin, terminal, tokyo-night, dracula, nord, gruvbox, one-dark, solarized, kanagawa, rose-pine, vesper.
  - A single colour: `[theme.custom] accent = "#f5c2e7"`.
  - Custom sounds: `[ui.sound] done_path = "sounds/done.mp3"`, `request_path = "sounds/request.mp3"` (relative to the config folder; add the mp3s with `chezmoi add`).
  - Desktop notifications instead of in-app toasts: `[ui.toast] delivery = "terminal"`.
  - Sidebar rows per agent: `[ui.sidebar.agents.rows_by_agent] claude = [["state_icon", "workspace", "tab"], ["agent"]]`.
- **Try it:** `herdr server reload-config`, then `herdr config check`.
- **Keep it:** `/codify` or `chezmoi edit ~/.config/herdr/config.toml`
- **Reference:** the commented defaults in herdr's built-in template (`herdr config check` shows anything it ignores), https://herdr.dev

## Claude Code

- **Where it lives:** `lib/claude-hooks.fragment.json` (the hooks we own) and `home/dot_claude/hooks/executable_speak-alert.sh`. Your `settings.json` itself is never committed.
- **Common changes:**
  - Spoken phrase: when an agent finishes it says "All done. Ready for you."; when it needs you it speaks Claude's own reason (e.g. "Claude needs your permission to use Bash."). Edit the `case` block in `speak-alert.sh` to change either.
  - Voice and speed: by default the alert uses the first installed English Premium voice, falling back to your macOS system voice (Read & Speak → System voice, e.g. a Siri voice), at rate 120 words per minute (lower is slower), after 800 ms of silence so the start isn't clipped. Set `SPEAK_ALERT_LEAD_MS` to change the lead-in. Change it in `speak-alert.sh`, or set `SPEAK_ALERT_VOICE` / `SPEAK_ALERT_RATE`. List voices with `say -v '?'`.
  - Which events speak: add or remove `Stop` / `Notification` entries in the fragment.
  - Theme: `/theme` inside Claude Code (stored in `~/.claude.json`, not tracked).
- **Try it:** `chezmoi apply` merges the fragment into `~/.claude/settings.json`, with a backup the first time it changes.
- **Keep it:** commit the repo change. Never hand-edit our hooks in `settings.json`; `/codify` reports when that has happened.
- **Reference:** https://docs.claude.com/en/docs/claude-code/hooks

## bat, delta, glow

- **Where they live:** `home/dot_config/bat/config`, `home/Library/Preferences/glow/glow.yml`, and the git keys in `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh`
- **Common changes:**
  - bat theme: `--theme="Catppuccin Macchiato"` (list: `bat --list-themes`).
  - Side-by-side diffs: in the gitconfig script, `git config --global delta.side-by-side true`.
  - delta theme: `git config --global delta.syntax-theme "Dracula"` (list: `delta --list-syntax-themes`).
  - glow width: `width: 120`.
- **Try it:** run `chezmoi apply`, then `bat README.md`, `git diff` or `glow README.md`.
- **Keep it:** `/codify`. A git key changed by hand shows up as owned-key drift; put the new value in the script.

## Packages

- **Where they live:** `Brewfile`
- **Add:** `brew install <name>` (or `--cask`), then `/codify` and keep it. Or add the line to the Brewfile and run `chezmoi apply`.
- **Don't track:** choose "skip" in `/codify`, which adds the name to `lib/drift-ignore.txt`.
- **Remove:** delete the line, then `brew uninstall <name>`.

## Undo a change

1. `chezmoi diff`: see how the machine differs from the repo.
2. `git -C ~/Development/dotfiles revert <commit>`: undo a recorded change.
3. `chezmoi apply`: put the machine back in line with the repo.
