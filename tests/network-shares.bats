#!/usr/bin/env bats
# network-shares: the NFS share units, FS-Cache (cachefilesd) setup, install/remove, the box-to-host
# hop and check. Stub sudo, systemctl, apt-get, dnf, rpm-ostree, mount.nfs, findmnt, selinuxenabled,
# matchpathcon, semanage, restorecon and distrobox-host-exec log their calls into a throwaway HOME, and
# the units and cachefilesd files go to scratch paths, so nothing here touches the real /etc, systemd,
# a package manager, SELinux or a real mount.

REPO="$BATS_TEST_DIRNAME/.."
CMD="$REPO/home/dot_local/bin/executable_network-shares"

setup() {
  [ "$(uname -s)" = Linux ] || skip "network-shares is Linux only"
  export HOME="$(mktemp -d "${TMPDIR:-/tmp}/network-shares-XXXXXXXX")"
  export NETWORK_SHARES_CONF="$HOME/shares.conf" NETWORK_SHARES_UNIT_DIR="$HOME/units"
  export NETWORK_SHARES_CONTAINER_MARKER="$HOME/not-a-container" NETWORK_SHARES_OSTREE_MARKER="$HOME/not-ostree"
  export NETWORK_SHARES_CACHEFILESD_CONF="$HOME/etc/cachefilesd.conf" NETWORK_SHARES_CACHEFILESD_DEFAULT="$HOME/etc/default/cachefilesd"
  export NETWORK_SHARES_FSCACHE_PROC="$HOME/fscache-caches"
  unset INACTIVE SELINUX LABEL
  mkdir -p "$HOME/bin" "$HOME/units" "$HOME/etc/default"
  conf rw 0
  for c in apt-get dnf rpm-ostree mount.nfs semanage restorecon; do
    printf '#!/bin/sh\necho "%s $*" >> "$HOME/calls"\n' "$c" > "$HOME/bin/$c"
  done
  # Installing cachefilesd makes it present; systemctl says active unless INACTIVE is set.
  printf '#!/bin/sh\necho "apt-get $*" >> "$HOME/calls"\ncase "$*" in *cachefilesd*) printf "#!/bin/sh\\n" > "$HOME/bin/cachefilesd"; chmod +x "$HOME/bin/cachefilesd" ;; esac\n' > "$HOME/bin/apt-get"
  cat > "$HOME/bin/systemctl" <<'STUB'
#!/bin/sh
echo "systemctl $*" >> "$HOME/calls"
if [ "$1" = is-active ]; then
  [ -z "${INACTIVE:-}" ] || { [ "$2" = --quiet ] || echo inactive; exit 3; }
  [ "$2" = --quiet ] || echo active
fi
exit 0
STUB
  printf '#!/bin/sh\necho "sudo $*" >> "$HOME/calls"\nexec "$@"\n' > "$HOME/bin/sudo"
  printf '#!/bin/sh\n[ -n "${SELINUX:-}" ]\n' > "$HOME/bin/selinuxenabled"
  printf '#!/bin/sh\nshift; echo "$1\tsystem_u:object_r:${LABEL:-var_t}:s0"\n' > "$HOME/bin/matchpathcon"
  # The host side of the hop: same command, outside the box.
  printf '#!/bin/sh\necho "distrobox-host-exec $*" >> "$HOME/calls"\nNETWORK_SHARES_CONTAINER_MARKER=/nonexistent exec "$@"\n' > "$HOME/bin/distrobox-host-exec"
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
  : > "$HOME/calls"
}

teardown() { case "${HOME:-}" in */network-shares-*) rm -rf "$HOME" ;; esac; }

conf() { # <media rw|ro> <models cache 0|1> [models options] : three shares, cache in a scratch dir
  printf 'fscache %s/cache 30 25 20 30 25 20\nshare nas.example.lan /export/home /var/mnt/nas/home rw 0 -\nshare nas.example.lan /export/media /var/mnt/nas/media %s 0 -\nshare 192.0.2.10 /export/models /var/mnt/nas/models ro %s %s\n' \
    "$HOME" "$1" "$2" "${3:--}" > "$NETWORK_SHARES_CONF"
}

A='var-mnt-nas'

