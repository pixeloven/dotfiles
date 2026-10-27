# Customize

Every tool follows the same loop: **change it → try it → keep it**. To keep a change, either edit the repo copy with `chezmoi edit <live path>` and then `chezmoi apply`, or edit the live file and run `/codify` in Claude Code.

## Ghostty

- **Where it lives:** `home/dot_config/ghostty/config.ghostty` → `~/.config/ghostty/config.ghostty`, which loads the per-OS `macos.ghostty` or `linux.ghostty` beside it
- **Common changes:**
  - Theme: `theme = Rose Pine`. Browse themes with `ghostty +list-themes` (interactive; press `d` for dark only). To follow the system light/dark instead: `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`.
  - Font: `font-family = Monaspace Neon`, `font-size = 15`. Installed fonts: `ghostty +list-fonts`.
  - Ligatures on: delete the two `font-feature = -calt` / `-liga` lines.
  - Transparency: `background-opacity = 0.9`.
  - A keybind: `keybind = cmd+shift+enter=toggle_split_zoom` (on Linux, `ctrl+shift+enter`).
  - Option as Alt (in `macos.ghostty`): `macos-option-as-alt = left` (the default here) lets left Option+C open fzf's folder search; use `true` for both Options or delete the line to type special characters with either.
- **Try it:** `cmd+shift+,` reloads (`ctrl+shift+,` on Linux).
- **Keep it:** `/codify` or `chezmoi edit ~/.config/ghostty/config.ghostty`
- **Reference:** `ghostty +show-config --default --docs`, https://ghostty.org/docs/config

## Ptyxis (Linux, when it's your terminal)

- **Where it lives:** `home/dot_local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette` → `~/.local/share/org.gnome.Ptyxis/palettes/`, and `home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl`, which sets only the default profile's palette in GSettings. Every other Ptyxis preference, the font included, stays yours. From a distrobox it sets it on the host through `distrobox-host-exec`.
- **Common changes:**
  - Colours: edit the palette file, or point the script's `palette` line at another palette by file name without `.palette`.
- **Try it:** Ptyxis → Preferences shows the change at once.
- **Keep it:** edit the script or palette, then `chezmoi apply`. `drift` reports a palette changed in Preferences as `owned-key`.

## Shell (zsh)

- **Where it lives:** `home/dot_config/zsh/dotfiles.zsh` → `~/.config/zsh/dotfiles.zsh` (oh-my-zsh settings, history, completion, fzf-tab, fzf, zoxide, fnm, eza aliases, autosuggestions, syntax highlighting, Starship) and `home/dot_config/starship.toml` → `~/.config/starship.toml`. Your `~/.zshrc` itself is never committed; it keeps your private lines plus one line, inside a `# >>> dotfiles >>>` marker block, that sources `dotfiles.zsh` (added by `home/.chezmoiscripts/run_onchange_after_40-zshrc-source.sh`).
- **What you get:** grey suggestions as you type (→ accepts), Ctrl+R history search, Ctrl+T file search, Alt+C folder jump (left Option+C in Ghostty on macOS), a fuzzy Tab menu with previews, `z <part of a path>` / `zi` to jump to folders you've visited, `ls`/`ll`/`la`/`lt` through eza with icons and git status, and Node versions from fnm that switch on `cd` into a folder with `.node-version` or `.nvmrc`.
- **Common changes:**
  - Prompt: edit `starship.toml`, e.g. `[directory] style = "bold blue"`, or add a module such as `$rust` to `format`. Colours are names from the `catppuccin_mocha` palette at the bottom.
  - Suggestion colour: `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#7f849c'` in `dotfiles.zsh`.
  - fzf colours: `FZF_DEFAULT_OPTS` in `dotfiles.zsh`; the Tab menu uses the same colours.
  - An alias or option: add it to `dotfiles.zsh` if it's safe to publish; anything private (keys, tokens, machine paths) goes in `~/.zshrc` outside the marker block.
  - 1Password variables: the `[data.opEnv]` table in your untracked `~/.config/chezmoi/chezmoi.toml` (name → `op://` ref), read into the shell by `home/dot_config/zsh/op-env.zsh.tmpl`. It works only when the service-account token is in `~/.config/harmony/op-sa-token`; see RUNBOOK section 11.
  - Syntax-highlighting colours: `catppuccin_mocha-zsh-syntax-highlighting.zsh` is vendored from Catppuccin (MIT, pinned commit in its header); edit it, or replace it with a newer copy and update the commit.
