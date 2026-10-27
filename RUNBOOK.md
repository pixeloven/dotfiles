# Runbook: manual steps

Steps that scripts can't do, or that the OS asks you to approve yourself. Each one ends with a **Done when** check. A new Linux machine starts at section 9 instead of section 1.

## 1. New Mac bootstrap

1. Install Homebrew and chezmoi, then run `chezmoi init --apply` (see README). It asks once whether to install the ops tools (kubectl, helm, argocd, talosctl, omnictl, terraform, ansible, docker CLI; default no), then installs everything in the Brewfile natively.
2. Install herdr from https://herdr.dev. It installs itself into `~/.local/bin` and updates with `herdr update`.
3. Run `herdr integration install claude` (and `herdr integration install pi` if you use Pi).
4. In the repo, enable the secret guard: `git -C ~/Development/dotfiles config core.hooksPath .githooks`.
5. Shell: install oh-my-zsh keeping the `~/.zshrc` chezmoi wrote (`sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc`), then Node through fnm: `fnm install 22 && fnm default 22`, and in a new tab reinstall the global npm tools listed in step 8. Without oh-my-zsh, `dotfiles.zsh` still loads with plain completion. After installing Claude Code and the npm tools (Codex, pi), run `chezmoi apply` again so they get crew and its packs.
6. Git identity, by hand, because dotfiles never sets it: `git config --global user.name "Your Name"` and `git config --global user.email you@example.com`. Optionally, add a separate PixelOven identity as in section 9a step 7.
7. Do steps 2–4 of this runbook.

**Done when:** `bats ~/Development/dotfiles/tests/` passes and `~/Development/dotfiles/lib/agent-plugins.sh check` prints nothing.

## 2. macOS permissions for Ghostty

macOS only.

1. System Settings → Notifications → Ghostty: turn on **Allow notifications**.
2. System Settings → Privacy & Security → Accessibility: turn on **Ghostty**. The global `cmd+`` drop-down terminal needs this.
3. Quit and reopen Ghostty.

**Done when:** `sleep 35` in a Ghostty tab you then switch away from posts a notification, and `cmd+`` opens the drop-down terminal from any app.

## 3. Claude Code theme

1. Restart Claude Code once after the first `chezmoi apply`, so it sees `~/.claude/themes/`.
2. Run `/theme` and pick **Catppuccin Mocha**. That choice is stored in `~/.claude.json`, which this repo never tracks.

**Done when:** inline code and commands show in peach and your own messages sit on a slightly lighter band.

## 4. Dictation

There are two layers, on both OSes: Claude Code's own `/voice` for Claude Code prompts, and one global push-to-talk key for everything else (Codex, a shell, any herdr pane). Neither needs root, uinput or an input daemon, and neither is tied to one desktop.

### 4a. Claude Code `/voice` (hold Space)

`/voice` streams your speech to Anthropic for transcription. That uses no messages or tokens, but it needs a Claude.ai login, not an API key. Dotfiles never turns it on for you.

1. *Both OSes.* In Claude Code, run `/voice hold`. Then hold **Space** while you speak and let go to stop. `/voice tap` toggles instead, and `/voice off` turns it off. The setting is stored in your untracked `~/.claude/settings.json`.
2. *Optional.* To skip the short warmup of a held Space, bind a modifier combo in `~/.claude/keybindings.json`: `voice:pushToTalk` in the `Chat` context, for example `meta+k`.
3. *macOS.* There's nothing to install. Allow microphone access for your terminal when macOS asks.
4. *Linux distrobox (and a Linux host without ALSA tools).* Claude Code records through ALSA (`arecord`, or SoX `rec`). The box sees `/dev/snd`, but nothing routes ALSA to the desktop's PipeWire. Inside the box, run `sudo apt-get install -y alsa-utils pipewire-alsa`. This installs into the box only. Don't add `~/.asoundrc`, because the box shares your home with the host.
   **Done when:** `arecord -l` lists a capture device, and `arecord -d 3 -f S16_LE -r 16000 /tmp/voice-check.wav` records three seconds into a file larger than 44 bytes.
   If Claude Code ends up using SoX, also run `sudo apt-get install -y sox libsox-fmt-pulse`.

**Done when:** holding Space in a Claude Code prompt and speaking types the text.

### 4b. Global push-to-talk

