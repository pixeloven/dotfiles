#!/usr/bin/env bats
# The operator persona key: a stub operator home stands in for the real one.

REAL_REPO="$BATS_TEST_DIRNAME/.."
TMPL="$REAL_REPO/home/.chezmoiscripts/run_onchange_after_50-operator-persona.sh.tmpl"

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  OP="$TMP/op"
  mkdir -p "$HOME" "$OP/bin"
  # Stub po-theme.sh: records each call; validate fails for the name "bad".
  cat > "$OP/bin/po-theme.sh" <<'STUB'
#!/bin/sh
echo "$*" >> "$(dirname "$0")/../calls"
[ "$1 $2" != "validate bad" ]
STUB
  chmod +x "$OP/bin/po-theme.sh"
}

teardown() { rm -rf "$TMP"; }

render() { # <chezmoi.toml body>
  printf '%s\n' "$1" > "$TMP/chezmoi.toml"
  chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template < "$TMPL"
}

@test "unset key renders an empty script" {
  run render ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "set key without operatorHome applies to the default home" {
  mkdir -p "$HOME/Development"; mv "$OP" "$HOME/Development/operator"
  render $'[data]\noperatorPersona = "operator"' > "$TMP/script"
  run sh "$TMP/script"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/Development/operator/config/po-theme")" = operator ]
}

@test "--home prints the resolved home only when it would be applied" {
  run "$REAL_REPO/lib/operator-persona.sh" --home "$OP"
  [ "$status" -eq 0 ]; [ "$output" = "$OP" ]
  mkdir -p "$HOME/Development"; mv "$OP" "$HOME/Development/operator"
  run "$REAL_REPO/lib/operator-persona.sh" --home ""
  [ "$status" -eq 0 ]; [ "$output" = "$HOME/Development/operator" ]
  touch "$HOME/Development/operator/.fm-secondmate-home"
  run "$REAL_REPO/lib/operator-persona.sh" --home "~/Development/operator"
  [ "$status" -eq 1 ]; [ -z "$output" ]
  run "$REAL_REPO/lib/operator-persona.sh" --home "$TMP/none"
  [ "$status" -eq 1 ]; [ -z "$output" ]
  [ ! -e "$HOME/Development/operator/calls" ]
}

@test "writes the selection then applies and verifies" {
  run "$REAL_REPO/lib/operator-persona.sh" operator "$OP"
  [ "$status" -eq 0 ]
  [ "$(cat "$OP/config/po-theme")" = operator ]
  [ "$(cat "$OP/calls")" = $'validate operator\napply\nverify' ]
}

@test "leaves a matching selection untouched" {
  mkdir -p "$OP/config"
  printf 'operator\n# kept\n' > "$OP/config/po-theme"
  run "$REAL_REPO/lib/operator-persona.sh" operator "$OP"
  [ "$status" -eq 0 ]
  [ "$(cat "$OP/config/po-theme")" = $'operator\n# kept' ]
}

@test "invalid name fails before writing" {
  run "$REAL_REPO/lib/operator-persona.sh" bad "$OP"
  [ "$status" -ne 0 ]
  [ ! -e "$OP/config/po-theme" ]
  [ "$(cat "$OP/calls")" = "validate bad" ]
}

@test "missing home, non-executable script and secondmate home are skipped" {
  run "$REAL_REPO/lib/operator-persona.sh" operator "$TMP/none"
  [ "$status" -eq 0 ]; [[ "$output" == *skipping* ]] || false
  touch "$OP/.fm-secondmate-home"
  run "$REAL_REPO/lib/operator-persona.sh" operator "$OP"
  [ "$status" -eq 0 ]; [[ "$output" == *secondmate* ]] || false
  rm "$OP/.fm-secondmate-home"; chmod -x "$OP/bin/po-theme.sh"
  run "$REAL_REPO/lib/operator-persona.sh" operator "$OP"
  [ "$status" -eq 0 ]; [[ "$output" == *"not executable"* ]] || false
  [ ! -e "$OP/calls" ] && [ ! -e "$OP/config/po-theme" ]
}

@test "home given with ~ expands against HOME" {
  mkdir -p "$HOME/Development"; mv "$OP" "$HOME/Development/operator"
  run "$REAL_REPO/lib/operator-persona.sh" operator
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/Development/operator/config/po-theme")" = operator ]
}
