#!/usr/bin/env bats
# bats file_tags=render
# Renders the source for each OS into throwaway HOMEs. CI runs this on macOS and Linux.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TMP="$(mktemp -d)"
  config ghostty
}

config() { # <terminal> : a fixed config rather than `chezmoi init`, because --override-data doesn't reach init
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "%s"\ncontainer = false\n' "$REPO" "$1" > "$TMP/chezmoi.toml"
}

teardown() { rm -rf "$TMP"; }

render() { # <os> : apply the source as <os> into $TMP/<os> (scripts excluded) and list what it wrote
  mkdir -p "$TMP/$1"
  HOME="$TMP/$1" chezmoi --source "$REPO" --config "$TMP/chezmoi.toml" --persistent-state "$TMP/$1.boltdb" \
    --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" apply --exclude scripts
  (cd "$TMP/$1" && find . \( -type f -o -type l \) | sed 's#^\./##' | LC_ALL=C sort)
}

init_config() { # <os> [chezmoi flags] : render .chezmoi.toml.tmpl as `chezmoi init` would on <os>
  local os="$1"; shift
  chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template --init --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" "$@" < "$REPO/home/.chezmoi.toml.tmpl"
}

@test "macOS gets today's files, plus macos.ghostty" {
  run render darwin
  [ "$status" -eq 0 ]
  expected=".agents/skills/codify/SKILL.md
.agents/skills/lastreply/SKILL.md
.claude/hooks/speak-alert.sh
.claude/skills/codify/SKILL.md
.claude/skills/lastreply/SKILL.md
.claude/themes/catppuccin-mocha.json
.config/bat/config
.config/ghostty/config.ghostty
.config/ghostty/macos.ghostty
.config/glow/catppuccin-mocha.json
.config/herdr/config.toml
.config/starship.toml
.config/zsh/catppuccin-zsh-syntax-highlighting.LICENSE
.config/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh
.config/zsh/dotfiles.zsh
.config/zsh/op-env.zsh
.local/bin/lastreply
.local/bin/speak-kokoro
.local/bin/toolsets
.local/bin/voice
.local/bin/voice-cloud
.local/bin/workstation-apps
Library/Preferences/glow/glow.yml"
  [ "$(grep -v 'config file template has changed' <<<"$output")" = "$expected" ]
}

@test "Linux with Ghostty gets glow in ~/.config and linux.ghostty, and no ~/Library or Ptyxis palette" {
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *.config/glow/glow.yml* ]] || false
  [[ "$output" == *.config/ghostty/linux.ghostty* ]] || false
  [[ "$output" != *macos.ghostty* ]] || false
  [[ "$output" != *org.gnome.Ptyxis* ]] || false
  [[ "$output" == *.local/bin/dictate* ]] || false
  [ ! -e "$TMP/linux/Library" ]
}

@test "Linux with Ptyxis also gets the Catppuccin Ptyxis palette" {
  palette=.local/share/org.gnome.Ptyxis/palettes/catppuccin-mocha.palette
  config ptyxis
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *$palette* ]] || false
}

@test "only Bazzite (Linux with installTarget distrobox) gets herdr-core's shell into the box" {
  run render darwin
  [[ "$output" != *.config/herdr-core* ]] || false
  run render linux
  [[ "$output" != *.config/herdr-core* ]] || false
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "ptyxis"\ninstallTarget = "distrobox"\ncontainer = true\n' "$REPO" > "$TMP/chezmoi.toml"
  run render linux
  [ "$status" -eq 0 ]
  [[ "$output" == *.config/herdr-core/config.toml* ]] || false
  grep -qx 'shell = \["distrobox", "enter", "ubuntu-dev"\]' "$TMP/linux/.config/herdr-core/config.toml"
}

@test "the Ptyxis settings script renders nothing without Ptyxis" {
  script() { # <os> <terminal> <container>
    chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template \
      --override-data "{\"chezmoi\":{\"os\":\"$1\"},\"terminal\":\"$2\",\"container\":$3}" \
      < "$REPO/home/.chezmoiscripts/run_onchange_after_50-ptyxis.sh.tmpl"
  }
  [ -z "$(script linux ghostty false)" ]
  [ -z "$(script darwin ghostty false)" ]
}