*macOS.* VoiceInk (from the Brewfile) does on-device transcription with local Whisper or Parakeet models and custom words.
1. Open VoiceInk, download a local model (Parakeet or Whisper large-v3-turbo), and allow Microphone and Accessibility access.
2. Set its shortcut, for example a held Right Option, and turn on pasting into the active app.
3. Superwhisper and Wispr Flow are paid alternatives. Apple Dictation (System Settings → Keyboard → Dictation, **Press 🌐 twice**) needs nothing installed.

*Linux.* `dictate` (`~/.local/bin/dictate`) is a toggle. The first press starts recording. The second press stops it, transcribes locally with whisper.cpp (from the Brewfile), and types the text into herdr's focused pane: Claude Code, Codex or a shell. If herdr isn't running, or no pane has focus, the text goes to the clipboard with a notification.
1. Download the speech model (about 550 MB) where you run tools. In a distrobox setup, that's inside the box:
   ```sh
   mkdir -p ~/.local/share/whisper
   curl -fL -o ~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
   ```
   **Done when:** `whisper-cli --help` prints its usage, and running `dictate` twice in a herdr pane types what you said into that pane.
2. Bind `dictate` to one key in your desktop: see section 4c. It works the same on any desktop.
   **Done when:** with a herdr pane focused, pressing the key shows "Listening…", and after you speak, pressing it again types your words into that pane.
3. *Optional.*
   - `DICTATE_PROMPT` lists words to expect, such as repo and tool names.
   - `DICTATE_MODEL` points at another ggml model.
   - `dictate --cancel` throws a recording away.
   - For the cloud engine, see CUSTOMIZE.md.

### 4c. Bind the keys (any desktop)

`dictate` (Linux) and `voice toggle` (mute on or off, both OSes) are plain commands. Bind each one to a key wherever your desktop lets you run a command on a key. Nothing here needs GNOME, and dotfiles never changes desktop settings for you. Pick keys that are free; Ctrl+Alt+D (dictate) and Ctrl+Alt+M (mute) are the suggestion.

The command to bind:

| Trigger | Linux distrobox | Linux host | macOS |
|---|---|---|---|
| Dictate | `sh -c 'distrobox enter ubuntu-dev -- "$HOME/.local/bin/dictate"'` | `sh -c '"$HOME/.local/bin/dictate"'` | VoiceInk's own key (4b) |
| Mute toggle | `sh -c '"$HOME/.local/bin/voice" toggle'` | `sh -c '"$HOME/.local/bin/voice" toggle'` | `~/.local/bin/voice toggle` |

The mute toggle needs only a shell, so it runs on a distrobox's host directly: the box shares your home and its mute file. Settings for `dictate`, such as `DICTATE_PROMPT`, go in its command, for example `sh -c 'distrobox enter ubuntu-dev -- env DICTATE_PROMPT="pixeloven, Bazzite" "$HOME/.local/bin/dictate"'`.

Where to bind it:
- **GNOME:** Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts → **+**, with a name, the command and the key. Optional, from a terminal on the host when `echo "$XDG_CURRENT_DESKTOP"` says GNOME, the same thing for dictate. Its first command replaces your list of custom shortcuts, so if `gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings` already lists paths, keep them in the new list:
  ```sh
  p=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/dictate/
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$p']"
  s="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p"
  gsettings set "$s" name 'Dictate into herdr'
  gsettings set "$s" binding '<Control><Alt>d'
  gsettings set "$s" command "sh -c 'distrobox enter ubuntu-dev -- \"\$HOME/.local/bin/dictate\"'"
  ```
- **KDE Plasma:** System Settings → Keyboard → Shortcuts → **Add New** → **Command or Script**, paste the command, then set the key.
- **Sway or i3:** in the config, `bindsym Ctrl+Mod1+d exec sh -c '"$HOME/.local/bin/dictate"'`, then reload.
- **Hyprland:** `bind = CTRL ALT, D, exec, sh -c '"$HOME/.local/bin/dictate"'`.
- **Other desktops** (Xfce, Cinnamon, MATE and others): the keyboard settings' application or custom shortcuts take the same command.
- **macOS:** in the Shortcuts app, make a shortcut with a **Run Shell Script** action containing `~/.local/bin/voice toggle`. In its details, choose **Add Keyboard Shortcut**.

Desktop shortcuts fire on key press only, so both are toggles, not hold-to-talk.

**Done when:** each key works from any app: the mute key shows "Voice muted" and then "Voice unmuted", and `voice status` agrees.

