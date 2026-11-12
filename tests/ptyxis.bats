#!/usr/bin/env bats
# The Ptyxis settings script and its drift check, against stub gsettings and distrobox-host-exec.
# Nothing here reads or writes real GSettings: every gsettings on PATH is a stub.

REAL_REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl"
UUID=0123456789abcdef
PROFILE="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$UUID/"

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" GS_DB="$TMP/gsettings.db" GS_LOG="$TMP/gsettings.log" HOST_BIN="$TMP/host"
  mkdir -p "$HOME" "$TMP/bin" "$HOST_BIN"
  : > "$GS_LOG"
  printf 'org.gnome.Ptyxis\tdefault-profile-uuid\t%s\n' "'$UUID'" > "$GS_DB"

  # The host's gsettings with the Ptyxis schema: values live in $GS_DB as schema<TAB>key<TAB>value.
  cat > "$HOST_BIN/gsettings" <<'STUB'
#!/bin/sh
echo "host $*" >> "$GS_LOG"
[ -e "$GS_DB" ] || { echo "No such schema" >&2; exit 1; }
case "$1" in
  list-keys) echo font-name ;;
  get) awk -F '\t' -v s="$2" -v k="$3" '$1 == s && $2 == k { v = $3 } END { print v }' "$GS_DB" ;;
  set) printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$GS_DB" ;;
esac
STUB
  cat > "$TMP/bin/distrobox-host-exec" <<'STUB'
#!/bin/sh
PATH="$HOST_BIN:$PATH" exec "$@"
STUB
  # Inside the container gsettings has no Ptyxis schema.
  cat > "$TMP/bin/gsettings" <<'STUB'
#!/bin/sh
echo "local $*" >> "$GS_LOG"
echo "No such schema" >&2
exit 1
STUB
  # The host's podman knows the box by name; BOX_ID unset means there is no box.
  cat > "$HOST_BIN/podman" <<'STUB'
#!/bin/sh
[ "$1 $2" = "inspect ubuntu-dev" ] && [ -n "${BOX_ID:-}" ] || exit 125
echo "$BOX_ID"
STUB
  printf '#!/bin/sh\n' > "$TMP/bin/brew"
  chmod +x "$HOST_BIN/gsettings" "$HOST_BIN/podman" "$TMP/bin/"*
  unset BOX_ID
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

config() { # <terminal> <container> [installTarget] : a chezmoi config for Linux with these answers
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "%s"\ncontainer = %s\ninstallTarget = "%s"\n' "$REAL_REPO" "$1" "$2" "${3:-host}" > "$TMP/chezmoi.toml"
}

ptyxis_script() { # <terminal> <container> [installTarget] : run the script as rendered for Linux with these answers
  config "$1" "$2" "${3:-host}"
  chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template \
    --override-data '{"chezmoi":{"os":"linux"}}' < "$REAL_REPO/$SCRIPT" > "$TMP/ptyxis.sh"
  sh "$TMP/ptyxis.sh"
}

setting() { # <schema> <key> : the stored value
  awk -F '\t' -v s="$1" -v k="$2" '$1 == s && $2 == k { v = $3 } END { print v }' "$GS_DB"
}

@test "on the host it sets only the palette, never the font" {
  PATH="$HOST_BIN:$PATH" run ptyxis_script ptyxis false
  [ "$status" -eq 0 ]
  [ "$(setting "$PROFILE" palette)" = "'catppuccin-mocha'" ]
  [ "$(grep -c ' set ' "$GS_LOG")" -eq 1 ]
  ! grep -q -e font-name -e use-system-font "$GS_LOG"
}

@test "in a distrobox it sets it on the host through distrobox-host-exec" {
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [ "$(setting "$PROFILE" palette)" = "'catppuccin-mocha'" ]
  [ "$(grep -c '^host set ' "$GS_LOG")" -eq 1 ]
  ! grep -q '^local' "$GS_LOG"
}

@test "without the Ptyxis schema it says so and sets nothing" {
  rm "$GS_DB"
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found; palette not set"* ]] || false
  ! grep -q ' set ' "$GS_LOG"
}

@test "without a default profile it sets nothing and explains the palette" {
  printf 'org.gnome.Ptyxis\tdefault-profile-uuid\t%s\n' "''" > "$GS_DB"
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [[ "$output" == *"no default profile yet"* ]] || false
  ! grep -q ' set ' "$GS_LOG"
}

@test "with Ghostty chosen the script is empty" {
  run ptyxis_script ghostty true
  [ "$status" -eq 0 ]
  [ ! -s "$TMP/ptyxis.sh" ]
  [ ! -s "$GS_LOG" ]
}

drift_bazzite() { # drift's findings on Bazzite (installTarget distrobox), in the box
  config ptyxis true distrobox
  DRIFT_CHEZMOI_ARGS="--source $REAL_REPO --config $TMP/chezmoi.toml --persistent-state $TMP/state.boltdb --override-data {\"chezmoi\":{\"os\":\"linux\"}}" \
    "$REAL_REPO/bin/drift"
}

