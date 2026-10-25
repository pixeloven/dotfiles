# Runbook: manual steps

Steps that scripts can't do, or that the OS asks you to approve yourself. Each one ends with a **Done when** check. A new Linux machine starts at section 9 instead of section 1.

## 1. New Mac bootstrap

1. Install Homebrew and chezmoi, then run `chezmoi init --apply` (see README). This installs everything in the Brewfile.
2. Install herdr from https://herdr.dev. It installs itself into `~/.local/bin` and updates with `herdr update`.
3. Run `herdr integration install claude` (and `herdr integration install pi` if you use Pi).
4. In the repo, enable the secret guard: `git -C ~/Development/dotfiles config core.hooksPath .githooks`.
5. Shell: install oh-my-zsh keeping the `~/.zshrc` chezmoi wrote (`sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc`), then Node through fnm: `fnm install 22 && fnm default 22`, and in a new tab reinstall the global npm tools listed in step 8. Without oh-my-zsh, `dotfiles.zsh` still loads with plain completion.
6. Do steps 2–4 of this runbook.

**Done when:** `bats ~/Development/dotfiles/tests/` passes.

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

macOS only for now.

Option A, nothing to install:
1. System Settings → Keyboard → Dictation: turn **on**, and set the shortcut to **Press 🌐 twice** (Fn twice).

Option B, better with technical words:
1. Install Superwhisper (https://superwhisper.com) or Wispr Flow.
2. Pick a local English model and set a push-to-talk key.
3. Turn on "paste into the active app".

**Done when:** speaking into a Claude Code prompt inside herdr types the text.

## 5. Premium voice for spoken alerts

macOS only. On Linux, alerts are silent for now; the voice approach is tracked in dotfiles issue #1.

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

## 9. New Linux (distrobox) bootstrap

For an Ubuntu distrobox on an image-based host such as Bazzite, where the host and the container share `$HOME` but each has its own Homebrew at `/home/linuxbrew/.linuxbrew`. Run every step inside the container unless it says host. Shared `$HOME` means `~/.zshrc`, `~/.gitconfig`, `~/.oh-my-zsh` and fnm's Node (`~/.local/share/fnm`) are the same files on both sides, so skip any step whose check already passes.

1. Homebrew and chezmoi: `sudo apt-get update && sudo apt-get install -y build-essential procps curl file git`, then the Homebrew installer from the README, then `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` for this shell only (don't add it to `~/.bashrc`, which the host reads too; `dotfiles.zsh` finds brew itself), `brew install chezmoi` and `chezmoi init --apply --source ~/Development/dotfiles pixeloven`.
   **Done when:** `brew bundle check --file ~/Development/dotfiles/Brewfile` says the dependencies are satisfied.
2. zsh as the container's login shell, from apt so a container rebuild can't strand it: `sudo apt-get install -y zsh && sudo chsh -s /usr/bin/zsh "$USER"`. This edits only the container's `/etc/passwd`; the host keeps its shell.
   **Done when:** after `exit` and `distrobox enter` again, `ps -p $$ -o comm=` prints `zsh` and `which node` is not `/usr/bin/node` (Homebrew sits ahead of the system dirs inside the container; on the host it stays last).
3. oh-my-zsh, keeping the `~/.zshrc` chezmoi wrote: `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc`.
   **Done when:** `~/.oh-my-zsh/oh-my-zsh.sh` exists and a new zsh shows the Starship prompt with grey suggestions as you type.
4. Node through fnm: first record the global npm tools under Homebrew's Node with `npm ls -g --depth=0` (on the first Linux machine: `chrome-devtools-axi`, `gh-axi`, `quota-axi`, `tasks-axi`). Then `fnm install 22 && fnm default 22` (the Mac's major), open a new shell, and `npm install -g` each tool at the version you recorded. Homebrew's `node` stays installed for anything that doesn't run `fnm env`, such as scripts and the operator's remote jobs.
   **Done when:** in a new shell `which node` is under fnm and `gh-axi --version` prints a version.
5. Git identity, by hand, because dotfiles never sets it: `git config --global user.name "Your Name"` and `git config --global user.email you@example.com`.
   **Done when:** `git config user.name` and `git config user.email` print your values.
6. delta on the host: the host reads the same `~/.gitconfig`, whose pager is `delta`. `distrobox-host-exec /home/linuxbrew/.linuxbrew/bin/brew install git-delta` (that path is resolved on the host, so it's the host's Homebrew).
   **Done when:** in a host terminal (outside the container), `delta --version` prints a version and `git -C ~/Development/dotfiles log -p -1` pages through delta.
7. Do steps 2–4 of section 1 (herdr, its Claude integration, the repo's secret guard) and section 3 if this `$HOME` hasn't had them yet.
   **Done when:** `herdr --version` prints a version, `fc-list | grep -q 'JetBrainsMono Nerd Font'` succeeds, and text you select in a herdr pane pastes into a host app with `ctrl+v` (herdr copies through the Brewfile's `wl-copy`/`xclip` when the terminal ignores OSC 52, as Ptyxis does).

**Done when:** every check above passes and `bats ~/Development/dotfiles/tests/` passes inside the container.