- **Try it:** `chezmoi apply`, then open a new tab (or `exec zsh`). `starship explain` shows what each prompt segment is.
- **Keep it:** `/codify` or `chezmoi edit ~/.config/zsh/dotfiles.zsh`. `/codify` also reports when the `~/.zshrc` source line is missing.
- **Reference:** https://starship.rs/config/, https://github.com/junegunn/fzf, https://github.com/Aloxaf/fzf-tab, https://github.com/ajeetdsouza/zoxide, https://github.com/Schniz/fnm

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

- **Where it lives:** `lib/claude-hooks.fragment.json` (the hooks we own), `home/dot_claude/hooks/executable_speak-alert.sh`, and the voice helpers in `home/dot_local/bin/`: `speak-kokoro` (local Kokoro TTS), `voice-cloud` (the cloud engine), `voice` (mute and status) and `dictate` (Linux push-to-talk). Your `settings.json` itself is never committed.
- **Common changes:**
  - Spoken phrase: when an agent finishes it says "All done. Ready for you."; when it needs you it speaks Claude's own reason (e.g. "Claude needs your permission to use Bash."). Edit the `case` block in `speak-alert.sh` to change either.
  - Engine: `SPEAK_ALERT_ENGINE` is `say` (the macOS default), `kokoro` (the Linux default: local Kokoro-82M, silent until its model is downloaded, see RUNBOOK section 5b; optional on macOS), `openai-compatible` (cloud, below) or `none`. Rendered alerts are cached in `~/.cache/speak-alert` (safe to delete), so a repeated line plays at once. They play through `afplay` on macOS and `paplay` on Linux.
  - Voice and speed: with `say`, the alert uses the first installed English Premium voice, falling back to your macOS system voice (Read & Speak → System voice, e.g. a Siri voice). List voices with `say -v '?'`. With Kokoro the voice is `af_heart`; others include `af_bella`, `bf_emma` and `am_michael`. With the cloud engine it's `alloy`. All engines use rate 120 words per minute (lower is slower). Kokoro and the cloud engine treat 150 as the voice's natural pace, so 120 is a calm 0.8×. Every alert starts after 800 ms of silence so the start isn't clipped; set `SPEAK_ALERT_LEAD_MS` to change that. Set `SPEAK_ALERT_VOICE` / `SPEAK_ALERT_RATE` (for example in your own lines of `~/.zshrc`), or change the defaults in `speak-alert.sh`.
  - Spoken summaries (opt-in, off by default): `touch ~/.config/speak-alert/summaries`. At the end of a turn you then hear the project name and the first one or two sentences of the reply (code, headings and links are dropped, and it is capped at about 220 characters) instead of the done line. With `SPEAK_ALERT_SUMMARIZER=claude`, Haiku writes that sentence through `claude -p` on your subscription, with hooks off, and falls back to the first-sentences version if it fails or takes longer than `SPEAK_ALERT_SUMMARY_TIMEOUT` (15 s). Codex replies go to Haiku only with `claude-all`. The summary is its own async `Stop` hook (`speak-alert.sh summary`). Mute, fleet workers and headless runs silence it like any alert.
  - Cloud engine (opt-in): any OpenAI-compatible speech server, hosted or one you run yourself (a Kokoro or Whisper server on your machine or network). Set `VOICE_CLOUD_URL` to its base URL including the version, e.g. `http://localhost:8880/v1`; there is no default server. Then use `SPEAK_ALERT_ENGINE=openai-compatible` for alerts and `DICTATE_ENGINE=openai-compatible` for dictation. Model names are `VOICE_CLOUD_TTS_MODEL` (`tts-1`) and `VOICE_CLOUD_STT_MODEL` (`whisper-1`). The API key is optional. Never commit it: the repo is public. The first place that has one wins: `VOICE_CLOUD_KEY`, the macOS Keychain (`security add-generic-password -s dotfiles-voice -a "$USER" -w`), the Linux desktop keyring through Secret Service, such as GNOME Keyring or KWallet (`secret-tool store --label='dotfiles voice' service dotfiles-voice`), then 1Password when `VOICE_CLOUD_OP_REF` names an item (e.g. `op://Private/voice/credential`). `voice-cloud key-source` says which one it found, never the key.
  - Mute and status: `voice mute`, `voice unmute`, `voice toggle` (for a key in any desktop, RUNBOOK section 4c) and `voice status` (engine and readiness, summaries, mute, cloud key source). Source: `home/dot_local/bin/executable_voice`.
  - Dictation (Linux): `dictate`, on a key you bind in your desktop: GNOME, KDE, a tiling window manager or any other (RUNBOOK section 4c). `DICTATE_PROMPT` lists words whisper should expect, `DICTATE_MODEL` picks the ggml model (default `~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin`), and `DICTATE_LANG` sets the language (`en`). On macOS, VoiceInk is the push-to-talk; set it up in its own settings.
  - Which events speak: add or remove `Stop` / `Notification` entries in the fragment. A notification speaks only for permission, idle, elicitation and needs-input prompts (`notification_type`); others, such as `auth_success`, stay silent. Edit that `case` in `speak-alert.sh` to change it.
  - Theme colours: `home/dot_claude/themes/catppuccin-mocha.json`. Inline code and commands use the `permission` token, e.g. `"permission": "#a6e3a1"` for green. Edits reload live. Pick the theme with `/theme` (stored in `~/.claude.json`, not tracked).
  - Rich view of replies: run `/lastreply` in Claude Code (or `lastreply --open`) to open a herdr split that renders each reply of that session with glow. In a split you opened yourself, `lastreply --watch` follows the agent in the same herdr tab (`--session <id>` to pin one, `--codex` for Codex, `--raw` for plain markdown). Source: `home/dot_local/bin/executable_lastreply`.
  - Skills: `/lastreply` and `/codify` come from one shared source each in `home/.chezmoitemplates/skills/`, installed for Claude (`home/dot_claude/skills/`) and Codex (`home/dot_agents/skills/`). Edit the shared file, not the per-tool `SKILL.md.tmpl`.
