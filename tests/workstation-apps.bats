#!/usr/bin/env bats
REPO="$BATS_TEST_DIRNAME/.."
MANAGER="$REPO/lib/workstation-apps.sh"
CLI="$REPO/home/dot_local/bin/executable_workstation-apps"
setup() {
  export HOME="$(mktemp -d)" DOTFILES_APPS_REPO="$REPO"
  export DOTFILES_APPS_OS=linux DOTFILES_APPS_ARCH=x86_64
  export DOTFILES_APPS_CONTAINER_MARKER="$HOME/not-a-container"
  unset XDG_CONFIG_HOME DOTFILES_APPS_INSTALL_TARGET
  mkdir -p "$HOME/bin" "$HOME/.config/chezmoi"
  CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
  printf '[data]\ninstallTarget = "host"\n# keep this\nagentPlugins = false\n' > "$CONFIG"
  touch "$HOME/installed"
  cat > "$HOME/bin/brew" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/calls"
case "$1" in
  list) grep -qxF -- "$2 $3" "$HOME/installed" ;;
  install) [ "${FAIL_INSTALL:-}" != yes ] || exit 1; echo "$2 $3" >> "$HOME/installed" ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$HOME/bin/brew"
  export PATH="$HOME/bin:$PATH"
}
teardown() { rm -rf "$HOME"; }

@test "catalog exposes all eight separate app choices" {
  run "$MANAGER" list
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 8 ]
  [[ "$output" == *herdr-desktop* ]]
  [[ "$output" == *claude-code* ]]
}

@test "plan is read-only and distinguishes Linux manual apps from casks" {
  run "$MANAGER" plan codex claude-code herdr-cli herdr-desktop blender comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'cask codex'* ]]
  [[ "$output" == *'formula herdr'* ]]
  [[ "$output" == *'manual items remain'* ]]
  [ ! -e "$HOME/calls" ]
}

@test "install uses explicit brew type and is idempotent" {
  run "$MANAGER" install herdr-cli codex claude-code
  [ "$status" -eq 0 ]
  grep -qx 'install --formula herdr' "$HOME/calls"
  grep -qx 'install --cask codex' "$HOME/calls"
  grep -qx 'install --cask claude-code' "$HOME/calls"
  run "$MANAGER" install herdr-cli codex claude-code
  [ "$status" -eq 0 ]
  [ "$(grep -c '^install ' "$HOME/calls")" -eq 3 ]
}

@test "manual entries return incomplete without vendor installs" {
  run "$MANAGER" install blender comfyui claude-desktop chatgpt-desktop herdr-desktop
  [ "$status" -eq 3 ]
  [[ "$output" == *'manual items remain'* ]]
  [ ! -e "$HOME/calls" ]
}

@test "Apple silicon desktop choices resolve to Homebrew casks" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" install blender comfyui claude-desktop chatgpt-desktop herdr-desktop
  [ "$status" -eq 0 ]
  for app in blender comfy claude chatgpt herdr-app; do
    grep -qx "install --cask $app" "$HOME/calls"
  done
}

@test "Intel Mac does not claim Apple silicon-only apps install" {
  export DOTFILES_APPS_OS=darwin
  run "$MANAGER" install comfyui herdr-desktop
  [ "$status" -eq 3 ]
  [ ! -e "$HOME/calls" ]
}

@test "unknown selection fails before any app installs" {
  run "$MANAGER" install codex nope
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/calls" ]
}

@test "brew failure stops and is not reported as success" {
  export FAIL_INSTALL=yes
  run "$MANAGER" install codex herdr-cli
  [ "$status" -eq 1 ]
  ! grep -q herdr "$HOME/calls"
}

@test "Distrobox installs refuse host execution but permit planning" {
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" plan codex
  [ "$status" -eq 0 ]
  run "$MANAGER" install codex
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/calls" ]
  touch "$DOTFILES_APPS_CONTAINER_MARKER"
  run "$MANAGER" install codex
  [ "$status" -eq 0 ]
}

@test "on and off only persist choices without touching unrelated settings" {
  run "$CLI" on codex blender
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex", "blender"\]' "$CONFIG"
  grep -qx '# keep this' "$CONFIG"
  grep -qx 'agentPlugins = false' "$CONFIG"
  [ ! -e "$HOME/calls" ]
  run "$CLI" off blender
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex"\]' "$CONFIG"
  [ ! -e "$HOME/calls" ]
  run "$CLI" install
  [ "$status" -eq 0 ]
  grep -qx 'install --cask codex' "$HOME/calls"
}

@test "empty selection is a no-op and malformed config is not evaluated" {
  run "$CLI" install
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/calls" ]
  printf 'workstationApps = bad\n' >> "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/calls" ]
}

@test "saved target guard also applies to the user command" {
  printf '[data]\ninstallTarget = "distrobox"\nworkstationApps = ["codex"]\n' > "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/calls" ]
}


@test "unknown saved selections are not silently dropped by on or off" {
  printf 'workstationApps = ["future-app", "codex"]\n' >> "$CONFIG"
  cp "$CONFIG" "$HOME/before"
  run "$CLI" on blender
  [ "$status" -eq 2 ]
  cmp "$HOME/before" "$CONFIG"
  run "$CLI" off codex
  [ "$status" -eq 2 ]
  cmp "$HOME/before" "$CONFIG"
}


@test "selection parser rejects missing commas and accepts TOML whitespace" {
  printf 'workstationApps = ["codex" "blender"]\n' >> "$CONFIG"
  run "$CLI" plan
  [ "$status" -eq 2 ]
  printf '[data]\nworkstationApps = [\t"codex"\t,\t"herdr-cli"\t]\n' > "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 0 ]
  grep -qx 'install --cask codex' "$HOME/calls"
  grep -qx 'install --formula herdr' "$HOME/calls"
}