@test "units are named as systemd-escape names them and mount each share on first use, never at boot" {
  run "$CMD" units
  [ "$status" -eq 0 ]
  [[ "$output" == *"### $HOME/units/$A-home.mount"* ]] || false
  [[ "$output" == *"### $HOME/units/$A-models.automount"* ]] || false
  [[ "$output" == *$'What=nas.example.lan:/export/home\nWhere=/var/mnt/nas/home\nType=nfs'* ]] || false
  [[ "$output" == *'Options=rw,_netdev,hard,timeo=100,retrans=3,noatime'$'\n'* ]] || false
  [[ "$output" == *'TimeoutSec=30'* ]] || false
  [[ "$output" == *'TimeoutIdleSec=10min'* ]] || false
  # Only the automounts are installed into a target; no mount is wanted or required by anything.
  [ "$(grep -c '^WantedBy=remote-fs.target$' <<<"$output")" -eq 3 ]
  [[ "$output" != *RequiredBy* ]] || false
  # No cached share: no cachefilesd.conf
  [[ "$output" != *cachefilesd.conf* ]] || false
  if command -v systemd-escape >/dev/null 2>&1; then
    [ "$(systemd-escape --path --suffix=mount /var/mnt/nas/home)" = "$A-home.mount" ]
    [ "$(systemd-escape --path --suffix=mount /var/mnt/my-nas/v1.2)" = 'var-mnt-my\x2dnas-v1.2.mount' ]
  fi
}

@test "a cached share mounts with fsc, then its own options; fsc=<id> replaces the plain fsc" {
  conf ro 1
  run "$CMD" units
  [[ "$output" == *$'What=192.0.2.10:/export/models\nWhere=/var/mnt/nas/models\nType=nfs\nOptions=ro,_netdev,hard,timeo=100,retrans=3,noatime,fsc\n'* ]] || false
  [[ "$output" == *$'What=nas.example.lan:/export/media\nWhere=/var/mnt/nas/media\nType=nfs\nOptions=ro,_netdev,hard,timeo=100,retrans=3,noatime\n'* ]] || false
  conf rw 1 vers=4.2,fsc=models
  run "$CMD" units
  [[ "$output" == *$'Options=ro,_netdev,hard,timeo=100,retrans=3,noatime,vers=4.2,fsc=models\n'* ]] || false
  # ...and it shows the cachefilesd.conf install writes
  [[ "$output" == *"### $HOME/etc/cachefilesd.conf"* ]] || false
  [[ "$output" == *$'dir '"$HOME"$'/cache\nbrun 30%\nbcull 25%\nbstop 20%\nfrun 30%\nfcull 25%\nfstop 20%'* ]] || false
}

@test "a mount point through a symlink is written as its real path, since systemd needs that" {
  mkdir -p "$HOME/real"
  ln -s "$HOME/real" "$HOME/link"
  printf 'share nas.example.lan /export/media %s/link/media rw 0 -\n' "$HOME" > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [ "$status" -eq 0 ]
  [[ "$output" == *"Where=$HOME/real/media"* ]] || false
  [[ "$output" != *"$HOME/link"* ]] || false
}

@test "values that would reach a unit file are checked again" {
  printf 'share nas.example.lan;rm /export/media /var/mnt/nas/media rw 0 -\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad server"* ]] || false
  printf 'share nas.example.lan /export/media /var/mnt/../x rw 0 -\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"bad mount point"* ]] || false
  printf 'share nas.example.lan /export/media /var/mnt/nas/media rwx 0 -\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"must be rw or ro"* ]] || false
  printf 'share nas.example.lan /export/media /var/mnt/nas/media rw 0 vers=4.2;reboot\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"bad options"* ]] || false
  printf 'share nas.example.lan /export/media /var/mnt/nas/media rw 1 -\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"no fscache line"* ]] || false
  rm "$NETWORK_SHARES_CONF"
  run "$CMD" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"add nfsShares to the settings file and run chezmoi apply"* ]] || false
}

@test "install writes the six units with sudo, enables the automounts, and a second install writes nothing" {
  run "$CMD" install
  [ "$status" -eq 0 ]
  for s in home media models; do
    for k in mount automount; do
      [ -f "$HOME/units/$A-$s.$k" ]
      [ "$(stat -c %a "$HOME/units/$A-$s.$k")" = 644 ]
    done
  done
  grep -qxF "sudo systemctl daemon-reload" "$HOME/calls"
  grep -qxF "sudo systemctl enable --now $A-home.automount $A-media.automount $A-models.automount" "$HOME/calls"
  # nothing cached: cachefilesd is never touched
  ! grep -q cachefilesd "$HOME/calls"
  [[ "$output" == *"Next: network-shares check"* ]] || false
  run "$CMD" status --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  : > "$HOME/calls"
  run "$CMD" install
  [ "$status" -eq 0 ]
  ! grep -q 'sudo install' "$HOME/calls"
}

