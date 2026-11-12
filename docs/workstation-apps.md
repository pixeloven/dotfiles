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

`on` and `off` are short forms of `enable` and `disable`. `preview app...` and `install app...` work on apps you haven't selected. Disabling an app leaves its program, settings and data in place. `install` exits 3 when some selected apps still need you (manual apps, a host/box mismatch, or a copy Homebrew doesn't manage). That result is partial, not a success. The only vendor scripts that run are the installers the catalog names: Herdr's official Linux installer, and the vendors' own apt packages. Blender's tarball runs no install script.

To add Blender and Comfy Desktop, run this in the box on Bazzite (or on an Ubuntu host):

```sh
workstation-apps enable blender comfyui   # saves the choice, then chezmoi apply --include scripts installs both
workstation-apps preview blender comfyui  # each shows installed
```

Both then appear in the host's app menu as "Blender (on ubuntu-dev)" and "Comfy Desktop (on ubuntu-dev)".

## Platforms

On Bazzite the `ubuntu-dev` distrobox is the Linux workstation and the host is the display: tools and desktop apps live in the box, and their windows and launchers appear on the host.

| App | macOS | Linux: Ubuntu host, or the Bazzite box |
|---|---|---|
| `herdr-cli` | Homebrew formula `herdr` | Homebrew formula `herdr` (in the box) |
| `herdr-desktop` | Cask `herdr-app`, Apple silicon only | [Herdr's official installer](https://herdr.dev/download/) into `~/.local`; Herdr's own updater keeps it current |
| `claude-code` | Cask `claude-code` | Cask `claude-code` (in the box) |
| `codex` | Cask `codex` (the CLI) | Cask `codex` (in the box) |
| `claude-desktop` | Cask `claude` | apt `claude-desktop` from [Anthropic's repository](https://code.claude.com/docs/en/desktop-linux) (beta) |
| `chatgpt-desktop` | Cask `chatgpt`, which includes Codex's desktop app | apt `chatgpt` from [OpenAI's Ubuntu package](https://learn.chatgpt.com/docs/linux/linux-app) (preview), x86_64 |
| `blender` | Cask `blender` | [Blender's official tarball](https://www.blender.org/download/) 5.3.0, x86_64, checked against its published sha256 and unpacked into `~/.local/opt/blender` |
| `comfyui` | Cask `comfy`, Apple silicon only | apt `comfyui-desktop-2` from [Comfy's official Ubuntu package](https://docs.comfy.org/installation/desktop/linux) 1.1.9, x86_64, checked against its published sha512 |

How it splits:

- **macOS:** everything is a Homebrew formula or cask.
- **Linux, command-line tools:** Homebrew. With `installTarget = "distrobox"` they install inside the box only, as the Brewfile does. On the Bazzite host itself, `chezmoi apply` and `workstation-apps install` skip them.
- **Linux, desktop apps:** the vendor's Ubuntu package with apt. In the box on Bazzite, or natively on an Ubuntu or Debian host; another distro's host skips them. Blender has no Ubuntu package, so it uses its official tarball instead (below). In the box, each app is then exported with `distrobox-export --app`, so it appears in the host's menu and runs in the box with the box's tools and GPU. The Codex inside ChatGPT, for example, sees the box's Homebrew. After each export, and after Herdr's installer runs, dotfiles rebuilds the host's icon cache for `~/.local/share/icons/hicolor` (`gtk-update-icon-cache`), if that cache exists, so new launchers show their icons.
- **Link handling:** after each export, dotfiles refreshes the host's link-handler index (`update-desktop-database`), which the export's own refresh can miss. Blender and Comfy Desktop register no link scheme, so they get no hidden launcher or `xdg-mime` default. Each app with a scheme rewrites its link default to its own desktop name (`chatgpt.desktop`, `com.anthropic.Claude.desktop`) every time it starts. So dotfiles adds a hidden launcher with that name that opens the box's copy, and points `codex://` and `claude://` at it with `xdg-mime`. If another install already owns that name, such as a host ChatGPT, dotfiles leaves it alone and points the link at the exported launcher instead. Until that install is removed, its own launcher wins on the app's next start. ChatGPT also registers for `http` and `https`, so after an export dotfiles puts back the host's previous default browser for both.
- **Apt packages:** `libsecret-1-0` is installed alongside, so sign-ins are stored in the host's keyring rather than in plaintext (Comfy's package depends on it already). Anthropic's signing key is checked against its published fingerprint before its repository is added. OpenAI's package adds OpenAI's own repository. Comfy's package is pinned to one release, checked against the sha512 that Comfy publishes for it, and adds Comfy's own apt source. If the sum doesn't match, nothing is installed and that app fails; the other apps still install. Apt updates all three: `sudo apt update && sudo apt upgrade` in the box.
- **Blender:** the official x86_64 tarball, pinned to one release and checked against the sha256 that blender.org publishes. If the sum doesn't match, nothing is unpacked and Blender fails; the other apps still install. The download comes from `mirror.blender.org`, the link on blender.org's download page; `download.blender.org` refuses scripted downloads. It unpacks into `~/.local/opt/blender/<version>`, with a `current` link and a launcher that calls `current/blender`. In the box that launcher is exported to the host's menu. On a host without a box, it goes in `~/.local/share/applications`, unless another install already has a `blender.desktop` there. The tarball is in the shared home, so it survives a box rebuild. Blender doesn't update itself. A new release is a new pin in `lib/workstation-apps.tsv`, and older versions stay in `~/.local/opt/blender` until you delete them. Where apt is usable (in the box, or on an Ubuntu or Debian host), dotfiles also installs any of the X11 and OpenGL libraries the official build loads that are missing: `libxi6`, `libsm6`, `libxkbcommon0`, `libxrender1`, `libxxf86vm1`, `libxfixes3` and `libgl1`. On another distro's host, those are left to you. From a terminal in the box, run `~/.local/opt/blender/current/blender`. Nothing is added to `PATH`.
- **Comfy Desktop:** the deb installs under `/opt/Comfy Desktop` in the box. dotfiles sets up no models, model paths, `extra_model_paths.yaml` or model downloads. Pointing Comfy at a shared model library comes later.
- **Herdr desktop:** its window runs on the host. On Bazzite, dotfiles also writes `~/.config/herdr-core/config.toml` with `shell = ["distrobox", "enter", "ubuntu-dev"]`, so the terminals Herdr opens are zsh in the box. Herdr still sees the agents running there. Two limits:
  - Commands Herdr starts with an argument list run on the host: its agent menu, `hc run`, templates, and sub-agents started from inside the box.
  - Plain programs in a box terminal show as `distrobox`.
- **macOS app versions:** the casks follow each vendor's own requirements. For example, `herdr-app` and `comfy` need Apple silicon, and `claude` and `chatgpt` need macOS 13 or later.

There is no separate Codex desktop app to select. OpenAI folded it into the ChatGPT app, and Homebrew retired the `codex-app` cask in favor of `chatgpt`. If `codex-app` is still installed, run `brew uninstall --cask codex-app` before selecting `chatgpt-desktop`. `chatgpt` and `chatgpt-classic` both install `ChatGPT.app`, so keep only one.

### Moving an existing host app into the box

A desktop app already installed on the Bazzite host (for example the `chatgpt-linux` cask) keeps working, but it owns the app's launcher name. To move it into the box:

1. Quit the host app.
2. Uninstall it the way it was installed (for the cask, `brew uninstall --cask chatgpt-linux` on the host). That removes its launcher and icon.
3. Run `chezmoi apply` in the box. It installs the app there, exports it, and points the app's link default at the box.

Never run `distrobox-export --app <app> --delete` while a host launcher with the same name exists. distrobox deletes both `<box>-<app>.desktop` and the un-prefixed `<app>.desktop`, along with its icons, and those may be the host install's only copies. dotfiles never calls `--delete`.

### Not managed

No Flatpak is managed. The Blender community Flatpak was declined: Blender and ComfyUI use the vendors' own downloads, in the box with its GPU. VS Code, 1Password, ROG Control Center and other host apps are not managed either.

## One copy per app: Homebrew owns the CLIs

Homebrew owns herdr, Claude Code and Codex. A copy from a vendor installer (`~/.local/bin`), from `npm install -g`, or a macOS app bundle that Homebrew doesn't manage would shadow the Homebrew copy or block the cask. So installs skip any app that already has such a copy and tell you how to hand it over:

```sh
workstation-apps vendor                        # read-only: copies Homebrew doesn't manage
workstation-apps vendor remove claude-code     # shows what it removes, then asks y/N
workstation-apps install claude-code
```

`vendor remove` never runs without your confirmation, and it never runs during `chezmoi apply`. It removes:

- a vendor-installed command, and Claude Code's `~/.local/share/claude` versions directory;
- an npm global, with `npm uninstall -g --prefix <prefix>`, from the prefix it was installed into;
- a macOS app bundle, moved to `~/.Trash`.

A global package from another package manager, such as bun or yarn, is listed but not removed: uninstall it with that tool.

Settings, sign-ins and data (`~/.claude`, `~/.codex`, `~/.config/herdr`) stay. On Bazzite, once the vendor copies in the shared `~/.local/bin` are gone, `claude` and `codex` live only in the box's Homebrew, and the host no longer runs them. Update Homebrew-owned apps with `brew upgrade`. Apps whose casks update themselves (`auto_updates`) keep doing so.

## Drift

`bin/drift`, which `/codify` reads, compares the selection with what is installed. It reports:

- `app-missing`: selected but not installed. Run `workstation-apps install <app>`, or `chezmoi apply`.
- `app-unselected`: a catalog app installed by its route (Homebrew, apt in the box, or its installer) but not selected. Run `workstation-apps enable <app>`, or keep it through `/codify`.
- `app-retired`: selected, but the catalog no longer has it. `chezmoi apply` and `install` warn and skip it until you run `workstation-apps disable <app>`.
- `app-vendor`: a selected app also has a copy Homebrew doesn't manage. Run `workstation-apps vendor remove <app>`.
- `app-unselected-vendor`: a catalog app installed by hand (a vendor installer, `npm install -g`, or a downloaded macOS app) but not selected, with the copy's path. Run `workstation-apps enable <app>`, then `workstation-apps vendor remove <app>` so Homebrew takes over.

## Left to you

- Signing in to every app, desktop-control permissions and credential stores. Never copy another machine's auth files.
- Each desktop app's first-run choices: at Comfy Desktop's first launch, create a ComfyUI instance. Keep the NVIDIA build it preselects for the GPU, and skip a starter template if you don't want its models downloaded. Comfy's shared models and outputs default to `~/ComfyUI-Shared`; dotfiles doesn't point it at a shared model library yet. Also Blender's preferences and add-ons: to render on the GPU, pick OptiX or CUDA under Preferences > System. Herdr Desktop's own settings in `~/.config/herdr-app` are separate from the herdr CLI's `~/.config/herdr`, and this repo doesn't write them.
- GPU drivers. `lib/distrobox/ubuntu-dev.ini` sets `nvidia=true`, and every apply in the box adds the NVIDIA EGL and Vulkan manifests that distrobox doesn't map (`lib/distrobox/nvidia-manifests.sh`). Without them, native Wayland and Vulkan apps silently render on the CPU. Rebuilding an existing box to get the GPU is RUNBOOK §9c.

The tests use stub `brew`, `apt-get`, `curl`, `sha256sum`, `sha512sum`, `distrobox-export`, `xdg-mime` and `npm` in a throwaway home. They show the routing and guard logic, not that a real app installs, launches or uses the GPU.

## Repairing ChatGPT MCP paths after a Linux migration

Moving ChatGPT from the experimental Linuxbrew cask to the vendor deb can leave
`node_repl` configured with a removed, version-specific Homebrew path. Its browser
service can also refer to a plugin cache file that no longer exists. The symptom
is a Codex startup warning: `node_repl: No such file or directory`.

After installing the vendor package, quit Codex and run from this repository:

```sh
bin/repair-codex-linux-paths
```

The command verifies the installed executables and browser service, backs up
`~/.codex/config.toml`, and replaces the recognized legacy paths inside the
`node_repl` tables. It leaves custom commands and other MCP servers alone. It is
an explicit migration command rather than an automatic overwrite on each apply.
Restart Codex afterwards. To restore the previous settings, copy the printed
backup over the config.

## Updating installed apps

The catalog selects installation routes; it does not pin app versions. Updating
installed binaries happens on the machine, separately from merging a dotfiles PR.
For Homebrew-owned apps and vendor apt packages, refresh the package indexes first:

```sh
brew update
brew outdated --greedy
brew upgrade --greedy
sudo apt-get update
sudo apt-get install --only-upgrade chatgpt claude-desktop
```

Run those inside `ubuntu-dev` on Bazzite. Only include installed packages in the
apt command. Homebrew upgrades all its installed packages here, including casks
that can update themselves. Herdr desktop uses its own updater. Vendor-installed
Claude Code and Codex copies must be updated by their original installers, or
explicitly handed over to Homebrew as described above; Homebrew does not update
those copies. Host apps outside this catalog use their host package managers.
An empty outdated list from cached indexes does not establish that the installed
versions are current.
