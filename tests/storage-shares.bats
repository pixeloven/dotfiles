#!/usr/bin/env bats
# storage-shares: the homelab NFS share units, install/remove, the box-to-host hop, check and the
# Comfy Desktop models folder. Stub sudo, systemctl, apt-get, mount.nfs, pgrep, findmnt and
# distrobox-host-exec log their calls into a throwaway HOME, and the units go to a scratch directory,
# so nothing here touches the real /etc, systemd, a real mount or a real Comfy Desktop.

REPO="$BATS_TEST_DIRNAME/.."
CMD="$REPO/home/dot_local/bin/executable_storage-shares"

setup() {
  [ "$(uname -s)" = Linux ] || skip "storage-shares is Linux only"
  export HOME="$(mktemp -d "${TMPDIR:-/tmp}/storage-shares-XXXXXXXX")"
  export STORAGE_SHARES_CONF="$HOME/shares.conf" STORAGE_SHARES_UNIT_DIR="$HOME/units"
  export STORAGE_SHARES_CONTAINER_MARKER="$HOME/not-a-container" STORAGE_SHARES_COMFY_SETTINGS="$HOME/comfy/settings.json"
  unset COMFY_RUNNING
  mkdir -p "$HOME/bin" "$HOME/units" "$HOME/comfy"
  conf rw
  for c in systemctl apt-get mount.nfs; do
    printf '#!/bin/sh\necho "%s $*" >> "$HOME/calls"\n' "$c" > "$HOME/bin/$c"
  done
  printf '#!/bin/sh\necho "sudo $*" >> "$HOME/calls"\nexec "$@"\n' > "$HOME/bin/sudo"
  printf '#!/bin/sh\n[ -n "${COMFY_RUNNING:-}" ]\n' > "$HOME/bin/pgrep"
  # The host side of the hop: same command, outside the box.
  printf '#!/bin/sh\necho "distrobox-host-exec $*" >> "$HOME/calls"\nSTORAGE_SHARES_CONTAINER_MARKER=/nonexistent exec "$@"\n' > "$HOME/bin/distrobox-host-exec"
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
  : > "$HOME/calls"
}

teardown() { case "${HOME:-}" in */storage-shares-*) rm -rf "$HOME" ;; esac; }

conf() { # <models rw|ro>
  printf 'server 192.0.2.10\nroot /var/mnt/storage-01\nshare me /bulk/shares/me rw\nshare common /bulk/shares/common rw\nshare models /bulk/models %s\n' "$1" > "$STORAGE_SHARES_CONF"
}

A='var-mnt-storage\x2d01'

@test "units are named as systemd-escape names them and mount each share on first use, never at boot" {
  run "$CMD" units
  [ "$status" -eq 0 ]
  [[ "$output" == *"### $HOME/units/$A-me.mount"* ]] || false
  [[ "$output" == *"### $HOME/units/$A-models.automount"* ]] || false
  [[ "$output" == *$'What=192.0.2.10:/bulk/shares/me\nWhere=/var/mnt/storage-01/me\nType=nfs'* ]] || false
  [[ "$output" == *'Options=rw,_netdev,hard,timeo=100,retrans=3,noatime'* ]] || false
  [[ "$output" == *'TimeoutSec=30'* ]] || false
  [[ "$output" == *'TimeoutIdleSec=10min'* ]] || false
  # Only the automounts are installed into a target; no mount is wanted or required by anything.
  [ "$(grep -c '^WantedBy=remote-fs.target$' <<<"$output")" -eq 3 ]
  [[ "$output" != *RequiredBy* ]] || false
  if command -v systemd-escape >/dev/null 2>&1; then
    [ "$(systemd-escape --path --suffix=mount /var/mnt/storage-01/me)" = "$A-me.mount" ]
  fi
}

@test "a read-only models share mounts ro" {
  conf ro
  run "$CMD" units
  [[ "$output" == *$'What=192.0.2.10:/bulk/models\nWhere=/var/mnt/storage-01/models\nType=nfs\nOptions=ro,'* ]] || false
}

