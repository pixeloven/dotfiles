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

Files that can hold secrets (`lib/denylist.txt`) are blocked by a pre-commit hook and by CI.

## Rebuild a Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
```

Then follow [RUNBOOK.md](RUNBOOK.md) for the few steps that macOS won't let a script do.

## Set up Linux (distrobox)

Tested on an Ubuntu 24.04 distrobox on Bazzite. Inside the container:

```sh
sudo apt-get update && sudo apt-get install -y build-essential procps curl file git zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
sudo chsh -s /usr/bin/zsh "$USER"
```

`chezmoi init` asks once which terminal you use (Ptyxis by default); macOS asks nothing. With Ptyxis, `chezmoi apply` sets its Catppuccin Mocha palette and leaves the font alone (from a distrobox, on the host through `distrobox-host-exec`); with Ghostty, see RUNBOOK section 10. The Brewfile's `if OS.mac?` / `if OS.linux?` blocks pick the per-OS packages. Inside the container, zsh puts Homebrew ahead of the system dirs so its Node and git win over apt's; on an image-based host (`/run/ostree-booted`) Homebrew stays last. Node comes from fnm on both OSes.

Then follow [RUNBOOK.md](RUNBOOK.md) section 9: oh-my-zsh, fnm's Node and the global npm tools, your git name and email (dotfiles never sets them), delta in the host's Homebrew, and the clipboard check.

## Day to day

- Change something: see [CUSTOMIZE.md](CUSTOMIZE.md).
- Changed something by hand? Run `/codify` in Claude Code. A new session also tells you when there's something to codify.
- `chezmoi diff` shows repo vs machine; `chezmoi apply` makes the machine match the repo.
- Tests: `bats tests/`. Tests tagged `machine` check the live install; skip them with `bats --filter-tags '!machine' tests/` (as CI does).