@test "glow config is the same on both OSes and points at the HOME's Catppuccin style" {
  render darwin > /dev/null
  render linux > /dev/null
  mac="$TMP/darwin/Library/Preferences/glow/glow.yml" linux="$TMP/linux/.config/glow/glow.yml"
  grep -qxF "style: \"$TMP/darwin/.config/glow/catppuccin-mocha.json\"" "$mac"
  [ "$(sed "s#$TMP/darwin#H#" "$mac")" = "$(sed "s#$TMP/linux#H#" "$linux")" ]
}

@test "glow config turns the pager off, so piped glow (ublue-motd) never opens one" {
  render linux > /dev/null
  cfg="$TMP/linux/.config/glow/glow.yml"
  grep -qxF "pager: false" "$cfg"
  command -v glow > /dev/null || skip "glow not installed"
  printf '#!/bin/sh\ntouch "%s/paged"; cat\n' "$TMP" > "$TMP/pager"; chmod +x "$TMP/pager"
  # As ublue-motd runs it; HOME, not --config, because glow still merges the real config
  printf '# Hi\n' | HOME="$TMP/linux" XDG_CONFIG_HOME="$TMP/linux/.config" PAGER="$TMP/pager" \
    TERM=dumb timeout 20 glow -s dark -w 80 - > /dev/null
  [ ! -e "$TMP/paged" ]
}

TOOLSETS_PROMPT="Ops tool sets to install (lib/toolsets.txt; none by default)"

@test "macOS init asks only about the tool sets, and picks Ghostty and the host" {
  run init_config darwin --promptChoice "Terminal app on this Linux machine=other" \
    --promptChoice "Install tools on this host, or only inside a distrobox=distrobox"
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "ghostty"'* ]] || false
  [[ "$output" == *'installTarget = "host"'* ]] || false
  [[ "$output" == *$'\ntoolsets = []\n'* ]] || false
  [[ "$output" != *"opsTools ="* ]] || false
}

@test "init records the tool sets answer on both OSes, defaulting to none" {
  local os
  for os in darwin linux; do
    run init_config "$os" --promptMultichoice "$TOOLSETS_PROMPT=kubernetes/terraform"
    [ "$status" -eq 0 ]
    [[ "$output" == *'toolsets = ["kubernetes", "terraform"]'* ]] || { echo "$os: $output"; false; }
  done
}

@test "the init choices are the sets in lib/toolsets.txt" {
  local want
  want="$(sed 's/#.*//' "$REPO/lib/toolsets.txt" | awk 'NF { print $1 }' | paste -sd / -)"
  run init_config darwin --promptMultichoice "$TOOLSETS_PROMPT=$want"
  [ "$status" -eq 0 ]
  [[ "$output" == *'toolsets = ["kubernetes", "talos", "terraform", "ansible", "containers"]'* ]] || false
}

re_init() { # <os> <old [data] lines> [chezmoi flags] : render the init template over an existing config, as a re-init does
  local os="$1"
  printf '[data]\n%s\n' "$2" > "$TMP/old.toml"
  shift 2
  chezmoi --source "$REPO" --config "$TMP/old.toml" execute-template --init --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" "$@" < "$REPO/home/.chezmoi.toml.tmpl"
}

@test "re-init turns the old opsTools answer into tool sets without asking: yes is all, no is none" {
  local os
  for os in darwin linux; do
    # A tool sets answer here would show up as kubernetes alone; the legacy seed must win.
    run re_init "$os" $'terminal = "ptyxis"\ninstallTarget = "host"\nopsTools = true' \
      --promptMultichoice "$TOOLSETS_PROMPT=kubernetes"
    [ "$status" -eq 0 ]
    [[ "$output" == *'toolsets = ["kubernetes", "talos", "terraform", "ansible", "containers"]'* ]] || { echo "$os: $output"; false; }
    [[ "$output" != *"opsTools ="* ]] || false
    run re_init "$os" $'terminal = "ptyxis"\ninstallTarget = "host"\nopsTools = false' \
      --promptMultichoice "$TOOLSETS_PROMPT=kubernetes"
    [[ "$output" == *$'\ntoolsets = []\n'* ]] || { echo "$os: $output"; false; }
  done
}

@test "re-init keeps the tool sets already chosen" {
  run re_init darwin 'toolsets = ["talos"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'toolsets = ["talos"]'* ]] || false
}

@test "re-init keeps the keys set by hand" {
  run re_init darwin $'agentPlugins = false\noperatorPersona = "operator"\noperatorHome = "~/Development/operator"'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nagentPlugins = false'* ]] || false
  [[ "$output" == *$'\noperatorPersona = "operator"'* ]] || false
  [[ "$output" == *$'\noperatorHome = "~/Development/operator"'* ]] || false
  run init_config darwin
  [[ "$output" != *agentPlugins* ]] || false
  [[ "$output" != *operator* ]] || false
}

@test "Linux init records where tools install" {
  run init_config linux --promptChoice "Install tools on this host, or only inside a distrobox=distrobox"
  [ "$status" -eq 0 ]
  [[ "$output" == *'installTarget = "distrobox"'* ]] || false
  { [ -e /run/ostree-booted ] || [ -e /run/host/run/ostree-booted ]; } && skip "an image-based host suggests distrobox"
  run init_config linux
  [ "$status" -eq 0 ]
  [[ "$output" == *'installTarget = "host"'* ]] || false
}

@test "the installTarget answer reaches zsh on Linux only" {
  run render linux
  [[ "$output" == *.config/zsh/dotfiles-target.zsh* ]] || false
  grep -qx '_dotfiles_install_target="host"' "$TMP/linux/.config/zsh/dotfiles-target.zsh"
  run render darwin
  [[ "$output" != *dotfiles-target* ]] || false
}

@test "Linux init records the terminal answer, defaulting to Ptyxis" {
  run init_config linux --promptChoice "Terminal app on this Linux machine=other"
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "other"'* ]] || false
  VTE_VERSION= run init_config linux
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal = "ptyxis"'* ]] || false
  [[ "$output" == *$'\ncontainer = '* ]] || false
}

@test "workstation apps default to none and preserve per-machine choices" {
  run init_config darwin
  [ "$status" -eq 0 ]
  [[ "$output" == *'workstationApps = []'* ]] || false
  run re_init linux 'workstationApps = ["herdr-cli", "codex", "blender"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'workstationApps = ["herdr-cli", "codex", "blender"]'* ]] || false
}

@test "workstation init choices come from the app catalog" {
  local ids want
  ids="$(awk -F '|' '!/^#/ && NF && !seen[$1]++ {print $1}' "$REPO/lib/workstation-apps.tsv")"
  want="$(sed 's/.*/"&"/' <<<"$ids" | paste -sd , - | sed 's/,/, /g')"
  run init_config linux --promptMultichoice "Workstation apps to install (lib/workstation-apps.tsv; none by default)=$(paste -sd / - <<<"$ids")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workstationApps = [$want]"* ]] || false
}

