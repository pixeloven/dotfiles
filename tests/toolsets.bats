#!/usr/bin/env bats
# toolsets: status, list, on and off for the optional ops tool sets. A stub brew and chezmoi log
# their calls; nothing is installed and chezmoi apply never runs.

REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="$REPO/home/dot_local/bin/executable_toolsets"

setup() {
  export HOME="$(mktemp -d)" TOOLSETS_REPO="$REPO"
  unset XDG_CONFIG_HOME
  CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
  mkdir -p "$HOME/.config/chezmoi" "$HOME/bin"
  printf 'sourceDir = "~/Development/dotfiles"\n\n[data]\nterminal = "ghostty"\n# kept\nagentPlugins = false\n' > "$CONFIG"
  # brew: installed formulae and taps come from files, so uninstall and untap change what it reports.
  printf 'helm\nsiderolabs/tap/talosctl\nansible\n' > "$HOME/formulae"
  printf 'siderolabs/tap\n' > "$HOME/taps"
  cat > "$HOME/bin/brew" <<'STUB'
#!/bin/sh
echo "brew $*" >> "$HOME/calls"
case "$1" in
  list) cat "$HOME/formulae" ;;
  tap) cat "$HOME/taps" ;;
  untap) grep -vxF "$2" "$HOME/taps" > "$HOME/t"; mv "$HOME/t" "$HOME/taps" ;;
  uninstall) shift; for f in "$@"; do grep -vxF "$f" "$HOME/formulae" > "$HOME/f"; mv "$HOME/f" "$HOME/formulae"; done ;;
esac
STUB
  printf '#!/bin/sh\necho "chezmoi $*" >> "$HOME/calls"\n' > "$HOME/bin/chezmoi"
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
}

teardown() { rm -rf "$HOME"; }

@test "list shows every set in lib/toolsets.txt with its formulae" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [ "$(awk '{ print $1 }' <<<"$output" | paste -sd ' ' -)" = "kubernetes talos terraform ansible containers" ]
  [[ "$output" == *"talos       siderolabs/tap/talosctl siderolabs/tap/omnictl"* ]] || false
}

@test "status is the default: what is on, and what is installed" {
  printf 'toolsets = ["talos"]\n' >> "$CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"talos       on   siderolabs/tap/talosctl siderolabs/tap/omnictl: partly installed (missing siderolabs/tap/omnictl)"* ]] || false
  [[ "$output" == *"terraform   off  hashicorp/tap/terraform: not installed"$'\n'* ]] || false
  [[ "$output" == *"ansible     off  ansible: installed (set is off; \`toolsets on ansible\`"* ]] || false
}

@test "before re-init, opsTools = true means every set, and false or no key means none" {
  printf 'opsTools = true\n' >> "$CONFIG"
  run "$SCRIPT" status
  [ "$(grep -c '^[a-z]* *on ' <<<"$output")" -eq 5 ]
  sed -i.x 's/opsTools = true/opsTools = false/' "$CONFIG"
  run "$SCRIPT" status
  [ "$(grep -c '^[a-z]* *off ' <<<"$output")" -eq 5 ]
}

@test "on adds the sets, changes only the toolsets line, then applies the scripts" {
  cp "$CONFIG" "$HOME/before"
  run "$SCRIPT" on terraform kubernetes
  [ "$status" -eq 0 ]
  [[ "$output" == *"toolsets: on: kubernetes terraform"* ]] || false
  [ "$(diff "$HOME/before" "$CONFIG" | grep '^[<>]')" = '> toolsets = ["kubernetes", "terraform"]' ]
  grep -qxF "chezmoi apply --include scripts" "$HOME/calls"
  run "$SCRIPT" on talos
  grep -qxF 'toolsets = ["kubernetes", "talos", "terraform"]' "$CONFIG"
  [ -e "$CONFIG.bak-dotfiles" ]
}

@test "off removes the sets and leaves their tools installed" {
  printf 'toolsets = ["kubernetes", "talos"]\n' >> "$CONFIG"
  run "$SCRIPT" off talos
  [ "$status" -eq 0 ]
  grep -qxF 'toolsets = ["kubernetes"]' "$CONFIG"
  [[ "$output" == *"stay installed"* ]] || false
  ! grep -q -e uninstall -e untap -e chezmoi "$HOME/calls" || false
  run "$SCRIPT" off kubernetes
  grep -qxF 'toolsets = []' "$CONFIG"
  [[ "$output" == *"toolsets: on: none"* ]] || false
}

@test "off on a machine still on opsTools = true keeps the other sets on" {
  printf 'opsTools = true\n' >> "$CONFIG"
  run "$SCRIPT" off containers
  [ "$status" -eq 0 ]
  grep -qxF 'toolsets = ["kubernetes", "talos", "terraform", "ansible"]' "$CONFIG"
}

@test "off --uninstall removes the installed formulae, then the tap nothing uses" {
  printf 'toolsets = ["talos", "ansible"]\n' >> "$CONFIG"
  run "$SCRIPT" off talos ansible --uninstall
  [ "$status" -eq 0 ]
  grep -qxF 'toolsets = []' "$CONFIG"
  grep -qxF "brew uninstall siderolabs/tap/talosctl" "$HOME/calls"
  grep -qxF "brew uninstall ansible" "$HOME/calls"
  grep -qxF "brew untap siderolabs/tap" "$HOME/calls"
  ! grep -q omnictl "$HOME/calls" || false
  [ "$(cat "$HOME/formulae")" = helm ]
  [[ "$output" == *"brew autoremove"* ]] || false
}

@test "unknown names and commands exit 2 and change nothing" {
  printf 'toolsets = ["talos"]\n' >> "$CONFIG"
  cp "$CONFIG" "$HOME/before"
  run "$SCRIPT" on kubernetes bogus
  [ "$status" -eq 2 ]
  run "$SCRIPT" off
  [ "$status" -eq 2 ]
  run "$SCRIPT" frob
  [ "$status" -eq 2 ]
  cmp "$HOME/before" "$CONFIG"
  [ ! -e "$HOME/calls" ]
}

@test "unknown names already in the config are kept" {
  printf 'toolsets = ["future", "talos"]\n' >> "$CONFIG"
  run "$SCRIPT" on kubernetes
  [ "$status" -eq 0 ]
  grep -qxF 'toolsets = ["kubernetes", "talos", "future"]' "$CONFIG"
}

@test "with no chezmoi config, on asks for chezmoi init first" {
  rm "$CONFIG"
  run "$SCRIPT" on kubernetes
  [ "$status" -eq 1 ]
  [[ "$output" == *"run chezmoi init first"* ]] || false
  [ ! -e "$CONFIG" ]
}
