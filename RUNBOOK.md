# Runbook: manual steps

Steps that scripts can't do, or that macOS asks you to approve yourself. Each one ends with a **Done when** check.

## 1. New Mac bootstrap

1. Install Homebrew and chezmoi, then run `chezmoi init --apply` (see README). This installs everything in the Brewfile.
2. Install herdr from https://herdr.dev. It installs itself into `~/.local/bin` and updates with `herdr update`.
3. Run `herdr integration install claude` (and `herdr integration install pi` if you use Pi).
4. In the repo, enable the secret guard: `git -C ~/Development/dotfiles config core.hooksPath .githooks`.
5. Do steps 2–4 of this runbook.

**Done when:** `bats ~/Development/dotfiles/tests/` passes.

## 2. macOS permissions for Ghostty

1. System Settings → Notifications → Ghostty: turn on **Allow notifications**.
2. System Settings → Privacy & Security → Accessibility: turn on **Ghostty**. The global `cmd+`` drop-down terminal needs this.
3. Quit and reopen Ghostty.

**Done when:** `sleep 35` in a Ghostty tab you then switch away from posts a notification, and `cmd+`` opens the drop-down terminal from any app.

## 3. Claude Code theme

1. In Claude Code, run `/theme` and pick the dark theme. That choice is stored in `~/.claude.json`, which this repo never tracks.

**Done when:** Claude Code's colours sit comfortably on Ghostty's Catppuccin background.

## 4. Dictation

Option A, nothing to install:
1. System Settings → Keyboard → Dictation: turn **on**, and set the shortcut to **Press 🌐 twice** (Fn twice).

Option B, better with technical words:
1. Install Superwhisper (https://superwhisper.com) or Wispr Flow.
2. Pick a local English model and set a push-to-talk key.
3. Turn on "paste into the active app".

**Done when:** speaking into a Claude Code prompt inside herdr types the text.

## 5. Spoken alerts: better voice, on and off

Better voice (free, on-device; the alert picks it up automatically):
1. System Settings → Accessibility → Spoken Content → System voice → **Manage Voices…**
2. Under English, download a **(Premium)** voice, e.g. Zoe, Ava or Evan (about 300 MB each).
3. Check it's installed: `say -v '?' | grep Premium`.

- Off: `touch ~/.config/speak-alert/muted`
- On: `rm ~/.config/speak-alert/muted`
- Pick a specific voice or speed: `export SPEAK_ALERT_VOICE="Ava (Premium)" SPEAK_ALERT_RATE=190`. List voices with `say -v '?'`.

**Done when:** a Claude Code reply ends and you hear "<folder> finished", or nothing while muted.

## 6. Optional tactical shader

1. Download a scanline/CRT shader (e.g. from https://github.com/hackr-sh/ghostty-shaders) to `~/.config/ghostty/shaders/crt.glsl`.
2. In `~/.config/ghostty/config.ghostty`, uncomment `custom-shader = shaders/crt.glsl`.
3. Reload Ghostty with `cmd+shift+,`.
4. Like it? Run `/codify` to keep both files. If you don't like it or the fans spin up, re-comment the line.

**Done when:** the effect shows and `/codify` has recorded it, or you've reverted it.

## 7. Inline images check (herdr Kitty graphics)

1. `brew install chafa`, then inside a herdr pane run `chafa --format=kitty <some.png>`.
2. If no image appears or panes glitch, set `kitty_graphics = false` under `[experimental]` in the herdr config, run `herdr server reload-config`, and then `/codify`.

**Done when:** you see the image, or graphics are turned off and that change is codified.