@test "with a cached share on an apt host, install adds cachefilesd, sets RUN=yes, writes its config and enables it" {
  conf rw 1
  printf '# Change to yes to enable\n#RUN=yes\n' > "$NETWORK_SHARES_CACHEFILESD_DEFAULT"
  printf 'dir /var/cache/fscache\nbrun 10%%\nsecctx system_u:system_r:cachefiles_kernel_t:s0\n' > "$NETWORK_SHARES_CACHEFILESD_CONF"
  rm -f "$HOME/bin/cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" command -v cachefilesd >/dev/null && skip "this machine has a real cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  [ "$status" -eq 0 ]
  grep -qxF "sudo apt-get install -y cachefilesd" "$HOME/calls"
  [ "$(cat "$NETWORK_SHARES_CACHEFILESD_DEFAULT")" = $'# Change to yes to enable\nRUN=yes' ]
  # the distro's file is kept once, and its SELinux line carried over
  grep -qx 'brun 10%' "$NETWORK_SHARES_CACHEFILESD_CONF.dotfiles-orig"
  head -n 1 "$NETWORK_SHARES_CACHEFILESD_CONF" | grep -q '^# Managed by dotfiles network-shares'
  grep -qx "dir $HOME/cache" "$NETWORK_SHARES_CACHEFILESD_CONF"
  grep -qx 'bcull 25%' "$NETWORK_SHARES_CACHEFILESD_CONF"
  grep -qx 'secctx system_u:system_r:cachefiles_kernel_t:s0' "$NETWORK_SHARES_CACHEFILESD_CONF"
  [ -d "$HOME/cache" ]
  grep -qxF "sudo systemctl enable --now cachefilesd" "$HOME/calls"
  # it was active, and its config changed: restarted to read it
  grep -qxF "sudo systemctl restart cachefilesd" "$HOME/calls"
  grep -q 'Options=ro,.*,noatime,fsc$' "$HOME/units/$A-models.mount"
  # no SELinux here: no labels
  ! grep -qE 'semanage|restorecon' "$HOME/calls"
  : > "$HOME/calls"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  ! grep -qE 'apt-get|restart|sudo install' "$HOME/calls"
}

@test "on an image-based host, install prints the rpm-ostree command and never layers a package" {
  conf rw 1
  touch "$NETWORK_SHARES_OSTREE_MARKER"
  rm -f "$HOME/bin/cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" command -v cachefilesd >/dev/null && skip "this machine has a real cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"  sudo rpm-ostree install --apply-live cachefilesd"* ]] || false
  [[ "$output" == *"  sudo rpm-ostree install cachefilesd && systemctl reboot"* ]] || false
  [[ "$output" == *"mount without FS-Cache until cachefilesd is installed"* ]] || false
  ! grep -qE 'rpm-ostree|apt-get|dnf' "$HOME/calls"
  [ ! -e "$NETWORK_SHARES_CACHEFILESD_CONF" ]
  # the shares are still installed, and status keeps saying what is left
  [ -f "$HOME/units/$A-models.automount" ]
  run "$CMD" status --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"FS-Cache for the cached shares is not set up"* ]] || false
  run "$CMD" status
  [[ "$output" == *"fs-cache $HOME/cache: cachefilesd not installed (network-shares install)"* ]] || false
}

@test "without apt, install uses dnf" {
  conf rw 1
  rm -f "$HOME/bin/apt-get" "$HOME/bin/cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" command -v apt-get >/dev/null && skip "this machine has a real apt-get"
  PATH="$HOME/bin:/usr/bin:/bin" command -v cachefilesd >/dev/null && skip "this machine has a real cachefilesd"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  grep -qxF "sudo dnf install -y cachefilesd" "$HOME/calls"
}

@test "on SELinux, a cache directory the policy doesn't label gets a cachefilesd label; a labelled one is only restored" {
  conf rw 1
  printf '#!/bin/sh\n' > "$HOME/bin/cachefilesd"; chmod +x "$HOME/bin/cachefilesd"
  SELINUX=1 run "$CMD" install
  [ "$status" -eq 0 ]
  grep -qxF "sudo semanage fcontext -a -t cachefiles_var_t $HOME/cache(/.*)?" "$HOME/calls"
  grep -qxF "sudo restorecon -R $HOME/cache" "$HOME/calls"
  : > "$HOME/calls"
  SELINUX=1 LABEL=cachefiles_var_t run "$CMD" install
  ! grep -q semanage "$HOME/calls"
  grep -qxF "sudo restorecon -R $HOME/cache" "$HOME/calls"
}

