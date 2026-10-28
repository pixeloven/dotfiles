#!/usr/bin/env bats
# lib/impeccable.sh against stub claude / codex / pi (present or not) and a stub npx standing in for
# Impeccable's installer: it records its argv, working directory and bundle in $TMP/calls and writes each
# provider's SKILL.md at the version in the bundle it was handed, as the real one does.

REAL_REPO="$BATS_TEST_DIRNAME/.."
LIB="$REAL_REPO/lib/impeccable.sh"
SCRIPTS="$REAL_REPO/home/.chezmoiscripts"
PIN="$(grep -vE '^[[:space:]]*(#|$)' "$REAL_REPO/lib/impeccable.txt" | head -n 1)"
LIVE_HOME="$HOME" LIVE_PATH="$PATH" # before setup() swaps them

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME" "$TMP/stub" "$TMP/bin" "$TMP/releases/skill-v$PIN"
  # Only these tools and the system dirs, so the real CLIs on this machine are never reached.
  ln -s "$(command -v jq)" "$TMP/bin/jq"; ln -s "$(command -v chezmoi)" "$TMP/bin/chezmoi"
  export PATH="$TMP/stub:$TMP/bin:/usr/bin:/bin"
  export IMPECCABLE_RELEASE_URL="file://$TMP/releases" IMPECCABLE_REGISTRY_URL="file://$TMP/registry"
  echo "$PIN" > "$TMP/releases/skill-v$PIN/universal.zip" # the stub reads the version out of the bundle
  for t in claude codex pi; do printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/$t"; done

  cat > "$TMP/stub/npx" <<'STUB'
#!/usr/bin/env bash
echo "npx $* | cwd=$PWD bundle=$IMPECCABLE_BUNDLE_PATH" >> "$(dirname "$HOME")/calls"
v="$(cat "$IMPECCABLE_BUNDLE_PATH")" || exit 1
for a in "$@"; do
  case "$a" in --providers=*) IFS=, read -ra ps <<<"${a#--providers=}" ;; esac
done
for p in "${ps[@]}"; do
  case "$p" in
    claude) d="$HOME/.claude/skills/impeccable"; fm="version: $v" ;;
    codex) d="$HOME/.agents/skills/impeccable"; fm=$'metadata:\n  version: '"$v" ;;
    pi) d="$HOME/.pi/agent/skills/impeccable"; fm="version: $v" ;;
  esac
  rm -rf "$d"; mkdir -p "$d"; printf -- '---\nname: impeccable\n%s\n---\nbody\n' "$fm" > "$d/SKILL.md"
done
STUB
  chmod +x "$TMP/stub/"*
}

teardown() { rm -rf "$TMP"; }

calls() { cat "$TMP/calls" 2>/dev/null; }

has() { # <tool> <version> [extra file] : a copy installed some other way, like the hand install it adopts
  local d
  case "$1" in claude) d="$HOME/.claude/skills/impeccable" ;; codex) d="$HOME/.agents/skills/impeccable" ;; pi) d="$HOME/.pi/agent/skills/impeccable" ;; esac
  mkdir -p "$d"; printf -- '---\nname: impeccable\nversion: %s\n---\n' "$2" > "$d/SKILL.md"
  [ -z "${3:-}" ] || echo mine > "$d/$3"
}

