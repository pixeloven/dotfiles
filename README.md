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

Files that can hold secrets (`lib/denylist.txt`) are blocked by a pre-commit hook and by CI.

## Rebuild a Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
```

Then follow [RUNBOOK.md](RUNBOOK.md) for the few steps that macOS won't let a script do.

On Linux, install Homebrew and chezmoi the same way and run the same `chezmoi init`. It asks once which terminal you use (Ptyxis by default); macOS asks nothing. The Brewfile's `if OS.mac?` / `if OS.linux?` blocks pick the per-OS packages.

## Day to day

- Change something: see [CUSTOMIZE.md](CUSTOMIZE.md).
- Changed something by hand? Run `/codify` in Claude Code. A new session also tells you when there's something to codify.
- `chezmoi diff` shows repo vs machine; `chezmoi apply` makes the machine match the repo.
- Tests: `bats tests/`. Tests tagged `machine` check the live install; skip them with `bats --filter-tags '!machine' tests/` (as CI does).
