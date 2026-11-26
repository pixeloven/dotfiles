# Machine settings (schema v1)

The settings file is the one way to turn on this repo's per-machine features: network shares, FS-Cache and extra Comfy Desktop model folders, and to move Comfy Desktop's own folders. It is optional. **With no file, every feature is off**, and the repo works as it always has. The one default is Comfy Desktop's folders: with `comfyui` among the [workstation apps](workstation-apps.md#comfy-desktop-folders), they go under `~/ComfyUI` before Comfy's first run, file or no file.

- **Where:** `${XDG_CONFIG_HOME:-~/.config}/dotfiles/settings.toml`, from the environment chezmoi runs in (an unset or relative `XDG_CONFIG_HOME` means `~/.config`). If your shells set `XDG_CONFIG_HOME` differently in different places, such as a host and a container, keep it at `~/.config` or the same in both. `dotfiles-settings path` prints it, and `dotfiles-settings check` names it.
- **Who writes it:** you, by hand, or any tool you use to manage your machines. dotfiles only reads it; it never writes or manages this file.
- **When it is read:** at every `chezmoi apply`, so a change takes effect at the next apply, with no `chezmoi init`. Deleting the file turns the features off at the next apply (see each feature's page for what to undo on the system first).
- **Validation:** chezmoi validates the whole file before it writes anything. A bad file fails the apply with one message naming the file and the key, and nothing changes. Unknown keys are an error, so a typo or a key from a newer release is caught instead of ignored.
- **Check it:** `dotfiles-settings check` (or `dotfiles-settings check FILE` before you put a file in place) prints one line: what the file turns on, or the problem. `dotfiles-settings show` prints the settings as apply reads them, with the defaults filled in, as JSON.

## The file

Every key is optional except `schemaVersion`. This example uses every key, with example values.

```toml
schemaVersion = 1                      # required: this release reads schema 1

[[nfsShares]]                          # zero or more, in order. Linux only; each mounts on first use
server     = "nas.example.lan"         # host name or IPv4 address
export     = "/export/models"          # the path the server exports
mountPoint = "/var/mnt/nas/models"     # where it mounts on this machine
mode       = "ro"                      # "rw" (default) or "ro"
cache      = true                      # false (default) or true: cache reads on local disk (FS-Cache)
comfyuiModels = true                   # false (default) or true: a Comfy Desktop models folder

[[nfsShares]]
server     = "192.0.2.10"
export     = "/export/media"
mountPoint = "/var/mnt/nas/media"

[fscache]                              # the local cache, used only when a share has cache = true
dir   = "/var/cache/fscache"           # cache directory
brun  = 30                             # percentages of free space on the cache's filesystem:
bcull = 25                             #   culling starts below bcull and stops above brun;
bstop = 20                             #   below bstop the cache stops growing
frun  = 30                             # the same three for free files (inodes)
fcull = 25
fstop = 20

[comfyui]
root       = "~/ComfyUI"               # where Comfy Desktop's folders go before its first run. Linux only
modelsDirs = ["~/models-extra"]        # more folders Comfy Desktop reads models from. Linux only
```

## Keys

| Key | Type | Default | Rules | Since |
|---|---|---|---|---|
| `schemaVersion` | integer | (required) | `1` | v1.0.0 |
| `nfsShares` | list of tables | none | Shares mount on first use ([network shares](network-shares.md)). Linux only; on macOS apply prints one line and skips them | v1.0.0 |
| `nfsShares[].server` | string | (required) | A host name or IPv4 address: letters, digits and `._-`, starting with a letter or digit | v1.0.0 |
| `nfsShares[].export` | string | (required) | An absolute path of letters, digits and `/_.-` | v1.0.0 |
| `nfsShares[].mountPoint` | string | (required) | An absolute path of at least two parts made of letters, digits and `_.-` (no trailing `/`, `.` or `..`), not under `/bin`, `/boot`, `/dev`, `/etc`, `/lib`, `/lib64`, `/proc`, `/run`, `/sbin`, `/sys` or `/usr`, and not `/var/cache`, `/var/lib`, `/var/log` or `/var/tmp` itself. network-shares checks the same after resolving symlinks. Unique, and none inside another. A path through a symlink (such as `/mnt` on an image-based system, a link to `/var/mnt`) is resolved when the units are written | v1.0.0 |
| `nfsShares[].mode` | string | `"rw"` | `"rw"` or `"ro"` | v1.0.0 |
| `nfsShares[].cache` | boolean | `false` | `true` adds `fsc`, so reads are cached on local disk by FS-Cache. Best on read-mostly shares: opening a file for writing drops its cached copy | v1.0.0 |
| `nfsShares[].comfyuiModels` | boolean | `false` | `true` adds the share's `mountPoint` to Comfy Desktop's Shared Models, after its own models folder and before `comfyui.modelsDirs` ([workstation apps](workstation-apps.md#comfy-desktop-model-folders)), so the mount point is written once | v1.1.0 |
| `fscache` | table | the defaults below | Read only when some share has `cache = true`; allowed (and unused) otherwise | v1.0.0 |
| `fscache.dir` | string | `"/var/cache/fscache"` | The same path rules as `mountPoint`. On an SELinux system, a directory other than the default is labelled for cachefilesd when network-shares installs | v1.0.0 |
| `fscache.brun`, `bcull`, `bstop` | integer | `30`, `25`, `20` | Whole percentages from 0 to 99 of free space on the cache directory's filesystem, with `bstop < bcull < brun` | v1.0.0 |
| `fscache.frun`, `fcull`, `fstop` | integer | `30`, `25`, `20` | The same, for free files (inodes), with `fstop < fcull < frun` | v1.0.0 |
| `comfyui` | table | none | | v1.0.0 |
| `comfyui.root` | string | `"~/ComfyUI"` | An absolute or `~/` folder path, not `/` or the home folder itself. With `comfyui` among the workstation apps, Comfy Desktop's install, models, input, output and cache folders are set under it before Comfy's first run ([workstation apps](workstation-apps.md#comfy-desktop-folders)). Changing it after that first run changes nothing. Linux only for now | v1.1.0 |
| `comfyui.modelsDirs` | list of strings | none | Absolute or `~/` folder paths, added to Comfy Desktop's Shared Models, after its first folder ([workstation apps](workstation-apps.md#comfy-desktop-model-folders)). Linux only for now | v1.0.0 |

The cache limits are percentages of **free** space on the filesystem that holds the cache, not a size, and they are set per machine. cachefilesd lets the cache grow freely while free space is above `bcull`. Below `bcull` it starts culling (deleting the least recently used cached files) and keeps culling until free space is back above `brun`. Below `bstop` it caches nothing new. There is no fixed size cap unless the cache directory is on its own filesystem.

So the room the cache gets is the gap between the disk's free space and `bcull`, and that gap shrinks as your own data grows. With the defaults (30/25/20) on a disk that is 66 % full (34 % free), the cache can take about 9 % of the disk before culling, and settles between about 4 % and 9 % (on a 2 TB disk, roughly 80 to 180 GB). Once the disk is 75 % full, the cache gets nothing. The defaults suit a disk shared with your data, where the cache must never crowd it out. If the cache should get more room on a given machine, lower the three numbers in that machine's settings file. For example, 15/10/5 lets it grow until 10 % of the disk is free (about 24 % of the disk at 66 % full) and still never takes the last 5 %. On a disk given only to the cache, cachefilesd's own 10/7/3 uses most of it.

## Versions

- `schemaVersion` is a whole number, separate from the repo's release tags. It changes only for a breaking change: a key renamed, removed or given a new meaning, or a stricter rule that rejects files that used to be valid.
- A new optional key keeps `schemaVersion = 1`, and the Keys table says which release added it. `nfsShares[].options` (extra NFS mount options) is reserved for such a key: schema v1 has no `options` yet, so a share that sets it fails with "unknown key" until a v1.x release adds it, with no `schemaVersion` change. A file that uses a key newer than the installed dotfiles fails with "unknown key", so pin the dotfiles release your settings were written for.
- After a schema change, the next release still reads the old version, and prints one line saying to update, for at least one minor release.

## For tools that write this file

- Write the whole file in one step (write a temporary file, then rename it), and run `dotfiles-settings check FILE` on it first.
- The file is plain TOML: write it with any TOML library. Write the keys only when you mean them; leaving one out takes the default.
- The values are only ever written into this file. dotfiles reads nothing else for these features, and the init answers in `~/.config/chezmoi/chezmoi.toml` stay separate.

## How it works

`home/.chezmoitemplates/dotfiles-settings` is the reference implementation: it reads the file with `include` and `fromToml`, checks each key, and returns the settings with the defaults filled in as JSON. `home/.chezmoiignore` calls it first, which is what fails a bad file before any write. The templates for each feature call it again. `home/.chezmoiversion` requires chezmoi 2.60.0, the oldest release with every template function the repo's templates use: `promptMultichoiceOnce` (in `.chezmoi.toml.tmpl`) arrived in 2.60.0, and the rest are older (`includeTemplate` 2.22.0, `fromToml` and `toToml` 2.19.0, `.chezmoi.workingTree` 2.9.1, `.chezmoiroot` 2.8.0; `include`, `stat`, `joinPath`, `output`, `promptChoiceOnce`, `fromJson` and `toJson` are all in 2.59). An older chezmoi stops with a clear message instead of misreading the file. The data key `dotfilesSettingsFile` replaces the path; it exists for tests, which render the files in `tests/fixtures/settings/` through it (`tests/settings.bats`, `tests/render.bats`).
