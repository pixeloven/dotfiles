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
  printf '#!/bin/sh\n' > "$TMP/bin/brew"
  chmod +x "$HOST_BIN/gsettings" "$TMP/bin/"*
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

config() { # <terminal> <container> : a chezmoi config for Linux with these answers
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "%s"\ncontainer = %s\n' "$REAL_REPO" "$1" "$2" > "$TMP/chezmoi.toml"
}

ptyxis_script() { # <terminal> <container> : run the script as rendered for Linux with these answers
  config "$1" "$2"
  chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template \
    --override-data '{"chezmoi":{"os":"linux"}}' < "$REAL_REPO/$SCRIPT" > "$TMP/ptyxis.sh"
  sh "$TMP/ptyxis.sh"
}

setting() { # <schema> <key> : the stored value
  awk -F '\t' -v s="$1" -v k="$2" '$1 == s && $2 == k { v = $3 } END { print v }' "$GS_DB"
}

@test "on the host it sets exactly the three owned settings" {
  PATH="$HOST_BIN:$PATH" run ptyxis_script ptyxis false
  [ "$status" -eq 0 ]
  [ "$(setting org.gnome.Ptyxis use-system-font)" = false ]
  [ "$(setting org.gnome.Ptyxis font-name)" = "'JetBrainsMono Nerd Font 14'" ]
  [ "$(setting "$PROFILE" palette)" = "'catppuccin-mocha'" ]
  [ "$(grep -c ' set ' "$GS_LOG")" -eq 3 ]
}

@test "in a distrobox it sets them on the host through distrobox-host-exec" {
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [ "$(setting "$PROFILE" palette)" = "'catppuccin-mocha'" ]
  [ "$(grep -c '^host set ' "$GS_LOG")" -eq 3 ]
  ! grep -q '^local' "$GS_LOG"
}

@test "without the Ptyxis schema it says so and sets nothing" {
  rm "$GS_DB"
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found; font and palette not set"* ]] || false
  ! grep -q ' set ' "$GS_LOG"
}

@test "without a default profile it sets the font and explains the palette" {
  printf 'org.gnome.Ptyxis\tdefault-profile-uuid\t%s\n' "''" > "$GS_DB"
  run ptyxis_script ptyxis true
  [ "$status" -eq 0 ]
  [[ "$output" == *"no default profile yet"* ]] || false
  [ "$(setting org.gnome.Ptyxis font-name)" = "'JetBrainsMono Nerd Font 14'" ]
  [ "$(grep -c '^host set ' "$GS_LOG")" -eq 2 ]
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

@test "drift reports a changed Ptyxis font or palette as owned-key" {
  ptyxis_script ptyxis true
  run drift ptyxis
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  printf 'org.gnome.Ptyxis\tfont-name\t%s\n' "'Monospace 12'" >> "$GS_DB"
  printf '%s\tpalette\t%s\n' "$PROFILE" "'gnome'" >> "$GS_DB"
  run drift ptyxis
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis font-name'* ]] || false
  [[ "$output" == *$'owned-key\torg.gnome.Ptyxis.Profile palette'* ]] || false
  [[ "$output" != *use-system-font* ]] || false
}

@test "drift ignores Ptyxis when Ghostty is the terminal" {
  run drift ghostty
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  [ ! -s "$GS_LOG" ]
}