- **Try it:** `chezmoi apply` merges the fragment into `~/.claude/settings.json`, with a backup the first time it changes.
- **Keep it:** commit the repo change. Never hand-edit our hooks in `settings.json`; `/codify` reports when that has happened.
- **Reference:** https://docs.claude.com/en/docs/claude-code/hooks

## Codex

- **Where it lives:** `lib/codex-owned-keys.txt` (the few settings we own, one `<table> <key> <value>` per line), applied by `home/.chezmoiscripts/run_onchange_after_30-codex-settings.sh.tmpl`. Your `~/.codex/config.toml` itself is never committed; it can hold connector tokens.
- **Common changes:**
  - Theme: `tui theme "catppuccin-mocha"` sets Codex's built-in syntax-highlighting theme; any built-in name works, e.g. `"dracula"`.
  - Another owned setting: add a line such as `tui animations false`.
  - Review pane: `$lastreply` in Codex (or `lastreply --open` in a Codex shell) opens the same glow pane, pinned to that Codex session through `$CODEX_THREAD_ID`. It shows Codex's final answer, not its progress notes.
  - Skills: `$codify` and `$lastreply`, from the shared sources above.
- **Try it:** `chezmoi apply`. The first change backs up the file to `~/.codex/config.toml.bak-dotfiles`.
- **Keep it:** commit the repo change. `/codify` reports when an owned Codex setting has been changed by hand.
  - Spoken alerts and the drift notice: `lib/codex-hooks.fragment.json`, merged into `~/.codex/hooks.json` beside your own hooks. They say "All done. Ready for you." when a turn finishes and "Codex needs your permission to use <tool>." on an approval request; headless `codex exec` runs and fleet workers stay silent. Each `statusMessage` is the name `/hooks` shows.
- **Approve hooks:** Codex runs a new or changed hook only after you approve it in `/hooks`, so after editing the fragment, approve again.
- **Check alerts:** `tail ~/.local/state/speak-alert/events.log` shows what each alert decided (spoke, or silent and why).
- **Linux:** alerts use local Kokoro once its model is downloaded (RUNBOOK section 5b). Until then the log says `silent: no speech backend`. Summaries come from Codex's own `Stop` hook (`codex-summary`) when the summaries file exists.

## Agent plugins (crew)

