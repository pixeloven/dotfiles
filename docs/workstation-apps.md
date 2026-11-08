# Workstation apps

Rebuilding a development environment is `chezmoi init --apply` plus the saved selection of workstation apps. This page covers that selection: which apps it can install, how each one installs on each platform, and what stays manual. It never installs anything you didn't select.

## Choose and install

`chezmoi init` asks once which apps to install; none are selected by default. The answer is the `workstationApps` list in your untracked `~/.config/chezmoi/chezmoi.toml`. Every `chezmoi apply` then installs the selected apps that are missing and leaves installed ones alone, the way it installs the ops `toolsets`. A rebuild needs no extra step.

```sh
workstation-apps                          # list: every app, on or off, and how it installs here
workstation-apps enable herdr-cli codex   # select apps, then run chezmoi apply --include scripts
workstation-apps disable codex            # deselect; nothing is uninstalled
workstation-apps preview                  # read-only: route, source and state of the selection
workstation-apps install [app...]         # install now without changing the selection
```

`on` and `off` are short forms of `enable` and `disable`. `preview app...` and `install app...` work on apps you haven't selected. Disabling an app leaves its program, settings and data in place. `install` exits 3 when some selected apps still need you (manual apps, a host/box mismatch, or a copy Homebrew doesn't manage). That result is partial, not a success. No vendor download script is run for you.

## Platforms

| App | macOS | Linux (plain host, or Bazzite with a distrobox) |
|---|---|---|
| `herdr-cli` | Homebrew formula `herdr` | Homebrew formula `herdr` (in the box) |
| `herdr-desktop` | Cask `herdr-app`, Apple silicon only | Manual: [vendor installer](https://herdr.dev/download/), no Flathub package |
| `claude-code` | Cask `claude-code` | Cask `claude-code` (in the box) |
| `codex` | Cask `codex` (the CLI) | Cask `codex` (in the box) |
| `claude-desktop` | Cask `claude` | Manual: [beta apt repository](https://code.claude.com/docs/en/desktop-linux), Debian and Ubuntu only |
| `chatgpt-desktop` | Cask `chatgpt`, which includes Codex's desktop app | Manual: [preview deb/rpm repositories](https://learn.chatgpt.com/docs/linux/linux-app) |
| `blender` | Cask `blender` | Manual: [official tarball](https://www.blender.org/download/) |
| `comfyui` | Cask `comfy`, Apple silicon only | Manual: [deb or AppImage](https://docs.comfy.org/installation/desktop/linux), x86_64 |

How it splits:

- **macOS:** everything is a Homebrew formula or cask.
- **Linux:** command-line tools install with Homebrew. With `installTarget = "distrobox"`, they install inside the box only, as the Brewfile does. A desktop app with an approved Flathub package installs on the host as a Flatpak; none qualifies today, so the Linux desktop apps above are manual. From inside a box they go through `distrobox-host-exec`, the same crossing the Ptyxis palette uses. On a Bazzite host, `chezmoi apply` and `workstation-apps install` skip the Homebrew apps and still install the Flatpak apps.
- **Flatpak installs** use `flatpak install --user` from Flathub, which needs no root. The `flathub` user remote is added if it is missing.
- **macOS app versions:** the casks follow each vendor's own requirements. For example, `herdr-app` and `comfy` need Apple silicon, and `claude` and `chatgpt` need macOS 13 or later.

There is no separate Codex desktop app to select. OpenAI folded it into the ChatGPT app, and Homebrew retired the `codex-app` cask in favor of `chatgpt`. If `codex-app` is still installed, run `brew uninstall --cask codex-app` before selecting `chatgpt-desktop`. `chatgpt` and `chatgpt-classic` both install `ChatGPT.app`, so keep only one.

### Flathub and community packages

None of these desktop apps has a Flathub package published or verified by its vendor. So no Linux desktop app installs automatically yet. The Flatpak route is in place for the first one that qualifies.

A package that Flathub lists but its vendor doesn't publish is a community package. It is added only after it is approved app by app. Once added, it carries the `community` label in the catalog, in `list` and in `preview`. The only candidate today is Blender's [`org.blender.Blender`](https://flathub.org/apps/org.blender.Blender): it is unverified, community-packaged from Blender's release tarball, and x86_64 only.

An app whose only Linux download is an AppImage stays manual. Manage the AppImage with [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever), a verified Flathub app. On an image-based host that can't install a deb, this applies to Comfy Desktop's AppImage.

## One copy per app: Homebrew owns the CLIs

Homebrew owns herdr, Claude Code and Codex. A copy from a vendor installer (`~/.local/bin`), from `npm install -g`, or a macOS app bundle that Homebrew doesn't manage would shadow the Homebrew copy or block the cask. So installs skip any app that already has such a copy and tell you how to hand it over:

```sh
workstation-apps vendor                        # read-only: copies Homebrew doesn't manage
workstation-apps vendor remove claude-code     # shows what it removes, then asks y/N
workstation-apps install claude-code
```

`vendor remove` never runs without your confirmation, and it never runs during `chezmoi apply`. It removes:

- a vendor-installed command, and Claude Code's `~/.local/share/claude` versions directory;
- an npm global, with `npm uninstall -g`;
- a macOS app bundle, moved to `~/.Trash`.

Settings, sign-ins and data (`~/.claude`, `~/.codex`, `~/.config/herdr`) stay. Update Homebrew-owned apps with `brew upgrade`. Apps whose casks update themselves (`auto_updates`) keep doing so.

## Drift

`bin/drift`, which `/codify` reads, compares the selection with what is installed. It reports:

- `app-missing`: selected but not installed. Run `workstation-apps install <app>`, or `chezmoi apply`.
- `app-unselected`: a catalog app installed but not selected. Run `workstation-apps enable <app>`, or keep it through `/codify`.
- `app-retired`: selected, but the catalog no longer has it. `chezmoi apply` and `install` warn and skip it until you run `workstation-apps disable <app>`.
- `app-vendor`: a selected app also has a copy Homebrew doesn't manage. Run `workstation-apps vendor remove <app>`.
- `app-unselected-vendor`: a catalog app installed by hand (a vendor installer, `npm install -g`, or a downloaded macOS app) but not selected, with the copy's path. Run `workstation-apps enable <app>`, then `workstation-apps vendor remove <app>` so Homebrew takes over.

## Left to you

- Signing in to every app, desktop-control permissions and credential stores. Never copy another machine's auth files.
- Each desktop app's first-run choices: Comfy's models and output folders, and Blender's preferences and add-ons. Herdr Desktop's own settings in `~/.config/herdr-app` are separate from the herdr CLI's `~/.config/herdr`, and this repo doesn't write them.
- GPU drivers and GPU access. A distrobox with the GPU switched off can't run GPU apps, which is why desktop apps install on the host.

The tests use stub `brew`, `flatpak` and `npm` in a throwaway home, so they show the routing and guard logic, not that a real app installs, launches or uses the GPU.