@test "values that would reach a unit file are checked first" {
  printf 'server 192.0.2.10;rm\nroot /var/mnt/storage-01\nshare me /bulk/shares/me rw\n' > "$STORAGE_SHARES_CONF"
  run "$CMD" units
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad or missing server"* ]] || false
  printf 'server 192.0.2.10\nroot /var/mnt/storage-01\nshare ../x /bulk/x rw\n' > "$STORAGE_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"bad share name"* ]] || false
  printf 'server 192.0.2.10\nroot /var/mnt/storage-01\nshare x /bulk/x rwx\n' > "$STORAGE_SHARES_CONF"
  run "$CMD" units
  [[ "$output" == *"must be rw or ro"* ]] || false
  rm "$STORAGE_SHARES_CONF"
  run "$CMD" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"set storageServer with chezmoi init"* ]] || false
}

@test "install writes the six units with sudo, enables the automounts, and a second install writes nothing" {
  run "$CMD" install
  [ "$status" -eq 0 ]
  for s in me common models; do
    for k in mount automount; do
      [ -f "$HOME/units/$A-$s.$k" ]
      [ "$(stat -c %a "$HOME/units/$A-$s.$k")" = 644 ]
    done
  done
  grep -qxF "sudo systemctl daemon-reload" "$HOME/calls"
  grep -qxF "sudo systemctl enable --now $A-me.automount $A-common.automount $A-models.automount" "$HOME/calls"
  [[ "$output" == *"Next: storage-shares check"* ]] || false
  run "$CMD" status --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  : > "$HOME/calls"
  run "$CMD" install
  [ "$status" -eq 0 ]
  ! grep -q 'sudo install' "$HOME/calls"
}

@test "status --quiet says what to run until the units are installed and current" {
  run "$CMD" status --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"on the host run: storage-shares install (needs sudo)"* ]] || false
  "$CMD" install
  conf ro
  run "$CMD" status --quiet
  [ "$status" -eq 1 ]
  run "$CMD" status
  [[ "$output" == *"models   ro 192.0.2.10:/bulk/models -> /var/mnt/storage-01/models: out of date (storage-shares install)"* ]] || false
}

@test "install drops units it wrote for a share that is gone, and leaves other units alone" {
  "$CMD" install
  printf '[Mount]\nWhat=other\n' > "$HOME/units/var-mnt-other.mount"
  printf 'server 192.0.2.10\nroot /var/mnt/storage-01\nshare me /bulk/shares/me rw\n' > "$STORAGE_SHARES_CONF"
  : > "$HOME/calls"
  run "$CMD" install
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/units/$A-models.mount" ]
  [ ! -e "$HOME/units/$A-common.automount" ]
  [ -f "$HOME/units/$A-me.automount" ]
  [ -f "$HOME/units/var-mnt-other.mount" ]
  grep -qxF "sudo systemctl disable --now $A-models.automount" "$HOME/calls"
}

@test "remove disables and deletes only its own units" {
  "$CMD" install
  printf '[Mount]\nWhat=other\n' > "$HOME/units/var-mnt-other.mount"
  : > "$HOME/calls"
  run "$CMD" remove
  [ "$status" -eq 0 ]
  [ "$(ls "$HOME/units")" = var-mnt-other.mount ]
  grep -qxF "sudo systemctl disable --now $A-me.automount" "$HOME/calls"
  run "$CMD" remove
  [[ "$output" == *"no units from storage-shares"* ]] || false
}

@test "without an NFS client, install adds nfs-common on an apt host" {
  rm "$HOME/bin/mount.nfs"
  PATH="$HOME/bin:/usr/bin:/bin" command -v mount.nfs >/dev/null && skip "this machine has a real mount.nfs"
  PATH="$HOME/bin:/usr/bin:/bin" run "$CMD" install
  [ "$status" -eq 0 ]
  grep -qxF "sudo apt-get install -y nfs-common" "$HOME/calls"
}

