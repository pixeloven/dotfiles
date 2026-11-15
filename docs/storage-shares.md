# Homelab NFS shares (storage-shares)

Opt-in, Linux only. With a server answer at `chezmoi init`, the machine mounts three NFS shares under `/var/mnt/storage-01`, each on first use:

| Mounted at | Server path | Mode |
|---|---|---|
| `/var/mnt/storage-01/<you>` | `/bulk/shares/<you>` (`<you>` is your login name) | read-write |
| `/var/mnt/storage-01/common` | `/bulk/shares/common` | read-write |
| `/var/mnt/storage-01/models` | `/bulk/models` | `storageModels`: read-write by default with `installTarget = distrobox` (Bazzite), read-only on a host (the creative VMs) |

A blank answer, the default, leaves the machine as it was: no command, no file and no apply step. macOS never asks. The repo holds no server address; it lives only in your untracked `~/.config/chezmoi/chezmoi.toml`.

## How it works

- `chezmoi init` asks `storageServer` (the NFS server's address, blank for none), then `storageModels` (`rw` or `ro`). `chezmoi apply` writes `~/.config/storage-shares/shares.conf` from them and installs the `storage-shares` command in `~/.local/bin`.
- `storage-shares install` writes one `.mount` and one `.automount` systemd unit per share to `/etc/systemd/system` with `sudo`, then enables the automounts. The units carry a `# Managed by dotfiles storage-shares` first line, and `install` and `remove` touch only those. `/etc` is writable and kept across updates on an image-based host such as Bazzite, so the units survive reboots and image updates.
- **Never blocks boot or a login:** only the automounts are enabled (in `remote-fs.target`), and setting one up needs no network. No unit requires a mount, so a mount failure can't hold up boot; that is what `nofail` does in fstab. A share mounts the first time something uses its path, waits up to 30 s for the server (`TimeoutSec=30`), and unmounts after 10 idle minutes. Shells don't touch the shares unless you `cd` into one.
- **Mount options:** `_netdev,hard,timeo=100,retrans=3,noatime`, plus `rw` or `ro`, with NFS v4.2, v4.1 or v3 negotiated with the server. `hard` keeps writes safe: if the server goes away while a share is in use, the processes using it wait until it comes back instead of getting silent write errors (`soft`). They can still be killed. An idle share is already unmounted, so an outage only affects what is using a share at that moment.
- **In the distrobox:** distrobox maps the host's `/var/mnt` into `ubuntu-dev` with slave propagation, so the box sees the shares at the same paths. Your uid and gid are the same in the box, so the server's owner and group checks treat both sides alike. On Bazzite, `storage-shares status`, `install` and `remove` run themselves on the host through `distrobox-host-exec`, while `check` and `comfy` run where you call them. So `storage-shares check` in the box shows what the box sees.
- **Every apply:** with a server set, `chezmoi apply` runs `storage-shares status --quiet`. It prints one line while the units still need `storage-shares install`, and never runs `sudo` itself. With Comfy Desktop selected (`comfyui`), it also runs `storage-shares comfy --quiet`.

## Comfy Desktop

The Linux Comfy Desktop (`comfyui-desktop-2`) keeps its shared model folders in `~/.config/comfyui-desktop-2/settings.json`, as the `modelsDirs` list. Its Settings window calls them Shared Models, and the first one is the primary, where downloads go. At each launch it writes a `--extra-model-paths-config` file from that list to `~/.local/share/comfyui-desktop-2/instance-model-paths/` and passes it to ComfyUI, so that file isn't the one to edit. `storage-shares comfy` adds `/var/mnt/storage-01/models` to the list once:

- read-write share: first, as the primary, so downloads land on the share; the folders already listed stay as extra ones.
- read-only share: after the local folder, which stays the primary. With an empty list, the local folder is `~/ComfyUI-Shared/models`, Comfy's default.

It never reorders a folder already listed, so a change you make in Comfy's settings sticks. It waits until `storage-shares install` has made the mount point (checking for it doesn't mount the share, so a down server can't stall an apply), until Comfy's first run has written `settings.json`, and skips while Comfy is running, since Comfy rewrites the file. Quit Comfy, then run `storage-shares comfy` (or `chezmoi apply`). On Bazzite this runs in the box, where Comfy is installed.

## Commands

```sh
storage-shares            # status: each share, its units and whether it is mounted
storage-shares install    # write and enable the units (sudo; from the box it runs on the host)
storage-shares check      # mount each share by using it, and test a write to each read-write share
storage-shares comfy      # add the models share to Comfy Desktop's models folders
storage-shares units      # print the units install writes
storage-shares remove     # disable and delete the units (sudo); the shares' contents stay
```

## Changing it

- Another server, or models read-only instead: edit `storageServer` or `storageModels` in `~/.config/chezmoi/chezmoi.toml` (or delete the line and run `chezmoi init` again), run `chezmoi apply`, then `storage-shares install`. A share already mounted picks up the change once it is unmounted.
- Turn it off: run `storage-shares remove`, then set `storageServer = ""` and run `chezmoi apply`.
- The share layout (the three shares and `/var/mnt/storage-01`) is in `home/dot_config/storage-shares/shares.conf.tmpl`.

The NFS exports themselves, the server's allowed clients and the router's address reservations are set up on the server and router, not by dotfiles.

## Tests

`tests/storage-shares.bats` runs the command against stub `sudo`, `systemctl`, `apt-get`, `pgrep` and `distrobox-host-exec`, writing units to a scratch directory. It covers the unit contents, install, remove, the box-to-host hop, check's failure messages and the Comfy settings edit. It doesn't mount a real share. `tests/render.bats` covers the init questions and shows that only Linux with a server gets the files.
