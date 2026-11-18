# Machine settings (schema v1)

The settings file is the one way to turn on this repo's per-machine features: network shares, FS-Cache and Comfy Desktop model folders. It is optional. **With no file, every feature is off**, and the repo works as it always has.

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
options    = ["vers=4.2"]              # extra NFS mount options (default none)

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
modelsDirs = ["/var/mnt/nas/models"]   # folders Comfy Desktop also reads models from. Linux only
```

## Keys

| Key | Type | Default | Rules | Since |
|---|---|---|---|---|
| `schemaVersion` | integer | (required) | `1` | v1.0.0 |
| `nfsShares` | list of tables | none | Shares mount on first use ([network shares](network-shares.md)). Linux only; on macOS apply prints one line and skips them | v1.0.0 |
| `nfsShares[].server` | string | (required) | A host name or IPv4 address: letters, digits and `._-`, starting with a letter or digit | v1.0.0 |
| `nfsShares[].export` | string | (required) | An absolute path of letters, digits and `/_.-` | v1.0.0 |
| `nfsShares[].mountPoint` | string | (required) | An absolute path of at least two parts made of letters, digits and `_.-` (no trailing `/`, `.` or `..`), not under `/boot`, `/dev`, `/etc`, `/proc`, `/run`, `/sys` or `/usr`. Unique, and none inside another. A path through a symlink (such as `/mnt` on an image-based system, a link to `/var/mnt`) is resolved when the units are written | v1.0.0 |
| `nfsShares[].mode` | string | `"rw"` | `"rw"` or `"ro"` | v1.0.0 |
| `nfsShares[].cache` | boolean | `false` | `true` adds `fsc`, so reads are cached on local disk by FS-Cache. Best on read-mostly shares: opening a file for writing drops its cached copy | v1.0.0 |
| `nfsShares[].options` | list of strings | none | Each `name` or `name=value` (lower-case letters, digits and `_`; values of letters, digits and `._:-`). The options network-shares sets itself are refused: `rw`, `ro`, `_netdev`, `hard`, `soft`, `timeo`, `retrans`, `noatime`, `fsc` and `nofsc`. `fsc=<id>` is allowed with `cache = true`, to give two shares from one server their own cache keys | v1.0.0 |
| `fscache` | table | the defaults below | Read only when some share has `cache = true`; allowed (and unused) otherwise | v1.0.0 |
| `fscache.dir` | string | `"/var/cache/fscache"` | The same path rules as `mountPoint`. On an SELinux system, a directory other than the default is labelled for cachefilesd when network-shares installs | v1.0.0 |
| `fscache.brun`, `bcull`, `bstop` | integer | `30`, `25`, `20` | Whole percentages from 0 to 99 of free space on the cache directory's filesystem, with `bstop < bcull < brun` | v1.0.0 |
| `fscache.frun`, `fcull`, `fstop` | integer | `30`, `25`, `20` | The same, for free files (inodes), with `fstop < fcull < frun` | v1.0.0 |
| `comfyui` | table | none | | v1.0.0 |
| `comfyui.modelsDirs` | list of strings | none | Absolute or `~/` folder paths, added to Comfy Desktop's Shared Models ([workstation apps](workstation-apps.md#comfy-desktop-model-folders)). Linux only for now | v1.0.0 |

The cache limits are percentages of **free** space on the filesystem that holds the cache, not a size. With the defaults, the cache grows while more than 30 % of that filesystem is free, gives space back to other data once free space falls below 25 %, and stops growing below 20 %. There is no fixed size cap unless the cache directory is on its own filesystem. On a large disk shared with your data, the defaults keep the cache out of the way; on a disk given only to the cache, lower limits (such as cachefilesd's own 10/7/3) use more of it.

## Versions

- `schemaVersion` is a whole number, separate from the repo's release tags. It changes only for a breaking change: a key renamed, removed or given a new meaning, or a stricter rule that rejects files that used to be valid.
- A new optional key keeps `schemaVersion = 1`, and the Keys table says which release added it. A file that uses a key newer than the installed dotfiles fails with "unknown key", so pin the dotfiles release your settings were written for.
- After a schema change, the next release still reads the old version, and prints one line saying to update, for at least one minor release.

## For tools that write this file

- Write the whole file in one step (write a temporary file, then rename it), and run `dotfiles-settings check FILE` on it first.
- The file is plain TOML: write it with any TOML library. Write the keys only when you mean them; leaving one out takes the default.
- The values are only ever written into this file. dotfiles reads nothing else for these features, and the init answers in `~/.config/chezmoi/chezmoi.toml` stay separate.

## How it works

`home/.chezmoitemplates/dotfiles-settings` is the reference implementation: it reads the file with `include` and `fromToml`, checks each key, and returns the settings with the defaults filled in as JSON. `home/.chezmoiignore` calls it first, which is what fails a bad file before any write. The templates for each feature call it again. `home/.chezmoiversion` requires chezmoi 2.74.0, the release these templates are tested with (Homebrew's chezmoi meets it); an older chezmoi stops with a clear message instead of misreading the file. The data key `dotfilesSettingsFile` replaces the path; it exists for tests, which render the files in `tests/fixtures/settings/` through it (`tests/settings.bats`, `tests/render.bats`).