drift() { # <terminal> : drift's findings on Linux with these answers, in a distrobox
  config "$1" true
  DRIFT_CHEZMOI_ARGS="--source $REAL_REPO --config $TMP/chezmoi.toml --persistent-state $TMP/state.boltdb --override-data {\"chezmoi\":{\"os\":\"linux\"}}" \
    "$REAL_REPO/bin/drift"
}

@test "drift reports a changed Ptyxis palette as owned-key, and ignores the font" {
  ptyxis_script ptyxis true
  run drift ptyxis
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  printf 'org.gnome.Ptyxis\tfont-name\t%s\n' "'Monospace 12'" >> "$GS_DB"
  printf '%s\tpalette\t%s\n' "$PROFILE" "'gnome'" >> "$GS_DB"
  run drift ptyxis
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis.Profile palette'* ]] || false
  [[ "$output" != *font-name* ]] || false
  [[ "$output" != *use-system-font* ]] || false
}

@test "drift ignores Ptyxis when Ghostty is the terminal" {
  run drift ghostty
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  [ ! -s "$GS_LOG" ]
}

ID1=2af5000000000000000000000000000000000000000000000000000000000001
ID2=2af5000000000000000000000000000000000000000000000000000000000002

prof() { echo "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$1/"; }

labelled() { # <label> : the uuids of the listed profiles with this label, one per line
  local u
  for u in $(setting org.gnome.Ptyxis profile-uuids | sed 's/^@as //' | tr -d "[]',"); do
    [ "$(setting "$(prof "$u")" label)" = "'$1'" ] && echo "$u"
  done
  return 0
}

assert_layout() { # <box id> : the default profile is the Host, and one separate profile labelled ubuntu-dev is the box
  local def box
  def="$(setting org.gnome.Ptyxis default-profile-uuid | tr -d "'")"
  [ "$(setting "$(prof "$def")" label)" = "'Host'" ]
  [ "$(setting "$(prof "$def")" default-container)" = "'session'" ]
  [ "$(setting "$(prof "$def")" palette)" = "'catppuccin-mocha'" ]
  [ "$(labelled ubuntu-dev | wc -l)" -eq 1 ]
  [ "$(labelled Host | wc -l)" -eq 1 ]
  box="$(labelled ubuntu-dev)"
  [ "$box" != "$def" ]
  [ "${#box}" -ge 16 ]
  [ "$(setting "$(prof "$box")" default-container)" = "'$1'" ]
  [ "$(setting "$(prof "$box")" use-custom-command)" = true ]
  [ "$(setting "$(prof "$box")" custom-command)" = "'/usr/bin/zsh -l'" ]
  [ "$(setting "$(prof "$box")" palette)" = "'catppuccin-mocha'" ]
  ! grep -q -e font -e use-system-font "$GS_LOG" || false
}

@test "on Bazzite a fresh home keeps the default profile on the host and adds the box profile labelled ubuntu-dev" {
  export BOX_ID=$ID1
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  assert_layout "$ID1"
  [ "$(setting org.gnome.Ptyxis default-profile-uuid)" = "'$UUID'" ]
  [ "$(setting "$PROFILE" use-custom-command)" = "" ]
}

@test "on Bazzite the earlier layout (default profile is the box, plus a Host profile) migrates to default = Host" {
  export BOX_ID=$ID1
  HOST=feedfacefeedfacefeedfacefeedface
  {
    printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID', '$HOST']"
    printf '%s\tlabel\t%s\n' "$PROFILE" "'ubuntu-dev'"
    printf '%s\tdefault-container\t%s\n' "$PROFILE" "'$ID1'"
    printf '%s\tuse-custom-command\t%s\n' "$PROFILE" true
    printf '%s\tcustom-command\t%s\n' "$PROFILE" "'/usr/bin/zsh -l'"
    printf '%s\tlabel\t%s\n' "$(prof $HOST)" "'Host'"
    printf '%s\tdefault-container\t%s\n' "$(prof $HOST)" "'session'"
  } >> "$GS_DB"
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  assert_layout "$ID1"
  [ "$(setting org.gnome.Ptyxis default-profile-uuid)" = "'$HOST'" ]
  [ "$(labelled ubuntu-dev)" = "$UUID" ]
  ! grep -q 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG" || false
}

@test "on Bazzite the earlier layout without a Host profile gets a new Host profile as the default" {
  export BOX_ID=$ID1
  printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID']" >> "$GS_DB"
  printf '%s\tlabel\t%s\n' "$PROFILE" "'ubuntu-dev'" >> "$GS_DB"
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  assert_layout "$ID1"
  [ "$(labelled ubuntu-dev)" = "$UUID" ]
}

