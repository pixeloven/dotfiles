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

@test "on Bazzite the default profile opens the box's zsh by box ID, and a Host profile is added once" {
  export BOX_ID=$ID1
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  [ "$(setting "$PROFILE" default-container)" = "'$ID1'" ]
  [ "$(setting "$PROFILE" label)" = "'ubuntu-dev'" ]
  [ "$(setting "$PROFILE" use-custom-command)" = true ]
  [ "$(setting "$PROFILE" custom-command)" = "'/usr/bin/zsh -l'" ]
  [ "$(setting "$PROFILE" palette)" = "'catppuccin-mocha'" ]
  uuids="$(setting org.gnome.Ptyxis profile-uuids)"
  host="$(sed "s/.*'$UUID', '\([0-9a-f]*\)'.*/\1/" <<<"$uuids")"
  [ "${#host}" -eq 32 ]
  [ "$(setting "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$host/" label)" = "'Host'" ]
  [ "$(setting "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$host/" default-container)" = "'session'" ]
  ! grep -q -e font -e palette.*Host "$GS_LOG" || false
  # A rerun reuses the Host profile.
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  [ "$(grep -c 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG")" -eq 1 ]
}

@test "on Bazzite a Host profile made by hand is reused, not duplicated" {
  export BOX_ID=$ID1
  printf 'org.gnome.Ptyxis\tprofile-uuids\t%s\n' "['$UUID', 'feedfacefeedfacefeedfacefeedface']" >> "$GS_DB"
  printf 'org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/feedfacefeedfacefeedfacefeedface/\tlabel\t%s\n' "'Host'" >> "$GS_DB"
  run ptyxis_script ptyxis true distrobox
  [ "$status" -eq 0 ]
  ! grep -q 'set org.gnome.Ptyxis profile-uuids' "$GS_LOG" || false
  [ "$(setting "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/feedfacefeedfacefeedfacefeedface/" default-container)" = "'session'" ]
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
  [ "$(setting "$PROFILE" default-container)" = "'$ID2'" ]
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
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "ptyxis"\ncontainer = true\ninstallTarget = "distrobox"\n' "$REAL_REPO" > "$TMP/chezmoi.toml"
  drift_bazzite() { DRIFT_CHEZMOI_ARGS="--source $REAL_REPO --config $TMP/chezmoi.toml --persistent-state $TMP/state.boltdb --override-data {\"chezmoi\":{\"os\":\"linux\"}}" "$REAL_REPO/bin/drift"; }
  run drift_bazzite
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  printf '%s\tcustom-command\t%s\n' "$PROFILE" "'/bin/bash'" >> "$GS_DB"
  run drift_bazzite
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis.Profile custom-command'* ]] || false
  [[ "$output" != *default-container* ]] || false
}