- **Where it lives:** `lib/agent-plugins.txt` lists the plugins kept installed at user scope for Claude Code, Codex and pi: crew and its four packs (`infra-skills`, `planning-skills`, `identity-skills`, `language-skills`) from the `pixeloven` marketplace (github.com/pixeloven/marketplace). `lib/agent-plugins.sh` does the work; `home/.chezmoiscripts/run_after_60-agent-plugins.sh.tmpl` runs its `ensure` on every `chezmoi apply`.
- **What it does:** for each tool that is installed, it adds the marketplace if needed and installs only the plugins that are missing. Claude Code and Codex install from the marketplace after refreshing their clone of it (or from that clone as it is, which may be behind, when offline); pi installs each one as `git:github.com/pixeloven/<name>@<sha>`, at the commit SHA in a freshly fetched catalogue (this machine's local copy, which may be behind, when offline). A tool installed later gets the plugins at the next `chezmoi apply`. On pi you get crew's skills and its readable roles; there is no in-session dispatch there (orchestrate from the operator instead).
- **A plugin you disable stays disabled:** an installed plugin is never re-installed, because `claude plugin install` and `codex plugin add` would turn it back on. `update` skips it too, and `/codify` doesn't report it.
- **Common changes:**
  - Add or drop a plugin: edit `lib/agent-plugins.txt`, then `chezmoi apply`. Dropping a name stops managing it; uninstall it yourself if you want it gone.
  - New versions: they arrive only when a reviewed re-pin merges in the marketplace. Then run `~/Development/dotfiles/lib/agent-plugins.sh update`, which brings Claude Code, Codex and pi to the catalogue's pins together. Claude's own auto-update for the marketplace stays off.
  - Opt a machine out: `agentPlugins = false` under `[data]` in your untracked `~/.config/chezmoi/chezmoi.toml`. Nothing is installed or reported then; already installed plugins stay.
  - Operator home: with `operatorHome` set, `home/.chezmoiscripts/run_onchange_after_61-operator-crew-fence.sh.tmpl` runs that home's own `bin/po-crew.sh fence`, which keeps crew out of the operator home's own sessions. It skips until the home has that script.
- **Try it:** `chezmoi apply`, then `~/Development/dotfiles/lib/agent-plugins.sh check`; it prints nothing when every tool is at the pins.
- **Keep it:** commit the repo change. `/codify` reports `plugin-missing` (run `chezmoi apply`) and `plugin-behind` (the installed commit differs from this machine's local catalogue copy; run `lib/agent-plugins.sh update`). The check stays offline, so it doesn't see a re-pin newly published in the marketplace: the operator's crew check finds that on demand, and `lib/agent-plugins.sh update` fetches the catalogue and applies it.

## bat, delta, glow

- **Where they live:** `home/dot_config/bat/config`, `home/.chezmoitemplates/glow.yml` (installed to `~/Library/Preferences/glow/glow.yml` on macOS and `~/.config/glow/glow.yml` on Linux), the glow style `home/dot_config/glow/catppuccin-mocha.json`, and the git keys in `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh`
- **Common changes:**
  - bat theme: `--theme="Catppuccin Macchiato"` (list: `bat --list-themes`).
  - Side-by-side diffs: in the gitconfig script, `git config --global delta.side-by-side true`.
  - delta theme: `git config --global delta.syntax-theme "Dracula"` (list: `delta --list-syntax-themes`).
  - glow width: `width: 120`.
  - glow colours: edit `catppuccin-mocha.json`, e.g. inline code `"code": {"color": "#a6e3a1"}` for green. `lastreply` uses the same style.
- **Try it:** run `chezmoi apply`, then `bat README.md`, `git diff` or `glow README.md`.
- **Keep it:** `/codify`. A git key changed by hand shows up as owned-key drift; put the new value in the script.

## Operator persona (optional, off by default)

- **Where it lives:** the chezmoi data key `operatorPersona`, set by hand in your untracked `~/.config/chezmoi/chezmoi.toml` (chezmoi never asks for it), applied by `home/.chezmoiscripts/run_onchange_after_50-operator-persona.sh.tmpl` through `lib/operator-persona.sh`. Unset, nothing happens.
- **Turn it on:**
  ```toml
  [data]
  operatorPersona = "operator"                 # a theme name, e.g. nautical or operator
  operatorHome = "~/Development/operator"      # optional; this is the default
  ```
- **What it does:** when the operator home exists, has an executable `bin/po-theme.sh` and is not a secondmate home (`.fm-secondmate-home`), it runs `po-theme.sh validate <name>`, writes the name as the first line of `config/po-theme` only if it differs, then runs `po-theme.sh apply` and `verify`. Anything else is skipped with a message. Dotfiles never writes the operator's `data/` or alias files; `po-theme.sh` stays their only writer.
- **Try it:** `chezmoi apply` (it re-runs whenever the key or home changes).
- **Keep it:** the key lives only in your local chezmoi config. If the theme is later switched another way, `/codify` reports `config/po-theme` as an owned-key change; set `operatorPersona` to match, or run the `lib/operator-persona.sh <name> <home>` command it suggests to switch back (`chezmoi apply` alone does not re-run it until the key or home changes). To stop managing it, remove the key.

## Packages

- **Where they live:** `Brewfile`
- **Add:** `brew install <name>` (or `--cask`), then `/codify` and keep it. Or add the line to the Brewfile and run `chezmoi apply`.
- **Don't track:** choose "skip" in `/codify`, which adds the name to `lib/drift-ignore.txt`.
- **Remove:** delete the line, then `brew uninstall <name>`.

## Undo a change

1. `chezmoi diff`: see how the machine differs from the repo.
2. `git -C ~/Development/dotfiles revert <commit>`: undo a recorded change.
3. `chezmoi apply`: put the machine back in line with the repo.