@test "in a distrobox, status, install and remove run on the host; check and comfy stay in the box" {
  touch "$STORAGE_SHARES_CONTAINER_MARKER"
  run "$CMD" install
  [ "$status" -eq 0 ]
  grep -q "^distrobox-host-exec env STORAGE_SHARES_CONF=$STORAGE_SHARES_CONF STORAGE_SHARES_UNIT_DIR=$HOME/units bash .*storage-shares install$" "$HOME/calls"
  [ -f "$HOME/units/$A-me.automount" ]
  : > "$HOME/calls"
  run "$CMD" status --quiet
  [ "$status" -eq 0 ]
  grep -q 'storage-shares status --quiet$' "$HOME/calls"
  : > "$HOME/calls"
  "$CMD" check || true
  "$CMD" comfy || true
  [ ! -s "$HOME/calls" ]
}

@test "check fails clearly when a share is missing or is not NFS" {
  printf 'server 192.0.2.10\nroot %s/mnt\nshare me /bulk/shares/me rw\nshare models /bulk/models ro\n' "$HOME" > "$STORAGE_SHARES_CONF"
  mkdir -p "$HOME/mnt/models"
  run "$CMD" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"me: FAIL: no $HOME/mnt/me; on the host run: storage-shares install"* ]] || false
  [[ "$output" == *"models: FAIL: $HOME/mnt/models is not an NFS mount"* ]] || false
}

comfy_settings() { printf '%s\n' "$1" > "$STORAGE_SHARES_COMFY_SETTINGS"; }

comfy_root() { # <models rw|ro> : shares under a scratch root, with the models mount point in place
  conf "$1"
  sed -i "s#^root .*#root $HOME/mnt#" "$STORAGE_SHARES_CONF"
  M="$HOME/mnt/models"
  mkdir -p "$M"
}

@test "comfy makes a read-write models share Comfy's primary folder, keeping the rest" {
  comfy_root rw
  comfy_settings '{"cacheDir":"/c","modelsDirs":["/home/u/ComfyUI-Shared/models"],"installDir":"/i"}'
  run "$CMD" comfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"primary models folder"* ]] || false
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = "[\"$M\",\"/home/u/ComfyUI-Shared/models\"]" ]
  [ "$(jq -c 'del(.modelsDirs)' "$STORAGE_SHARES_COMFY_SETTINGS")" = '{"cacheDir":"/c","installDir":"/i"}' ]
  run "$CMD" comfy --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq '.modelsDirs | length' "$STORAGE_SHARES_COMFY_SETTINGS")" -eq 2 ]
}

@test "comfy adds a read-only models share after the local folder, which stays primary" {
  comfy_root ro
  comfy_settings '{"modelsDirs":["/home/u/ComfyUI-Shared/models"]}'
  "$CMD" comfy
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = "[\"/home/u/ComfyUI-Shared/models\",\"$M\"]" ]
  comfy_settings '{"onAppClose":"quit"}'
  "$CMD" comfy
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = "[\"$HOME/ComfyUI-Shared/models\",\"$M\"]" ]
}

@test "comfy never reorders a folder already listed" {
  comfy_root rw
  comfy_settings "{\"modelsDirs\":[\"/a\",\"$M\"]}"
  run "$CMD" comfy
  [ "$status" -eq 0 ]
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = "[\"/a\",\"$M\"]" ]
}

@test "comfy waits for the shares, for Comfy's first run and for it to quit, and leaves a file it doesn't expect alone" {
  comfy_settings '{"modelsDirs":["/a"]}'
  run "$CMD" comfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"no /var/mnt/storage-01/models yet; on the host run storage-shares install"* ]] || false
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = '["/a"]' ]
  comfy_root rw
  rm "$STORAGE_SHARES_COMFY_SETTINGS"
  run "$CMD" comfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"open Comfy Desktop once"* ]] || false
  run "$CMD" comfy --quiet
  [ -z "$output" ]
  comfy_settings '{"modelsDirs":["/a"]}'
  COMFY_RUNNING=1 run "$CMD" comfy
  [[ "$output" == *"Comfy Desktop is running"* ]] || false
  [ "$(jq -c .modelsDirs "$STORAGE_SHARES_COMFY_SETTINGS")" = '["/a"]' ]
  comfy_settings 'not json'
  run "$CMD" comfy
  [ "$status" -eq 1 ]
  [ "$(cat "$STORAGE_SHARES_COMFY_SETTINGS")" = 'not json' ]
}
