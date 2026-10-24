#!/usr/bin/env bats

REAL_REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  R="$TMP/repo"
  mkdir -p "$HOME" "$R/bin" "$R/lib" "$R/home/dot_config/ghostty" "$R/home/.chezmoiscripts" "$TMP/stub"
  cp "$REAL_REPO/bin/drift" "$R/bin/drift"
  cp "$REAL_REPO/lib/denylist.txt" "$REAL_REPO/lib/claude-hooks.fragment.json" "$R/lib/"
  : > "$R/lib/drift-ignore.txt"
  cp "$REAL_REPO/.chezmoiroot" "$REAL_REPO/home/.chezmoiignore" "$R/" 2>/dev/null || true
  mv "$R/.chezmoiignore" "$R/home/.chezmoiignore"
  cp "$REAL_REPO/home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh" "$R/home/.chezmoiscripts/"
  echo 'theme = x' > "$R/home/dot_config/ghostty/config.ghostty"
  printf 'brew "bat"\ncask "ghostty"\n' > "$R/Brewfile"

  # Stub brew: everything in the Brewfile is installed, nothing extra.
  cat > "$TMP/stub/brew" <<'STUB'
#!/bin/sh
case "$*" in
  "leaves --installed-on-request") printf '%s\n' bat $STUB_EXTRA_FORMULA ;;
  "list --cask") echo ghostty ;;
  "bundle list --all --file="*) printf 'bat\nghostty\n' ;;
  "bundle check --verbose --no-upgrade --file="*)
    [ -n "$STUB_MISSING" ] && { echo "→ Formula $STUB_MISSING needs to be installed."; exit 1; }
    echo "The Brewfile's dependencies are satisfied." ;;
esac
STUB
  chmod +x "$TMP/stub/brew"
  export PATH="$TMP/stub:$PATH"
  unset STUB_EXTRA_FORMULA STUB_MISSING

  chezmoi --source "$R" --config "$TMP/chezmoi.toml" --persistent-state "$TMP/state.boltdb" apply --exclude scripts
  sh "$R/home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh"
  mkdir -p "$HOME/.claude"
  jq '{hooks: .hooks}' "$R/lib/claude-hooks.fragment.json" > "$HOME/.claude/settings.json"
  export DRIFT_CHEZMOI_ARGS="--source $R --config $TMP/chezmoi.toml --persistent-state $TMP/state.boltdb"
}

teardown() { rm -rf "$TMP"; }

@test "clean state prints nothing" {
  run "$R/bin/drift"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "in-place edit reported as edited" {
  echo 'font-size = 20' >> "$HOME/.config/ghostty/config.ghostty"
  run "$R/bin/drift"
  [[ "$output" == *$'edited\t.config/ghostty/config.ghostty'* ]] || false
}

@test "hand-edited owned hook reported as owned-key" {
  jq '.hooks.Stop[0].hooks[0].command = "echo hi"' "$HOME/.claude/settings.json" > "$TMP/s" && mv "$TMP/s" "$HOME/.claude/settings.json"
  run "$R/bin/drift"
  [[ "$output" == *$'owned-key\t~/.claude/settings.json hooks.Stop'* ]] || false
}

@test "changed git key reported as owned-key" {
  git config --global delta.side-by-side true
  run "$R/bin/drift"
  [[ "$output" == *$'owned-key\t~/.gitconfig delta.side-by-side'* ]] || false
}

@test "new ghostty file reported as untracked-config" {
  mkdir -p "$HOME/.config/ghostty/shaders"
  echo shader > "$HOME/.config/ghostty/shaders/crt.glsl"
  run "$R/bin/drift"
  [[ "$output" == *$'untracked-config\t.config/ghostty/shaders/crt.glsl'* ]] || false
}

@test "drift never proposes a denylisted path" {
  mkdir -p "$HOME/.config/herdr"
  : > "$HOME/.config/herdr/herdr.sock"
  : > "$HOME/.config/herdr/herdr-server.log"
  echo 'export X=1' > "$HOME/.zshrc"
  run "$R/bin/drift"
  [[ "$output" != *herdr.sock* ]] || false
  [[ "$output" != *.log* ]] || false
  [[ "$output" != *zshrc* ]] || false
}

@test "package installed by hand reported as pkg-extra" {
  export STUB_EXTRA_FORMULA=htop
  run "$R/bin/drift"
  [[ "$output" == *$'pkg-extra\thtop'* ]] || false
}

@test "ignored package not reported" {
  export STUB_EXTRA_FORMULA=htop
  echo htop > "$R/lib/drift-ignore.txt"
  run "$R/bin/drift"
  [ -z "$output" ]
}

@test "missing package reported as pkg-missing" {
  export STUB_MISSING=glow
  run "$R/bin/drift"
  [[ "$output" == *$'pkg-missing\tglow'* ]] || false
}

@test "summary is one line or empty" {
  run "$R/bin/drift" --summary
  [ -z "$output" ]
  export STUB_EXTRA_FORMULA=htop
  echo 'font-size = 20' >> "$HOME/.config/ghostty/config.ghostty"
  run "$R/bin/drift" --summary
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == "dotfiles: 2 changes not codified - run /codify" ]] || false
}

@test "hook mode emits a user-visible systemMessage only when drifted" {
  run "$R/bin/drift" --hook
  [ -z "$output" ]
  echo 'font-size = 20' >> "$HOME/.config/ghostty/config.ghostty"
  run "$R/bin/drift" --hook
  [ "$(jq -r '.systemMessage' <<<"$output")" = "dotfiles: 1 changes not codified - run /codify" ]
}
