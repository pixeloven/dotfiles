# Network shares (network-shares)

Opt-in, Linux only. List NFS shares under `nfsShares` in the [settings file](settings.md) and the machine mounts each one on first use, so a server that is down never holds up boot. A share with `cache = true` also caches its reads on local disk with FS-Cache.

With no settings file, or no `nfsShares`, nothing here exists: no command, no file and no apply step. On macOS apply prints one line and skips the shares. The repo holds no server names or paths; they live only in your settings file.

```toml
# ~/.config/dotfiles/settings.toml
schemaVersion = 1

[[nfsShares]]
server = "nas.example.lan"
export = "/export/models"
mountPoint = "/var/mnt/nas/models"
mode = "ro"
cache = true

[[nfsShares]]
server = "nas.example.lan"
export = "/export/media"
mountPoint = "/var/mnt/nas/media"
```

## How it works

- `chezmoi apply` validates the settings file, writes `~/.config/network-shares/shares.conf` from `nfsShares` and `fscache`, and installs the `network-shares` command in `~/.local/bin`.
- `network-shares install` writes one `.mount` and one `.automount` systemd unit per share to `/etc/systemd/system` with `sudo`, then enables the automounts. The units carry a `# Managed by dotfiles network-shares` first line, and `install` and `remove` touch only those. `/etc` is writable and kept across updates on an image-based host such as Bazzite, so the units survive reboots and image updates. A mount point through a symlink (such as `/mnt`, a link to `/var/mnt` on an image-based host) is written as its real path, because systemd needs one.
- **Never blocks boot or a login:** only the automounts are enabled (in `remote-fs.target`), and setting one up needs no network. No unit requires a mount, so a mount failure can't hold up boot; that is what `nofail` does in fstab. A share mounts the first time something uses its path, waits up to 30 s for the server (`TimeoutSec=30`), and unmounts after 10 idle minutes. Shells don't touch the shares unless you `cd` into one.
- **Mount options:** `_netdev,hard,timeo=100,retrans=3,noatime`, plus `rw` or `ro`, then `fsc` for a cached share. These are fixed: `mode` and `cache` are the only per-share choices. The NFS version is negotiated with the server. `hard` keeps writes safe: if the server goes away while a share is in use, the processes using it wait until it comes back instead of getting silent write errors (`soft`). They can still be killed. An idle share is already unmounted, so an outage only affects what is using a share at that moment.
- **In a distrobox:** a share mounted under a path distrobox shares with the box (such as `/var/mnt`, or your home) shows in the box at the same path. Your uid and gid are the same in the box, so the server's owner and group checks treat both sides alike. In a box, `network-shares status`, `units`, `install` and `remove` run themselves on the host through `distrobox-host-exec`, while `check` runs where you call it, so `network-shares check` in the box shows what the box sees.
- **Every apply:** with shares listed, `chezmoi apply` runs `network-shares status --quiet`. It prints one line while the units (or FS-Cache, for a cached share) still need `network-shares install`, and never runs `sudo` itself.

## FS-Cache

A share with `cache = true` mounts with `fsc`, so the kernel keeps a copy of what you read in a local cache directory, run by the `cachefilesd` daemon. It suits read-mostly shares, such as a model or media library read by several machines. Opening a file for writing drops its cached copy, so it helps little on a share you mostly write to. Until cachefilesd runs, a cached share still mounts, uncached.

When some share is cached, `network-shares install` also:

1. **Installs cachefilesd when it is missing.** On an apt host it runs `sudo apt-get install -y cachefilesd`, and on a dnf host `sudo dnf install -y cachefilesd`. On an image-based host (`/run/ostree-booted`, such as Bazzite) it never layers a package: it prints the command and carries on with the mounts. Run it yourself, then run `network-shares install` again:

   ```sh
   sudo rpm-ostree install --apply-live cachefilesd
   ```

   If an update is already staged (`rpm-ostree status` shows one), `--apply-live` may refuse, or apply only at the next boot. Then layer it for the next boot instead, and reboot:

   ```sh
   sudo rpm-ostree install cachefilesd && systemctl reboot
   ```

2. **Sets `RUN=yes`** in `/etc/default/cachefilesd` where that file exists (Debian and Ubuntu start the daemon only with it).
3. **Writes `/etc/cachefilesd.conf`** from the `fscache` settings: the cache directory and the six limits, with the distro's SELinux `secctx` line kept. The distro's original file is kept once as `/etc/cachefilesd.conf.dotfiles-orig`.
4. **Labels the cache directory on SELinux hosts.** The policy already labels the default `/var/cache/fscache`, so that only gets `restorecon`. Another directory first gets a local `semanage fcontext` rule for `cachefiles_var_t`.
5. **Enables cachefilesd** (`systemctl enable --now`), and restarts it when its config changed.

The limits are percentages of **free** space (and free files) on the cache directory's filesystem, not a size. With the defaults (30/25/20), the cache grows while more than 30 % of that filesystem is free, gives space back once free space falls below 25 %, and stops growing below 20 %. On a disk shared with your data that keeps the cache out of the way; for a hard size cap, put `fscache.dir` on its own filesystem. [settings.md](settings.md) has the rules.

`network-shares status` shows whether cachefilesd is running and whether a cache is bound (`/proc/fs/fscache/caches`). `network-shares check` shows `fsc` on each cached share that is mounted with it.

## Commands

```sh
network-shares            # status: each share, its units and whether it is mounted; FS-Cache
network-shares install    # write and enable the units, and set up FS-Cache (sudo; from a box it runs on the host)
network-shares check      # mount each share by using it, and test a write to each read-write share
network-shares units      # print the units (and cachefilesd.conf) install writes
network-shares remove     # disable and delete the units (sudo); the shares' contents stay
```

## Changing it

- Add, change or drop a share: edit `nfsShares` in the settings file, check it with `dotfiles-settings check`, run `chezmoi apply`, then `network-shares install`. Install removes the units of a share that is gone. A share already mounted picks up a change once it is unmounted.
- Cache settings: edit `fscache` or a share's `cache`, then the same steps.
- Turn it off: run `network-shares remove` first, then delete `nfsShares` (or the whole settings file) and run `chezmoi apply`. `remove` leaves cachefilesd, its config and the cache as they are; `sudo systemctl disable --now cachefilesd` stops it, and the package you installed stays until you remove it.

The exports themselves and which clients the server allows are set up on the server, not by dotfiles.

## Tests

`tests/network-shares.bats` runs the command against stub `sudo`, `systemctl`, `apt-get`, `dnf`, `rpm-ostree`, the SELinux tools and `distrobox-host-exec`, writing units and cachefilesd's files to scratch paths. It covers the unit contents, the FS-Cache setup on apt, dnf and image-based hosts, install, remove, the box-to-host hop and check's failure messages. It doesn't mount a real share or run a real cache. `tests/render.bats` shows that only Linux with `nfsShares` gets the files, and `tests/settings.bats` covers the validation.
