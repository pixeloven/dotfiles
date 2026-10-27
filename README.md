# dotfiles

Terminal setup as code for macOS and Linux: Ghostty, herdr, zsh with Starship, Claude Code alerts, and bat/delta/glow, all on the dark Catppuccin Mocha theme. Managed with [chezmoi](https://chezmoi.io) and a Homebrew `Brewfile`.

## What's managed

| Managed in full (safe to publish) | Patched key by key (never committed) |
|---|---|
| `~/.config/ghostty/config.ghostty` | `~/.claude/settings.json`: only the hooks in `lib/claude-hooks.fragment.json` |
| `~/.config/herdr/config.toml` | `~/.gitconfig`: only the delta/merge keys in `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh` |
| `~/.config/bat/config`, glow's `glow.yml` (`~/Library/Preferences/glow/` on macOS, `~/.config/glow/` on Linux) | |
| `~/.claude/hooks/speak-alert.sh`, `~/.claude/skills/codify/` | `~/.zshrc`: only the source line in its `# >>> dotfiles >>>` block |
| `~/.config/zsh/`, `~/.config/starship.toml` | |
| Linux with Ptyxis: `~/.local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette` | Ptyxis GSettings: only the default profile's palette in `home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl` |
| | Claude Code, Codex and pi plugin registries (`~/.claude/plugins/`, `~/.codex/config.toml`, `~/.pi/agent/settings.json`): only the plugins in `lib/agent-plugins.txt`, installed when missing and never re-installed |

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

Then, on the Linux host or inside the box (on a host, use its own package manager for the first line):

```sh
sudo apt-get update && sudo apt-get install -y build-essential procps curl file git zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
sudo chsh -s /usr/bin/zsh "$USER"
```

`chezmoi init` asks a few questions once. On Linux: which terminal you use (Ptyxis by default) and where tools install (`host` by default, `distrobox` suggested on an image-based host and in a box on one; with `distrobox`, nothing installs outside a container). On both OSes: whether to install the ops tools (kubectl, helm, argocd, talosctl, omnictl, terraform, ansible and the docker CLI; default no). With Ptyxis, `chezmoi apply` sets its Catppuccin Mocha palette and leaves the font alone (from a distrobox, on the host through `distrobox-host-exec`); with Ghostty, see RUNBOOK section 10. The Brewfile's `if OS.mac?` / `if OS.linux?` blocks pick the per-OS packages. On Linux, zsh puts Homebrew ahead of the system dirs so its Node and git win over apt's; on an image-based host (`/run/ostree-booted`) Homebrew stays last. Node comes from fnm on both OSes.

Then follow [RUNBOOK.md](RUNBOOK.md) section 9: oh-my-zsh, fnm's Node and the global npm tools, your git name and email (dotfiles never sets them), the clipboard check, and, with a distrobox, moving the validation pipeline into the box. Each step says whether it applies to a Linux host, a distrobox, or both.

## Day to day

- Change something: see [CUSTOMIZE.md](CUSTOMIZE.md).
- Changed something by hand? Run `/codify` in Claude Code. A new session also tells you when there's something to codify.
- `chezmoi diff` shows repo vs machine; `chezmoi apply` makes the machine match the repo.
- Tests: `bats tests/`. Tests tagged `machine` check the live install; skip them with `bats --filter-tags '!machine' tests/` (as CI does).