@test "status reports each share and whether cachefilesd runs with a cache bound" {
  conf rw 1
  printf '#!/bin/sh\n' > "$HOME/bin/cachefilesd"; chmod +x "$HOME/bin/cachefilesd"
  run "$CMD" status --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"on the host run: network-shares install (needs sudo)"* ]] || false
  "$CMD" install
  run "$CMD" status --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  INACTIVE=1 run "$CMD" status --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"FS-Cache for the cached shares is not set up"* ]] || false
  printf 'CACHE    REF   VOLS  OBJS  ACCES S NAME\n======== ===== ===== ===== ===== = ===============\n' > "$NETWORK_SHARES_FSCACHE_PROC"
  printf '00000001     2     1     0     1 A CacheFiles\n' >> "$NETWORK_SHARES_FSCACHE_PROC"
  run "$CMD" status
  [[ "$output" == *"/var/mnt/nas/models ro 192.0.2.10:/export/models cached: automount active, mounts on first use"* ]] || false
  [[ "$output" == *"fs-cache $HOME/cache: cachefilesd active, cache bound"* ]] || false
  conf ro 1
  run "$CMD" status
  [[ "$output" == *"/var/mnt/nas/media ro nas.example.lan:/export/media: out of date (network-shares install)"* ]] || false
}

@test "install drops units it wrote for a share that is gone, and leaves other units alone" {
  "$CMD" install
  printf '[Mount]\nWhat=other\n' > "$HOME/units/var-mnt-other.mount"
  printf 'share nas.example.lan /export/home /var/mnt/nas/home rw 0 -\n' > "$NETWORK_SHARES_CONF"
  run "$CMD" status
  [[ "$output" == *"no longer in $NETWORK_SHARES_CONF: "*"$A-media.automount"*"(network-shares install removes them)"* ]] || false
  : > "$HOME/calls"
  run "$CMD" install
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/units/$A-models.mount" ]
  [ ! -e "$HOME/units/$A-media.automount" ]
  [ -f "$HOME/units/$A-home.automount" ]
  [ -f "$HOME/units/var-mnt-other.mount" ]
  grep -qxF "sudo systemctl disable --now $A-models.automount" "$HOME/calls"
}

@test "remove disables and deletes only its own units, and leaves cachefilesd alone" {
  conf rw 1
  printf '#!/bin/sh\n' > "$HOME/bin/cachefilesd"; chmod +x "$HOME/bin/cachefilesd"
  "$CMD" install
  printf '[Mount]\nWhat=other\n' > "$HOME/units/var-mnt-other.mount"
  : > "$HOME/calls"
  run "$CMD" remove
  [ "$status" -eq 0 ]
  [ "$(ls "$HOME/units")" = var-mnt-other.mount ]
  grep -qxF "sudo systemctl disable --now $A-home.automount" "$HOME/calls"
  ! grep -q 'cachefilesd' "$HOME/calls"
  [ -f "$NETWORK_SHARES_CACHEFILESD_CONF" ]
  [[ "$output" == *"cachefilesd, $NETWORK_SHARES_CACHEFILESD_CONF and its cache are left as they are"* ]] || false
  run "$CMD" remove
  [[ "$output" == *"no units from network-shares"* ]] || false
}

@test "without an NFS client, install adds nfs-common on an apt host" {
  rm "$HOME/bin/mount.nfs"
  PATH="$HOME/bin:/usr/bin:/bin" command -v mount.nfs >/dev/null && skip "this machine has a real mount.nfs"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  [ "$status" -eq 0 ]
  grep -qxF "sudo apt-get install -y nfs-common" "$HOME/calls"
}

@test "in a distrobox, status, units, install and remove run on the host; check stays in the box" {
  touch "$NETWORK_SHARES_CONTAINER_MARKER"
  run "$CMD" install
  [ "$status" -eq 0 ]
  grep -q "^distrobox-host-exec env NETWORK_SHARES_CONF=$NETWORK_SHARES_CONF NETWORK_SHARES_UNIT_DIR=$HOME/units .* bash .*network-shares install$" "$HOME/calls"
  [ -f "$HOME/units/$A-home.automount" ]
  : > "$HOME/calls"
  run "$CMD" status --quiet
  [ "$status" -eq 0 ]
  grep -q 'network-shares status --quiet$' "$HOME/calls"
  : > "$HOME/calls"
  "$CMD" units > /dev/null
  grep -q 'network-shares units$' "$HOME/calls"
  : > "$HOME/calls"
  "$CMD" check || true
  ! grep -q distrobox-host-exec "$HOME/calls"
}

@test "check fails clearly when a share is missing or is not NFS" {
  printf 'share nas.example.lan /export/home %s/mnt/home rw 0 -\nshare nas.example.lan /export/models %s/mnt/models ro 0 -\n' "$HOME" "$HOME" > "$NETWORK_SHARES_CONF"
  mkdir -p "$HOME/mnt/models"
  run "$CMD" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"$HOME/mnt/home: FAIL: not there; on the host run: network-shares install"* ]] || false
  [[ "$output" == *"$HOME/mnt/models: FAIL: not an NFS mount"* ]] || false
}