@test "on Bazzite a default already flipped to Host by hand stays the host, and the box stays the box" {
  export BOX_ID=$ID1
  HOST=feedfacefeedfacefeedfacefeedface
  {
    printf 'org.gnome.Ptyxis\tdefault-profile-uuid\t%s\n' "'$HOST'"
    printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID', '$HOST']"
    printf '%s\tlabel\t%s\n' "$PROFILE" "'ubuntu-dev'"
    printf '%s\tdefault-container\t%s\n' "$PROFILE" "'$ID1'"
    printf '%s\tlabel\t%s\n' "$(prof $HOST)" "'Host'"
    printf '%s\tdefault-container\t%s\n' "$(prof $HOST)" "'session'"
  } >> "$GS_DB"
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  assert_layout "$ID1"
  [ "$(setting org.gnome.Ptyxis default-profile-uuid)" = "'$HOST'" ]
  [ "$(labelled ubuntu-dev)" = "$UUID" ]
  ! grep -q -e "set $(prof $HOST) default-container '$ID1'" -e "set $(prof $HOST) use-custom-command true" "$GS_LOG" || false
  ! grep -q 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG" || false
}

@test "on Bazzite reruns never duplicate profiles, from a fresh home or the earlier layout" {
  export BOX_ID=$ID1
  ptyxis_script ptyxis true distrobox
  ptyxis_script ptyxis true distrobox
  ptyxis_script ptyxis true distrobox
  assert_layout "$ID1"
  [ "$(setting org.gnome.Ptyxis profile-uuids | tr ',' '\n' | wc -l)" -eq 2 ]
  [ "$(grep -c 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG")" -eq 1 ]
  [ "$(grep -c 'set org.gnome.Ptyxis default-profile-uuid' "$GS_LOG")" -eq 0 ]
  # A rebuilt box moves the same box profile to the new ID.
  export BOX_ID=$ID2
  ptyxis_script ptyxis true distrobox
  assert_layout "$ID2"
  [ "$(grep -c 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG")" -eq 1 ]
}

@test "on Bazzite a rerun after migrating the earlier layout changes nothing about the profiles" {
  export BOX_ID=$ID1
  printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID']" >> "$GS_DB"
  printf '%s\tlabel\t%s\n' "$PROFILE" "'ubuntu-dev'" >> "$GS_DB"
  ptyxis_script ptyxis true distrobox
  ptyxis_script ptyxis true distrobox
  assert_layout "$ID1"
  [ "$(setting org.gnome.Ptyxis profile-uuids | tr ',' '\n' | wc -l)" -eq 2 ]
  [ "$(grep -c 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG")" -eq 1 ]
  [ "$(grep -c 'set org.gnome.Ptyxis default-profile-uuid' "$GS_LOG")" -eq 1 ]
}

@test "on Bazzite without the box, the default profile stays on the host" {
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  [[ "$output" == *"box ubuntu-dev not found"* ]] || false
  [ -z "$(setting "$PROFILE" default-container)" ]
  [ "$(grep -c ' set ' "$GS_LOG")" -eq 1 ]
}

@test "a rebuilt box (new ID) changes the rendered script, so chezmoi runs it again" {
  export BOX_ID=$ID1
  ptyxis_script ptyxis true distrobox
  cp "$TMP/ptyxis.sh" "$TMP/first.sh"
  export BOX_ID=$ID2
  ptyxis_script ptyxis true distrobox
  ! cmp -s "$TMP/first.sh" "$TMP/ptyxis.sh" || false
  [ "$(setting "$(prof "$(labelled ubuntu-dev)")" default-container)" = "'$ID2'" ]
}

@test "a plain Linux host with Ptyxis never gets a box profile" {
  export BOX_ID=$ID1
  PATH="$HOST_BIN:$PATH" run ptyxis_script ptyxis false host
  [ "$status" -eq 0 ]
  [ "$(grep -c ' set ' "$GS_LOG")" -eq 1 ]
  ! grep -q -e default-container -e profile-uuids "$GS_LOG" || false
}

@test "drift reports a changed box profile key as owned-key, but not the per-rebuild container ID" {
  export BOX_ID=$ID1
  ptyxis_script ptyxis true distrobox
  run drift_bazzite
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  printf '%s\tcustom-command\t%s\n' "$(prof "$(labelled ubuntu-dev)")" "'/bin/bash'" >> "$GS_DB"
  run drift_bazzite
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis.Profile custom-command'* ]] || false
  [[ "$output" != *default-container* ]] || false
}

@test "drift reports a default profile that opens the box (the earlier layout)" {
  export BOX_ID=$ID1
  config ptyxis true distrobox
  printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID']" >> "$GS_DB"
  printf '%s\tlabel\t%s\n' "$PROFILE" "'ubuntu-dev'" >> "$GS_DB"
  printf '%s\tdefault-container\t%s\n' "$PROFILE" "'$ID1'" >> "$GS_DB"
  run drift_bazzite
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis default profile opens the box'* ]] || false
}

@test "drift reports a missing box profile on Bazzite" {
  export BOX_ID=$ID1
  ptyxis_script ptyxis true distrobox
  box="$(labelled ubuntu-dev)"
  printf '%s\tlabel\t%s\n' "$(prof "$box")" "'renamed'" >> "$GS_DB"
  run drift_bazzite
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis ubuntu-dev profile'* ]] || false
}

@test "on macOS the script is empty even with Ptyxis chosen" {
  config ptyxis false
  chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template \
    --override-data '{"chezmoi":{"os":"darwin"}}' < "$REAL_REPO/$SCRIPT" > "$TMP/ptyxis.sh"
  [ ! -s "$TMP/ptyxis.sh" ]
}