STORAGE_PROMPT="NFS server for the homelab shares under /var/mnt/storage-01 (blank: none)"
STORAGE_MODELS_PROMPT="Mount the models share read-write or read-only"

@test "the homelab NFS shares are off by default: Linux init asks for a server, blank by default, and macOS never does" {
  run init_config linux
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nstorageServer = ""\n'* ]] || false
  [[ "$output" != *storageModels* ]] || false
  run init_config darwin --promptString "$STORAGE_PROMPT=192.0.2.10"
  [ "$status" -eq 0 ]
  [[ "$output" != *storage* ]] || false
}

@test "with a server, the models share defaults to read-write in a distrobox setup and read-only on a host" {
  run init_config linux --promptString "$STORAGE_PROMPT= 192.0.2.10 " \
    --promptChoice "Install tools on this host, or only inside a distrobox=distrobox"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nstorageServer = "192.0.2.10"\nstorageModels = "rw"\n'* ]] || false
  run init_config linux --promptString "$STORAGE_PROMPT=192.0.2.10" \
    --promptChoice "Install tools on this host, or only inside a distrobox=host"
  [[ "$output" == *$'\nstorageModels = "ro"\n'* ]] || false
  run re_init linux $'installTarget = "host"\nstorageServer = "192.0.2.10"\nstorageModels = "rw"'
  [[ "$output" == *$'\nstorageServer = "192.0.2.10"\nstorageModels = "rw"\n'* ]] || false
}

@test "only Linux with a storageServer gets storage-shares and its shares.conf" {
  printf 'sourceDir = "%s"\n\n[data]\nterminal = "other"\ncontainer = false\nstorageServer = "192.0.2.10"\nstorageModels = "ro"\n' "$REPO" > "$TMP/chezmoi.toml"
  run render darwin
  [[ "$output" != *storage-shares* ]] || false
  run render linux
  [[ "$output" == *.config/storage-shares/shares.conf* ]] || false
  [[ "$output" == *.local/bin/storage-shares* ]] || false
  user="$(id -un)"
  grep -qx 'server 192.0.2.10' "$TMP/linux/.config/storage-shares/shares.conf"
  grep -qx "share $user /bulk/shares/$user rw" "$TMP/linux/.config/storage-shares/shares.conf"
  grep -qx 'share models /bulk/models ro' "$TMP/linux/.config/storage-shares/shares.conf"
  config other
  printf 'storageServer = ""\n' >> "$TMP/chezmoi.toml"
  rm -rf "$TMP/linux" "$TMP/linux.boltdb"
  run render linux
  [[ "$output" != *storage-shares* ]] || false
}

@test "the storage-shares apply step runs only with a storageServer, touches Comfy only when it is selected, and never fails apply" {
  step() { chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template --override-data "$1" < "$REPO/home/.chezmoiscripts/run_after_46-storage-shares.sh.tmpl"; }
  run step '{"chezmoi":{"os":"linux"},"storageServer":""}'
  [ -z "$output" ]
  run step '{"chezmoi":{"os":"darwin"},"storageServer":"192.0.2.10"}'
  [ -z "$output" ]
  mkdir -p "$TMP/run/.local/bin"
  printf '#!/bin/sh\necho "$*" >> "$HOME/calls"\nexit "${STUB_EXIT:-0}"\n' > "$TMP/run/.local/bin/storage-shares"
  chmod +x "$TMP/run/.local/bin/storage-shares"
  apply_step() { # <data> <stub exit> : run the rendered step as apply would, with a stub storage-shares
    step "$1" > "$TMP/step.sh"
    : > "$TMP/run/calls"
    HOME="$TMP/run" STUB_EXIT="$2" sh "$TMP/step.sh"
  }
  for rc in 0 1; do
    run apply_step '{"chezmoi":{"os":"linux"},"storageServer":"192.0.2.10","workstationApps":["blender"]}' "$rc"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/run/calls")" = 'status --quiet' ]
    run apply_step '{"chezmoi":{"os":"linux"},"storageServer":"192.0.2.10","workstationApps":["comfyui"]}' "$rc"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/run/calls")" = $'status --quiet\ncomfy --quiet' ]
  done
}