## 5. Voice for spoken alerts

### 5a. macOS: Premium voice

macOS's free Premium voices run on-device and sound far more natural than the default. They can't be downloaded from a script. Once one is installed, the alert uses it automatically.

1. Open **System Settings → Accessibility → Read & Speak**. In macOS 26 this panel replaced "Spoken Content"; on macOS 15 and earlier it's still called Spoken Content. Shortcut: type `System voice` in the Settings search box.
2. Next to **System voice**, click the ⓘ (or the menu) → **Manage Voices…**
3. Expand **English**, then click the download icon next to **Zoe (Premium)**, which is the recommended voice. Ava (Premium) and Evan (Premium) are good alternatives. Each is about 300–500 MB.
4. Wait for the download to finish. You don't need to change the system voice itself.
5. Check: `say -v '?' | grep Premium` lists the voice.
6. Listen: `say -v "Zoe (Premium)" -r 120 "All done. Ready for you."`.

Until a Premium voice is installed, alerts use your macOS **System voice** (e.g. a Siri voice), which is already decent. If several Premium voices are installed, the alert uses the first one alphabetically. To pin one, set `SPEAK_ALERT_VOICE="Zoe (Premium)"`, or change the default in `speak-alert.sh` (see CUSTOMIZE.md). Kokoro (5b) is optional on macOS: set `SPEAK_ALERT_ENGINE=kokoro` and download its model.

### 5b. Linux: Kokoro, a local voice

On Linux, alerts use Kokoro-82M, an open voice model that runs on the CPU. It renders a WAV file, which `paplay` plays on the desktop's PipeWire, also from a distrobox. Until the model is downloaded, alerts stay silent and the log says `silent: no speech backend`.

1. Download the model files (about 340 MB) where you run tools. In a distrobox setup, that's inside the box:
   ```sh
   mkdir -p ~/.local/share/kokoro
   curl -fL -o ~/.local/share/kokoro/kokoro-v1.0.onnx \
     https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
   curl -fL -o ~/.local/share/kokoro/voices-v1.0.bin \
     https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
   ```
   `kokoro-v1.0.int8.onnx` (about 90 MB) is a smaller alternative: point `SPEAK_KOKORO_MODEL` at it.
2. Warm it up once. uv fetches the Python packages on the first run, which takes a minute: `speak-kokoro --out /tmp/kokoro-check.wav "All done. Ready for you."`.
   **Done when:** `/tmp/kokoro-check.wav` exists, and `paplay /tmp/kokoro-check.wav` speaks the line.

### 5c. Both OSes: on and off, summaries

- Mute: `voice mute`, and `voice unmute` to hear alerts again. `voice toggle` flips it and shows a notification, so it suits a key (section 4c). Mute covers alerts and summaries for Claude Code and Codex. It is the file `~/.config/speak-alert/muted`, so `touch` and `rm` on that file work too.
- `voice status` shows the engine and whether it's ready, whether summaries are on, whether voice is muted, and where a cloud key would come from (never the key).
- Spoken summaries, opt-in: `touch ~/.config/speak-alert/summaries`. At the end of a turn, you hear the project name and the first sentence or two of the reply instead of "All done. Ready for you.". Mute still silences everything. Fleet workers and headless runs stay silent. Undo with `rm ~/.config/speak-alert/summaries`. Codex runs the new hooks only after you approve them in `/hooks`.
- `tail ~/.local/state/speak-alert/events.log` shows what each alert decided.

**Done when:** a Claude Code reply ends and you hear "All done. Ready for you." (or the summary) in your chosen voice, or nothing while muted.

## 6. Optional tactical shader

