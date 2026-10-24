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

1. Restart Claude Code once after the first `chezmoi apply`, so it sees `~/.claude/themes/`.
2. Run `/theme` and pick **Catppuccin Mocha**. That choice is stored in `~/.claude.json`, which this repo never tracks.

**Done when:** inline code and commands show in peach and your own messages sit on a slightly lighter band.

## 4. Dictation

Option A, nothing to install:
1. System Settings → Keyboard → Dictation: turn **on**, and set the shortcut to **Press 🌐 twice** (Fn twice).

Option B, better with technical words:
1. Install Superwhisper (https://superwhisper.com) or Wispr Flow.
2. Pick a local English model and set a push-to-talk key.
3. Turn on "paste into the active app".

**Done when:** speaking into a Claude Code prompt inside herdr types the text.

## 5. Premium voice for spoken alerts

macOS's free Premium voices are on-device and far more natural than the default. They can't be downloaded from a script. Once one is installed, the alert uses it automatically.

1. Open **System Settings → Accessibility → Read & Speak**. In macOS 26 this panel replaced "Spoken Content"; on macOS 15 and earlier it's still called Spoken Content. Shortcut: type `System voice` in the Settings search box.
2. Next to **System voice**, click the ⓘ (or the menu) → **Manage Voices…**
3. Expand **English**, then click the download icon next to **Zoe (Premium)**, which is the recommended voice. Ava (Premium) and Evan (Premium) are good alternatives. Each is about 300–500 MB.
4. Wait for the download to finish. You don't need to change the system voice itself.
5. Check: `say -v '?' | grep Premium` lists the voice.
6. Listen: `say -v "Zoe (Premium)" -r 120 "All done. Ready for you."`.

Until a Premium voice is installed, alerts use your macOS **System voice** (e.g. a Siri voice), which is already decent. If several Premium voices are installed, the alert uses the first one alphabetically. To pin one, set `SPEAK_ALERT_VOICE="Zoe (Premium)"`, or change the default in `speak-alert.sh` (see CUSTOMIZE.md).

On and off:
- Off: `touch ~/.config/speak-alert/muted`
- On: `rm ~/.config/speak-alert/muted`

**Done when:** a Claude Code reply ends and you hear "All done. Ready for you." in your chosen voice, or nothing while muted.

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
