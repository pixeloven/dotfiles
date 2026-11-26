# dotfiles

Terminal setup as code for macOS and Linux: Ghostty, herdr, zsh with Starship, Claude Code and Codex, and bat/delta/glow, all on the dark Catppuccin Mocha theme. Managed with [chezmoi](https://chezmoi.io) and a Homebrew `Brewfile`. A fresh install starts minimal, and everything heavier is an option you turn on ([below](#what-a-fresh-install-gets)).

## What a fresh install gets

Accept the defaults `chezmoi init` offers and you get the terminal, herdr, the agent CLIs and what the operator needs. Nothing else:

- **Terminal:** Ghostty on macOS (on Linux, your terminal: Ptyxis gets the theme), the JetBrains Mono fonts, zsh with Starship, fzf, fzf-tab, zoxide, eza and the autosuggestion and highlighting plugins, plus bat, git-delta, glow and tmux.
- **herdr, Claude Code and Codex:** the `herdr-cli`, `claude-code` and `codex` workstation apps, ticked by default. Claude Code and Codex get the crew plugins, the Impeccable skill, the `/lastreply` and `/codify` skills and the spoken-alert hooks (on macOS they speak through the built-in `say`; on Linux they need the `voice` tool set and a local voice, RUNBOOK section 5).
- **Operator prerequisites:** `gh` and `jq`, Node through fnm (and Homebrew's `node`), `uv`, the 1Password CLI, and `bats-core`, `shellcheck` and `gitleaks` for this repo's checks and the validation pipeline.

Every option below is off on a fresh install. Each says what it adds and how to turn it on or off; CUSTOMIZE.md has the details.

| Option | What it adds | On / off |
|---|---|---|
| Tool set `voice` | VoiceInk (macOS push-to-talk), ffmpeg (a short lead-in so alerts aren't clipped) and, on Linux, pulseaudio's `paplay`/`parecord` and whisper.cpp, which spoken alerts and `dictate` need | `toolsets on voice` / `toolsets off voice` |
| Tool set `aws` | the AWS CLI | `toolsets on aws` / `toolsets off aws` |
| Tool sets `kubernetes`, `talos`, `terraform`, `ansible`, `containers` | kubectl, helm and argocd; talosctl and omnictl; terraform; ansible; the docker CLI | `toolsets on <set>` / `toolsets off <set>` |
| Workstation apps `herdr-desktop`, `claude-desktop`, `chatgpt-desktop` | the Herdr, Claude and ChatGPT desktop apps | `workstation-apps enable <app>` / `disable <app>` |
| Workstation apps `blender`, `comfyui` | Blender and Comfy Desktop (Comfy downloads no models) | `workstation-apps enable blender comfyui` / `disable` |
| Machine settings file | Linux network shares with FS-Cache, and Comfy Desktop model folders | `~/.config/dotfiles/settings.toml` ([docs/settings.md](docs/settings.md)) |
| `operatorPersona` | an operator home's persona theme | a `[data]` key in `~/.config/chezmoi/chezmoi.toml` (CUSTOMIZE.md) |
| `agentPlugins = false` | opts out of the crew plugins and the Impeccable skill, which are on by default | a `[data]` key in `~/.config/chezmoi/chezmoi.toml` |

`chezmoi init` asks once for the tool sets (none ticked) and the workstation apps (`herdr-cli`, `claude-code` and `codex` ticked), and saves the answers in `~/.config/chezmoi/chezmoi.toml`. `toolsets` and `workstation-apps` change them later and install what you turn on. Turning something off never uninstalls it; `toolsets off <set> --uninstall` does.

**Existing machines keep their packages.** Before this, `voice` and `aws` were in every machine's base Brewfile. They stay installed: `brew bundle` never uninstalls, and drift never flags a tool set's packages as `pkg-extra`. They are off in `toolsets status`, though, and a rebuilt machine won't reinstall them. To keep them managed, run `toolsets on voice aws` once. Saved workstation app answers, an empty one included, are kept as they are; the new app defaults apply only to a machine answering for the first time.

**Mute:** `voice mute` and `voice unmute` silence or restore spoken alerts and summaries for Claude Code and Codex. `voice toggle` flips mute and can sit on a key in any desktop (RUNBOOK section 4c). `voice status` shows what is on.

## What's managed

| Managed in full (safe to publish) | Patched key by key (never committed) |
|---|---|
| `~/.config/ghostty/config.ghostty` | `~/.claude/settings.json`: only the hooks in `lib/claude-hooks.fragment.json` |
| `~/.config/herdr/config.toml` | `~/.gitconfig`: only the delta/merge keys in `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh` |
| `~/.config/bat/config`, glow's `glow.yml` (`~/Library/Preferences/glow/` on macOS, `~/.config/glow/` on Linux) | |
| `~/.claude/hooks/speak-alert.sh`, `~/.claude/skills/codify/`, the voice helpers `~/.local/bin/voice`, `speak-kokoro`, `voice-cloud` and (Linux) `dictate` (their packages come with the `voice` tool set), `~/.local/bin/toolsets` and `~/.local/bin/dotfiles-settings` | `~/.zshrc`: only the source line in its `# >>> dotfiles >>>` block |
| `~/.config/zsh/`, `~/.config/starship.toml` | |
| Linux with Ptyxis: `~/.local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette` | Ptyxis GSettings: only the default profile's palette in `home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl` |
| | Claude Code, Codex and pi plugin registries (`~/.claude/plugins/`, `~/.codex/config.toml`, `~/.pi/agent/settings.json`, and the `pixeloven` entry under `extraKnownMarketplaces` in `~/.claude/settings.json`): only the plugins in `lib/agent-plugins.txt`, kept at its pinned crew release; a disabled one is never re-installed |
| Linux with `nfsShares` in the settings file (opt-in): `~/.config/network-shares/shares.conf` and `~/.local/bin/network-shares` | `/etc/systemd/system`: only the share units `network-shares install` writes, and with a cached share `/etc/cachefilesd.conf` (with sudo, never from an apply); Comfy Desktop's `settings.json`: only the `comfyui.modelsDirs` folders in `modelsDirs`, and, with `comfyui` selected and before Comfy's first run, its five folder keys |
| | The Impeccable design skill (`~/.claude/skills/impeccable/`, `~/.agents/skills/impeccable/`, `~/.pi/agent/skills/impeccable/`): kept at the version in `lib/impeccable.txt` by its own installer |

Files that can hold secrets (`lib/denylist.txt`) are blocked by a pre-commit hook and by CI.

## Rebuild a Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
```

Then follow [RUNBOOK.md](RUNBOOK.md) for the few steps that macOS won't let a script do.

## Set up Linux (on the host, or in a distrobox)

Tools install either on the Linux machine itself (a server, or any host where you want its own Homebrew) or only inside a distrobox (tested with Ubuntu 24.04 on Bazzite); `chezmoi init` asks which. For a distrobox, first create the box on the host from the tracked file (it shares your `$HOME`), then enter it:

```sh
distrobox assemble create --file ~/Development/dotfiles/lib/distrobox/ubuntu-dev.ini
distrobox enter ubuntu-dev
```

On Bazzite the box is the Linux workstation and the host is the display. Tools and desktop apps install in the box, which gets the host's NVIDIA GPU (`nvidia=true`). With Ptyxis, the default profile (labelled Host) opens the host, and a separate profile labelled `ubuntu-dev` opens the box's zsh.

Then, on the Linux host or inside the box (on a host, use its own package manager for the first line):

```sh
sudo apt-get update && sudo apt-get install -y build-essential procps curl file git zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
sudo chsh -s /usr/bin/zsh "$USER"
```

`chezmoi init` asks a few questions once. On Linux: which terminal you use (Ptyxis by default) and where tools install (`host` by default, `distrobox` suggested on an image-based host and in a box on one; with `distrobox`, nothing installs outside a container). On both OSes: which optional tool sets and which workstation apps to install, as checkboxes ([what a fresh install gets](#what-a-fresh-install-gets)). `toolsets` and `workstation-apps` change them later (CUSTOMIZE.md). With Ptyxis, `chezmoi apply` sets its Catppuccin Mocha palette and leaves the font alone (from a distrobox, on the host through `distrobox-host-exec`); with Ghostty, see RUNBOOK section 10. The Brewfile's `if OS.mac?` / `if OS.linux?` blocks pick the per-OS packages. On Linux, zsh puts Homebrew ahead of the system dirs so its Node and git win over apt's; on an image-based host (`/run/ostree-booted`) Homebrew stays last. Node comes from fnm on both OSes.

Then follow [RUNBOOK.md](RUNBOOK.md) section 9: oh-my-zsh, fnm's Node and the global npm tools, your git name and email (dotfiles never sets them), the clipboard check, and, with a distrobox, moving the validation pipeline into the box. Each step says whether it applies to a Linux host, a distrobox, or both.

## Workstation apps

`chezmoi init` also asks which workstation apps to install: Herdr (CLI and desktop), Claude Code, Codex, the Claude and ChatGPT desktop apps, Blender and Comfy Desktop. The Herdr CLI, Claude Code and Codex are ticked by default; the desktop apps, Blender and Comfy Desktop are yours to add. Every `chezmoi apply` installs the selected ones, so a rebuild is `chezmoi init --apply` plus that saved selection. `workstation-apps` lists, previews, enables and disables them. Homebrew installs the CLIs and the macOS apps. On Linux, the Claude and ChatGPT desktop apps install from their vendors' apt packages: on Bazzite inside the `ubuntu-dev` box, where `distrobox-export` puts them in the host's menu. Comfy Desktop also installs from its vendor's apt package, and Blender from its official tarball. Both are pinned and checksum-checked, in the box on Bazzite, and exported to the host menu. Herdr desktop uses Herdr's official installer. See [workstation apps](docs/workstation-apps.md) and RUNBOOK.md section 12.

## Machine settings (optional)

A few features are per machine and off unless you turn them on in one settings file, `~/.config/dotfiles/settings.toml` (schema v1, [docs/settings.md](docs/settings.md)). With no file, nothing changes. `chezmoi apply` validates it first and fails with one message, changing nothing, if it is wrong; `dotfiles-settings check` runs the same check.

- **Network shares** (Linux): NFS shares mounted on first use, so a down server never holds up boot, optionally cached on local disk with FS-Cache. `network-shares install` (sudo, on the host) sets them up; network-shares never runs sudo from an apply. See [network shares](docs/network-shares.md) and RUNBOOK.md section 13.
- **Comfy Desktop folders** (Linux): where its folders go before its first run, `~/ComfyUI` by default, and extra folders added to its Shared Models. See [workstation apps](docs/workstation-apps.md#comfy-desktop-folders).

## Day to day

- Change something: see [CUSTOMIZE.md](CUSTOMIZE.md).
- Changed something by hand? Run `/codify` in Claude Code. A new session also tells you when there's something to codify.
- `chezmoi diff` shows repo vs machine; `chezmoi apply` makes the machine match the repo.
- Tests: `bats tests/`. Tests tagged `machine` check the live install; skip them with `bats --filter-tags '!machine' tests/` (as CI does).