1. Download a scanline/CRT shader (e.g. from https://github.com/hackr-sh/ghostty-shaders) to `~/.config/ghostty/shaders/crt.glsl`.
2. In `~/.config/ghostty/config.ghostty`, uncomment `custom-shader = shaders/crt.glsl`.
3. Reload Ghostty with `cmd+shift+,` (`ctrl+shift+,` on Linux).
4. Like it? Run `/codify` to keep both files. If you don't like it or the fans spin up, re-comment the line.

**Done when:** the effect shows and `/codify` has recorded it, or you've reverted it.

## 7. Inline images check (herdr Kitty graphics)

1. `brew install chafa`, then inside a herdr pane run `chafa --format=kitty <some.png>`.
2. If no image appears or panes glitch, set `kitty_graphics = false` under `[experimental]` in the herdr config, run `herdr server reload-config`, and then `/codify`.

**Done when:** you see the image, or graphics are turned off and that change is codified.

## 8. One-time `~/.zshrc` cleanup and the nvm → fnm switch

For a Mac set up before the zsh config existed. Linux machines never had nvm; section 9 sets up fnm directly. `~/.zshrc` is never tracked: it holds an API key and the pnpm and antigravity PATH lines. Afterwards it keeps only those private lines plus the `# >>> dotfiles >>>` block that sources `~/.config/zsh/dotfiles.zsh`, which now loads oh-my-zsh (trimmed), the plugins, fnm and Starship.

1. Back up: `cp ~/.zshrc ~/.zshrc.bak-$(date +%Y%m%d)`.
2. `chezmoi apply`. It writes `~/.config/zsh/`, `~/.config/starship.toml` and the Ghostty font, and appends the marker block to `~/.zshrc`.
3. Edit `~/.zshrc` by hand and delete the oh-my-zsh lines (`export ZSH=…`, `ZSH_THEME=…`, `plugins=(git)`, `source $ZSH/oh-my-zsh.sh` and the commented template around them) and the three nvm lines (`export NVM_DIR=…` and the two `[ -s "$NVM_DIR/…" ]` lines). Keep the API key, the pnpm and antigravity lines and the marker block. Don't edit inside the block.
4. Record the global npm tools while nvm's Node is still active: `npm ls -g --depth=0`. At the time of the plan (`docs/plans/2026-10-24-zsh-setup.md`) these were, under Node 22.23.2: `@openai/codex@0.164.0`, `@earendil-works/pi-coding-agent@0.87.1`, `gh-axi@0.1.43`, `tasks-axi@0.2.6`, `quota-axi@0.1.66`, `lavish-axi@0.1.90`, `chrome-devtools-axi@0.1.44`, `gnhf@0.1.44`. Use the versions the command prints; they move.
5. Open a new tab, then `fnm install 22.23.2 && fnm default 22.23.2`, open another new tab, and `npm install -g` each tool at the version you recorded.
6. Verify in a fresh tab: `which node` points under fnm (not `~/.nvm`), and each tool resolves and runs, e.g. `codex --version`, `gh-axi --version`, `pi --version`. Check that Codex hooks and the fleet still find `gh-axi` and the other `-axi` tools.
7. Restart running Claude Code and Codex sessions; they keep their old PATH until restarted.

**Keep `~/.nvm` only until the operator's remote jobs know fnm.** Its one remaining use: the operator repo's `bin/fm-remote-job-lib.sh` builds remote-job PATHs from nvm's default Node and doesn't look for fnm yet. A fix that teaches it fnm has been sent upstream. Until that lands, leave `~/.nvm` untouched (it is also the rollback below) and upgrade both Node installs when it matters, since they drift apart. Once it lands and a remote job finds `node` without nvm, `rm -rf ~/.nvm`.

**Roll back:** `cp ~/.zshrc.bak-<date> ~/.zshrc` and open a new tab; nvm and the old prompt are back.

**Done when:** a new Ghostty tab shows the Starship prompt with icons, grey suggestions appear as you type, Ctrl+R, the Tab menu, `z` and `ls` work, `which node` is under fnm, every tool above prints its version, and `drift` reports no `~/.zshrc` finding.

## 9. New Linux bootstrap (on the host, or in a distrobox)

On Linux, `chezmoi init` asks once where tools install (`installTarget`). Each step below says which of the two setups it applies to; macOS uses section 1 instead.

- **Linux host** (`host`, the default): everything installs on the main OS, as on a Linux server or any machine where you want the host's own Homebrew, an image-based one included. Do 9a steps 2–9 on the machine itself. 9b–9d don't apply, and no-mistakes keeps its managed service.
- **Linux distrobox** (`distrobox`, suggested on an image-based host such as Bazzite, and in a box on one): tools install only inside an Ubuntu distrobox named `ubuntu-dev`. Do all of section 9: for a new machine 9a then 9b; for an existing box 9b, and 9d for what already reached the host; for a rebuild 9c, then 9d if you haven't yet.

On both OSes `chezmoi init` also asks whether to install the ops tools (`opsTools`, default no): kubectl, helm, argocd, talosctl, omnictl, terraform (HashiCorp's tap), ansible and the docker CLI. Each answer is asked once and kept in `~/.config/chezmoi/chezmoi.toml`; to change one, delete its line there and run `chezmoi init` again. `chezmoi apply` never asks, so a machine set up before these questions keeps the defaults until you run `chezmoi init --source ~/Development/dotfiles pixeloven` once (in a box, from inside it); 9b step 1 does this for an existing box.

With `distrobox`: the box shares the host's `$HOME` (distrobox mounts it even with `--home`), so `~/.zshrc`, `~/.gitconfig`, `~/.oh-my-zsh`, `~/.local/bin`, fnm's Node, `~/Development`, `~/.no-mistakes`, chezmoi's config and the agents' sign-ins are the same files on both sides and survive a rebuild. Each side has its own Homebrew at `/home/linuxbrew/.linuxbrew`; the box's lives in the container and goes with it. Tools go in the box only: don't install anything with the host's `brew`, and use `distrobox-host-exec` only for the Ptyxis palette and read-only checks. On the host, chezmoi's Brewfile step skips itself (outside a container). The validation pipeline (no-mistakes) runs inside the box too (9b). Run every distrobox step inside the box unless it says host.

### 9a. Build the machine or the box

1. *Linux distrobox.* On the host, create the box from the tracked file: `distrobox assemble create --file ~/Development/dotfiles/lib/distrobox/ubuntu-dev.ini` (Ubuntu 24.04 with zsh and Homebrew's build tools, the shared home, no GPU). Then `distrobox enter ubuntu-dev`.
   **Done when:** inside the box, `echo $CONTAINER_ID` prints `ubuntu-dev`, `echo $HOME` prints your host home, and `/run/.containerenv` exists.
2. *Both Linux setups.* zsh as the login shell: `sudo chsh -s /usr/bin/zsh "$USER"`. In a box this edits only the box's `/etc/passwd` and the host keeps its shell; on a Linux host, install zsh with the system package manager first.
   **Done when:** in a new login (in a box: after `exit` and `distrobox enter ubuntu-dev` again), `ps -p $$ -o comm=` prints `zsh` and `which node` is not `/usr/bin/node` (Homebrew sits ahead of the system dirs, except on an image-based host, where it stays last).
3. *Both Linux setups.* Homebrew and chezmoi: the Homebrew installer from the README, then `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` for this shell only (don't add it to `~/.bashrc`, which the host reads too; `dotfiles.zsh` finds brew itself), `brew install chezmoi` and `chezmoi init --apply --source ~/Development/dotfiles pixeloven`. Answer `host` or `distrobox` to match your setup (in a box, `distrobox`), and say yes to the ops tools if you want them.
   **Done when:** `brew bundle check --file ~/Development/dotfiles/Brewfile` says the dependencies are satisfied; with the ops tools, `kubectl version --client` and `terraform version` print versions; and, in a box, `distrobox-host-exec /home/linuxbrew/.linuxbrew/bin/brew leaves` (the host's Homebrew) gained nothing.
4. *Both Linux setups.* oh-my-zsh, keeping the `~/.zshrc` chezmoi wrote: `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc`. On a box rebuild, skip it: it lives in the shared home.
   **Done when:** `~/.oh-my-zsh/oh-my-zsh.sh` exists and a new zsh shows the Starship prompt with grey suggestions as you type.
5. *Both Linux setups.* Node through fnm: `fnm install 22 && fnm default 22` (the Mac's major), open a new shell, and `npm install -g` the global tools (`chrome-devtools-axi`, `gh-axi`, `quota-axi`, `tasks-axi`). Install Claude Code, Codex and herdr with their own installers (they land in `~/.local/bin`), run `herdr integration install claude`, then `chezmoi apply` again so they get crew and its packs. On a box rebuild all of this is already in the shared home.
   **Done when:** in a new shell `which node` is under fnm, `gh-axi --version` and `herdr --version` print versions, and `~/Development/dotfiles/lib/agent-plugins.sh check` prints nothing.
6. *Both Linux setups.* Git identity, by hand, because dotfiles never sets it: `git config --global user.name "Your Name"` and `git config --global user.email you@example.com`.
   **Done when:** `git config user.name` and `git config user.email` print your values.
7. *Both Linux setups, optional.* If you want a separate identity for PixelOven repos, set it by hand. Write `~/.gitconfig-pixeloven` containing `[user]` and `email = <your GitHub noreply address>`, then add to `~/.gitconfig`:
   ```ini
   [includeIf "hasconfig:remote.*.url:https://github.com/pixeloven/**"]
       path = ~/.gitconfig-pixeloven
   [includeIf "hasconfig:remote.*.url:git@github.com:pixeloven/**"]
       path = ~/.gitconfig-pixeloven
   ```
   It needs git 2.36 or later, and it also covers the no-mistakes gate repos under `~/.no-mistakes/repos`, whose remotes are github.com/pixeloven URLs. Merges made on the GitHub website use the account's commit email instead; if you want those private too, Settings → Emails → "Keep my email addresses private" makes them use the noreply address.
   **Done when** (if you did this step): `git -C ~/Development/dotfiles config user.email` prints the noreply address and a non-PixelOven repo still prints the global one.
8. *Both Linux setups.* The repo's secret guard (`git -C ~/Development/dotfiles config core.hooksPath .githooks`) and section 3, if this `$HOME` hasn't had them yet.
   **Done when:** `git -C ~/Development/dotfiles config core.hooksPath` prints `.githooks`, `fc-list | grep -q 'JetBrainsMono Nerd Font'` succeeds, and text you select in a herdr pane pastes into a host app with `ctrl+v` (herdr copies through the Brewfile's `wl-copy`/`xclip` when the terminal ignores OSC 52, as Ptyxis does).
9. *Both Linux setups, optional, with the ops tools.* The Brewfile installs only the docker CLI, not an engine; point it at one. On a Linux host, use an engine running there. In a box there is none: point it at the host's podman by adding `export DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock` to your own lines in `~/.zshrc` (outside the dotfiles block). Those containers then run on the host, a deliberate crossing, which is why dotfiles doesn't set it.
   **Done when** (if you did this step): `docker ps` prints a header and no error.

**Done when:** every check above that applies passes and `bats ~/Development/dotfiles/tests/` passes (in a box, inside it).

### 9b. Move the validation daemon into the box

*Linux distrobox only.* One time per machine, with or without a rebuild. The box's `systemctl --user` is the host's (distrobox shares `/run/user/$UID`), so `no-mistakes daemon start` from the box installed its daemon as a host systemd unit. Its pipelines then ran on the host with the host's tools, and their test steps ran the Brewfile into the host's Homebrew. With `installTarget = "distrobox"`, `dotfiles.zsh` inside the box sets `NM_TEST_START_DAEMON=1`, which makes no-mistakes start a detached daemon instead of a service, and `NM_HOME=$HOME/.no-mistakes`, so the gate remotes and run history stay where they are. The daemon serves every lane: only firstmate or you do this, with nothing running.

1. On a box set up before `chezmoi init` asked where tools install, record the answer, since `chezmoi apply` never asks: in the box, `chezmoi init --source ~/Development/dotfiles pixeloven`, answer `distrobox` (and the ops tools question, if it asks), then `chezmoi apply`. A box built with 9a has it already.
   **Done when:** in the box, `chezmoi execute-template '{{ .installTarget }}'` prints `distrobox`.
2. In a new zsh in the box (after `chezmoi apply`), check the variables.
   **Done when:** `echo $NM_TEST_START_DAEMON $NM_HOME` prints `1` and your `~/.no-mistakes` path.
3. Check that nothing is running: `no-mistakes daemon status`, `no-mistakes axi status`, and `no-mistakes runs` in each gated repo.
   **Done when:** no run is pending or running.
4. Retire the host unit. `no-mistakes daemon stop` alone isn't enough: the unit restarts itself and is enabled for the next login. From the box:
   ```sh
   distrobox-host-exec systemctl --user list-unit-files 'no-mistakes-daemon-*'
   distrobox-host-exec sh -c 'for f in "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service; do [ -e "$f" ] || continue; systemctl --user disable --now "${f##*/}" && rm "$f"; done; systemctl --user daemon-reload'
   ```
   **Done when:** the first command lists no unit files and `ls ~/.config/systemd/user | grep no-mistakes` prints nothing.
5. Start the daemon in the box: `no-mistakes daemon start`.
   **Done when:** `no-mistakes daemon status` says it is running and `cat /proc/"$(jq -r .pid "$NM_HOME/daemon.pid")"/cgroup` does **not** show `user@1000.service/app.slice` (the host's user services; your uid may differ from 1000).

The detached daemon lives as long as the box. After a reboot or `distrobox stop`, the next `no-mistakes` command starts it again, in the box. Run `no-mistakes` only from the box's zsh, where the two variables are set (it needs `installTarget = "distrobox"`); from a shell without them it would install the host unit again.

**Roll back:** `no-mistakes daemon stop`, then `env -u NM_TEST_START_DAEMON no-mistakes daemon start` reinstalls the host unit.

### 9c. Destroy and rebuild the box

*Linux distrobox only.* Destroying the box removes only the container: its apt packages, its Homebrew (with the ops tools), and whatever runs in it, such as herdr and the daemon. Everything in the shared home stays, including `~/Development` (the repos, and the operator home with its state), `~/.no-mistakes`, `~/.treehouse` and every sign-in. Destroying it also doesn't undo anything it wrote to the host; that is 9d.

1. If an agent session supervises work from inside the box (firstmate in herdr), ask it to stop dispatching and let every lane finish or be torn down.
   **Done when:** `treehouse status` in each project repo shows nothing leased and `no-mistakes axi status` shows no active run.
2. Stop the daemon. Once 9b is done it runs in the box: `no-mistakes daemon stop`. If 9b isn't done yet, do its steps 3–4 now, so no host unit is left behind.
   **Done when:** `no-mistakes daemon status` says it is not running.
3. End the supervising session (`/exit` in its Claude Code), quit herdr (its server goes with the box), and close every shell in the box.
   **Done when:** in a host terminal, `pgrep -lx 'claude|herdr'` prints nothing (the box shares the host's process list).
4. On the host, in a host terminal (not a tab inside the box): `distrobox assemble create --replace --file ~/Development/dotfiles/lib/distrobox/ubuntu-dev.ini`. `--replace` removes the old `ubuntu-dev` and creates it again. Never add `--rm-home` to a `distrobox rm`: this box's home is your host home.
   **Done when:** `distrobox list` shows `ubuntu-dev` freshly created and `ls ~/Development` still lists your repos.
5. In the new box, do 9a steps 2–3 (zsh, then Homebrew and `chezmoi init --apply`). Everything else in 9a is in the shared home already: check each remaining step's **Done when** and skip it when it passes.
   **Done when:** 9a's final check passes.
6. Start the daemon (9b step 5, including its cgroup check), start herdr, and run `cd ~/Development/operator && claude` in a herdr pane. Its start-up reconciles from the state on disk.
   **Done when:** the session reconciles and a test dispatch's pipeline run passes.

### 9d. Clean the host

*Linux distrobox only.* With `host` the host's Homebrew is meant to have these tools, so skip this. The daemon's pipeline runs on the host ran the Brewfile into the host's Homebrew (2026-10-25), and agent sessions then added `gh`, `git-delta` and `node` there, plus a few files in `~/.local/bin`, so the host daemon could push and lint. Remove them by hand, in a host terminal, each only at the point its step names. Skip a step for anything you use on the host. Credentials and user data are never deleted here.

1. Homebrew formulae the pipeline installed. Safe once 9b is done, so the pipeline no longer runs on the host:
   `brew uninstall awscli bat bats-core chezmoi eza fd ffmpeg fnm fzf-tab fzf gitleaks glow shellcheck starship tmux uv wl-clipboard xclip zoxide zsh-autosuggestions zsh-syntax-highlighting`, and `brew uninstall --cask 1password-cli` unless you use `op` on the host.
   **Done when:** `brew list --formula` shows none of them.
2. `node` and its links, added for the host daemon. Safe once 9b is done: `brew uninstall node && rm ~/.local/bin/node ~/.local/bin/npm`. Those links point at `/home/linuxbrew/.linuxbrew/bin`, which inside the box is the box's own Homebrew; the box's shells use fnm's Node either way.
   **Done when:** on the host, `command -v node npm` prints nothing.
3. `git-delta`, added by this section's old "delta on the host" step. Safe once 9b is done: `brew uninstall git-delta`. Leave the delta keys in `~/.gitconfig`: the box reads the same file. Run git in the box, or on the host use `git -c core.pager=less …`.
   **Done when:** on the host, `git -c core.pager=less log -1` works.
4. `gh`, added for host pushes. Safe once 9b is done, if you don't push from host apps: `brew uninstall gh`. Don't run `gh auth logout`: `~/.config/gh` is shared, so it would sign the box out too. Leave the credential helper in `~/.gitconfig` as well: its `/home/linuxbrew/.linuxbrew/bin/gh` path is the box's gh inside the box.
   **Done when:** on the host, `command -v gh` prints nothing, and in the box `gh auth status` is still logged in.
5. Then tidy Homebrew: `brew autoremove && brew cleanup --prune=all` (the second only clears the download cache).
   **Done when:** `brew leaves` prints only what you had before the box (plus anything you kept) and `brew list --cask` still lists your casks and the two JetBrains font casks.
6. Lint tools downloaded into `~/.local/bin` for the host's pipeline. Safe once 9b is done and the box has its own copy: in the box, `command -v -a shellcheck actionlint` lists another path for each one you remove. shellcheck comes from the box's Homebrew; the Brewfile has no actionlint, so keep `~/.local/bin/actionlint` while the box has no other. Then `rm ~/.local/bin/shellcheck` (and `~/.local/bin/actionlint` if it qualified).
   **Done when:** in the box, `shellcheck --version` and `actionlint --version` still print versions.
7. Empty directories a test run left: `rmdir ~/.config/.agents ~/.config/.aws ~/.config/.codex ~/.config/.git`. Safe any time; `rmdir` refuses a directory that isn't empty.
   **Done when:** `ls -d ~/.config/.agents` fails.
8. Optional: `rm ~/.local/share/applications/claude-code-url-handler.desktop && update-desktop-database ~/.local/share/applications` stops `claude://` links opening Claude on the host. Safe any time; a Claude Code update may write it again.
   **Done when:** the file is gone.

Keep:
- The font casks `font-jetbrains-mono` and `font-jetbrains-mono-nerd-font`. Ptyxis renders on the host and its Nerd Font glyphs come from them; uninstalling them deletes the fonts.
- `jq`, your own casks, and Homebrew itself (Bazzite ships it).
- The Ptyxis palette, `~/.local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette`, and the profile's palette setting.
- `~/.no-mistakes/`: the daemon's state, gate repos and run history, now used from the box.
- Everything else dotfiles and the box keep in the shared home, such as `~/.zshrc`, `~/.oh-my-zsh`, `~/.config/{zsh,herdr,chezmoi}`, `~/.local/bin/{claude,codex,herdr,no-mistakes,treehouse,lastreply}`, `~/.local/share/fnm` and `~/.treehouse`. The host's bash never reads the zsh files; the rest is the box's.
- Credentials and user data, always: `~/Development`, `~/.claude`, `~/.claude.json`, `~/.codex`, `~/.config/gh`, `~/.ssh`, `~/.local/share/keyrings`.

**Done when:** every check above passes, on the host `systemctl --user list-unit-files | grep no-mistakes` prints nothing, and Ptyxis keeps its font and Catppuccin Mocha palette.

## 10. Ghostty on Linux (only if you chose `ghostty`)

Ptyxis is the Linux default and needs nothing here: `chezmoi apply` installs the Catppuccin Mocha palette and sets it as the default profile's palette; the font stays the system's. This section is for a machine whose `chezmoi init` answer was `ghostty`. Ghostty isn't on Flathub, so pick one of these:

- **AppImage via Gear Lever (recommended).** Download the community Ghostty AppImage (linked from https://ghostty.org/docs/install/binary), open it with Gear Lever on the host and let it integrate the app into the menu. Updates go through Gear Lever.
- **COPR via `rpm-ostree install ghostty`.** Works, but layers a package onto the host image, which Bazzite discourages. Only if you accept layering.
- **The community `.deb` inside the Ubuntu container**, then `distrobox-export --app ghostty` from inside the box to put it in the host's app menu.

When Ghostty runs on the host (AppImage or COPR) and your tools live in the container, uncomment `command = distrobox enter ubuntu-dev` in `~/.config/ghostty/linux.ghostty` (use your box's name from `distrobox list`), then `/codify`. A Ghostty exported from the container already starts inside it.

If programs in the container complain about an unknown terminal (`TERM=xterm-ghostty`; Ghostty's terminfo lives at a host path), copy the entry into the shared `~/.terminfo` by running `infocmp -x xterm-ghostty | tic -x -` on the host. herdr panes reset `TERM` to `xterm-256color`, so only the herdr client itself sees it. Not verified yet.

**Done when:** Ghostty opens from the app menu with the Catppuccin Mocha theme, a new tab lands in the container (`echo $CONTAINER_ID` prints the box), and `bats ~/Development/dotfiles/tests/ghostty.bats` passes.
