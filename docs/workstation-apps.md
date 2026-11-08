# Selectable workstation applications

This public repository sets up an environment, not a machine's projects or identity. The workstation app catalog is **opt-in** and independent of the existing ops `toolsets`. Selections live in the local chezmoi configuration, never in a machine-specific file committed here. Existing base Brewfile and configuration behavior is unchanged; a full `chezmoi apply` is not a minimal-app bootstrap.

## Choose, preview, install

After applying dotfiles, use:

```sh
workstation-apps list
workstation-apps on herdr-cli herdr-desktop claude-code codex blender comfyui
workstation-apps plan
workstation-apps install
```

`chezmoi init` also offers these app selections, all off by default. `on` and `off` **only save selection**; they never install, uninstall, sign in, stop services, or remove app data. `install` is a separate explicit step and does not run the rest of chezmoi's scripts. `plan app...` and `install app...` work for a one-off subset without changing saved selections. `off` leaves binaries, user preferences and content untouched. There is intentionally no automatic uninstall/cleanup command.

Homebrew-backed entries install with an explicit `--formula` or `--cask`. Already installed entries are left alone; use Homebrew separately for upgrades. Existing vendor/npm installs are not removed or migrated automatically. Check `type -a herdr claude codex` before adopting an app already installed another way, and keep one intended installation owner.

`plan` is read-only and shows the route and source for every selection. `install` exits 3 when selected items need manual work; this is a partial result, not an install success. A failed Homebrew command stops immediately. No vendor download script is automatically executed.

## Platform catalog

Sources checked 2026-11-08. Availability changes; the source links in `lib/workstation-apps.tsv` are the evidence, not a claim that every listed route was executed on every OS.

| Selection | macOS | Linux host / Ubuntu Distrobox |
|---|---|---|
| `herdr-cli` | Homebrew formula `herdr` | Homebrew formula `herdr` |
| `herdr-desktop` | Cask `herdr-app`, Apple silicon | Official vendor installer; manual |
| `claude-code` | Cask `claude-code` | Cask `claude-code` |
| `codex` | Cask `codex` (CLI) | Cask `codex` (CLI) |
| `claude-desktop` | Cask `claude` | No verified official package in this catalog; manual evaluation |
| `chatgpt-desktop` | Cask `chatgpt` | Linux packaging evaluation; manual |
| `blender` | Cask `blender` | Distro package or official archive; manual |
| `comfyui` | Cask `comfy`, Apple silicon | Official Comfy Desktop deb or AppImage; manual |

Herdr's desktop app and its TUI are different products/configuration surfaces. The app's own installer sets up `herdr-core`; selecting `herdr-cli` is not a substitute for the desktop app. See [Herdr download](https://herdr.dev/download/) and [TUI install](https://herdr.dev/tui/docs/install/).

The [Comfy Linux guide](https://docs.comfy.org/installation/desktop/linux) now documents official deb/AppImage packages. Do not silently replace Desktop with a Git checkout or a Python server. The first-run terms, local/cloud choice, instance version, GPU backend, models and output locations remain deliberate local setup. Do not add `--no-sandbox` or alter AppArmor as an installer workaround.

The core ChatGPT cask only represents its macOS package. A separate `ublue-os/experimental-tap/chatgpt-linux` package exists and uses OpenAI-hosted assets, but is a community experimental packaging route, not the core cask. It is deliberately not added as an implicit tap or fallback. Evaluate its support, permissions and lifecycle before adding an explicitly named opt-in route. Do not assume a working local installation proves compatibility on every Ubuntu/Distrobox system.

## Configuration boundaries

- Existing Herdr TUI preferences remain in `home/dot_config/herdr/config.toml`.
- Herdr Desktop uses `~/.config/herdr-app`, distinct from the TUI. Its version-matched `AGENTS.md` describes its supported settings. This first increment **does not overwrite or import** that directory, its layouts, machines, sessions or project lists. A follow-up can patch an allowlist of portable theme/keyboard preferences once their schema is verified. See [Herdr guide](https://herdr.dev/guide/).
- Existing Claude/Codex hooks and selected plugin configuration are unchanged. They do not imply an authenticated login, paid subscription, or agent access to another computer.
- Claude/ChatGPT desktop login, device authorization, desktop-control permissions and credential stores remain local and manual. Never copy another machine's auth files.
- Blender preferences/addons and Comfy installations, models, workflows, inputs and outputs are not imported, generated or synced by this feature.
- No SSH keys, tokens, project work, personal content, remote-host names or machine addresses belong in the catalog or committed configuration.

## Distrobox and GPU boundary

For an Ubuntu VM, use the `host` target. On Bazzite with `installTarget = "distrobox"`, the installer refuses to run on the host: enter the intended box first. It never invokes `distrobox-host-exec`, installs host packages, exports launchers, changes drivers, or starts services. `plan` works on either side of the boundary.

The existing `ubuntu-dev.ini` is a CLI dev box and explicitly sets `nvidia=false`. Installing Blender/Comfy or Herdr inside it does not supply GPU access, GUI libraries, clipboard integration or a host launcher. Keep that box unchanged. Validate a separate GPU-enabled creative box and its host integration before declaring Linux desktop apps supported there. Shared `$HOME` also means preference and app-data paths are shared unless deliberately separated; Distrobox is not a security boundary.

Hardware provisioning stays in the workstation runbook: Proxmox VM creation, passthrough, signed NVIDIA drivers/MOK enrollment, snapshots and shared-storage mounts. This app selection layer does not manage those.

## Validation and rollout

1. Start from a known-good VM snapshot. Confirm OS, GPU driver and available disk separately.
2. Preview selections; resolve manual items rather than treating them as installed.
3. Install a small subset. Re-run it; Homebrew-installed items should be unchanged.
4. Verify executable paths and vendor versions, sign in locally, then test a small actual task.
5. For GUI apps test launch, clipboard, remote-session visibility and correct GPU use. Test an agent reading back a human edit, not just launching a process.
6. Snapshot after validation. Repeat on another OS only after the first machine works.

Repository tests use fake Homebrew and throwaway HOME/config paths. They cover selection, idempotent install, manual outcomes, malformed input and the Distrobox guard. They do not establish real app install, GUI or GPU support; macOS and Ubuntu/Distrobox runtime validation remains necessary.