@test "the pin is one semver version" {
  [[ "$PIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
}

@test "ensure installs the pin for every tool through Impeccable's installer, from HOME, with no hooks" {
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ "$(calls | wc -l | tr -d ' ')" -eq 1 ]
  calls | grep -q "^npx --yes impeccable@$PIN install -y --user --no-hooks --providers=claude,codex,pi | cwd=$HOME bundle=/"
  bundle="$(calls | head -n 1 | sed 's/.* bundle=//')"
  [ "$(basename "$bundle")" = universal.zip ] && [ ! -e "$bundle" ] # the downloaded copy, cleaned up after
  for t in claude codex pi; do [ "$(cat "$HOME/.local/state/dotfiles/impeccable/$t")" = "$PIN" ]; done
  grep -qxF "version: $PIN" "$HOME/.claude/skills/impeccable/SKILL.md"
  [ ! -e "$HOME/.local/state/dotfiles/impeccable/backup" ]
  run "$LIB" check
  [ "$status" -eq 0 ]; [ -z "$output" ]
  rm "$TMP/calls"
  run "$LIB" ensure # at the pin everywhere: nothing to do, nothing fetched
  [ "$status" -eq 0 ]; [ -z "$(calls)" ]
}

@test "a tool that isn't installed is skipped and never reported" {
  rm "$TMP/stub/codex" "$TMP/stub/pi"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex not found; skipping"* ]] || false
  [[ "$output" == *"pi not found; skipping"* ]] || false
  [ "$(calls | wc -l | tr -d ' ')" -eq 1 ]
  calls | grep -q -- "--no-hooks --providers=claude |"
  [ ! -e "$HOME/.agents/skills/impeccable" ]
  run "$LIB" check
  [ -z "$output" ]
}

@test "a hand install that is older is backed up whole, then replaced at the pin" {
  has claude 4.0.4 notes.md
  has pi 4.0.4
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  b="$(ls -d "$HOME/.local/state/dotfiles/impeccable/backup/claude-4.0.4-"*)"
  [ "$(cat "$b/notes.md")" = mine ]
  grep -qxF "version: 4.0.4" "$b/SKILL.md"
  ls -d "$HOME/.local/state/dotfiles/impeccable/backup/pi-4.0.4-"*
  [[ "$output" == *"backed up $HOME/.claude/skills/impeccable (4.0.4) to $b"* ]] || false
  grep -qxF "version: $PIN" "$HOME/.claude/skills/impeccable/SKILL.md"
  grep -qxF "version: $PIN" "$HOME/.pi/agent/skills/impeccable/SKILL.md"
  calls | grep -q -- "--no-hooks --providers=claude,codex,pi |"
}

@test "a copy this script installed is replaced on a pin bump without a backup" {
  run "$LIB" ensure
  R="$TMP/repo"; mkdir -p "$R/lib" "$TMP/releases/skill-v99.0.0"
  cp "$LIB" "$R/lib/"; printf '# pin\n99.0.0\n' > "$R/lib/impeccable.txt"
  echo 99.0.0 > "$TMP/releases/skill-v99.0.0/universal.zip"
  run "$R/lib/impeccable.sh" check
  [[ "$output" == *$'skill-behind\tclaude impeccable@99.0.0\tchezmoi apply'* ]] || false
  [[ "$output" == *$'skill-behind\tcodex impeccable@99.0.0\tchezmoi apply'* ]] || false
  run "$R/lib/impeccable.sh" ensure
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/state/dotfiles/impeccable/backup" ]
  calls | grep -q "^npx --yes impeccable@99.0.0 install -y --user --no-hooks --providers=claude,codex,pi |"
  [ "$(cat "$HOME/.local/state/dotfiles/impeccable/pi")" = 99.0.0 ]
}

@test "a copy newer than the pin is left alone and reported as skill-ahead" {
  has claude 99.1.0
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  grep -qxF "version: 99.1.0" "$HOME/.claude/skills/impeccable/SKILL.md"
  calls | grep -q -- "--no-hooks --providers=codex,pi |"
  run "$LIB" check
  [ "$output" = $'skill-ahead\tclaude impeccable@'"$PIN"$'\tset lib/impeccable.txt to 99.1.0' ]
}

@test "check reports skill-missing and skill-behind, reading Codex's metadata version" {
  has claude 1.0.0
  mkdir -p "$HOME/.agents/skills/impeccable"
  printf -- '---\nname: impeccable\nmetadata:\n  version: "%s"\n---\nversion: 0.0.1\n' "$PIN" > "$HOME/.agents/skills/impeccable/SKILL.md"
  run "$LIB" check
  [ "$status" -eq 0 ]
  [ "$output" = $'skill-behind\tclaude impeccable@'"$PIN"$'\tchezmoi apply\nskill-missing\tpi impeccable@'"$PIN"$'\tchezmoi apply' ]
  [ -z "$(calls)" ]
}

@test "offline, ensure fails and leaves the installed copy as it was" {
  has claude 1.0.0
  rm -r "$TMP/releases"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch file://$TMP/releases/skill-v$PIN/universal.zip"* ]] || false
  grep -qxF "version: 1.0.0" "$HOME/.claude/skills/impeccable/SKILL.md"
  [ -z "$(calls)" ]
}

@test "without npx, ensure says so and fails" {
  rm "$TMP/stub/npx"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"npx not found"* ]] || false
}

@test "a failed install fails ensure and records nothing" {
  printf '#!/bin/sh\nexit 1\n' > "$TMP/stub/npx"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: npx impeccable@$PIN install"* ]] || false
  [ ! -e "$HOME/.local/state/dotfiles/impeccable/claude" ]
}

@test "latest names the version to bump to, and nothing when the pin is current" {
  mkdir -p "$TMP/registry/impeccable"
  echo '{"version":"99.0.0"}' > "$TMP/registry/impeccable/latest"
  run "$LIB" latest
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinned $PIN, latest 99.0.0"* ]] || false
  [[ "$output" == *"set $(cd "$REAL_REPO" && pwd)/lib/impeccable.txt to 99.0.0, then chezmoi apply"* ]] || false
  echo "{\"version\":\"$PIN\"}" > "$TMP/registry/impeccable/latest"
  run "$LIB" latest
  [ "$output" = "impeccable: pinned $PIN, latest $PIN" ]
}

@test "the apply script runs ensure, and agentPlugins = false renders nothing" {
  render() { printf '%s\n' "$1" > "$TMP/chezmoi.toml"; chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template < "$SCRIPTS/run_after_62-impeccable.sh.tmpl"; }
  run render ''
  [ "$status" -eq 0 ]
  [[ "$output" == *'/lib/impeccable.sh" ensure'* ]] || false
  run render $'[data]\nagentPlugins = false'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# bats test_tags=machine
@test "check runs on this machine's live install" {
  HOME="$LIVE_HOME" PATH="$LIVE_PATH" run "$LIB" check
  [ "$status" -eq 0 ]
  [ -z "$(grep -vE $'^skill-(missing|behind|ahead)\t(claude|codex|pi) impeccable@' <<<"$output")" ]
}
