#!/usr/bin/env bats
# workstation-apps: the catalog, preview, install, the chezmoi apply step, drift lines and vendor
# copies. Stub brew, flatpak, distrobox-host-exec, npm and chezmoi log their calls into a throwaway
# HOME; PATH leaves out the real ~/.local/bin and Homebrew, so nothing real is found or installed.
REPO="$BATS_TEST_DIRNAME/.."
MANAGER="$REPO/lib/workstation-apps.sh"
CLI="$REPO/home/dot_local/bin/executable_workstation-apps"
ORIG_PATH="$PATH"

setup() {
  export HOME="$(mktemp -d)" DOTFILES_APPS_REPO="$REPO"
  export DOTFILES_APPS_OS=linux DOTFILES_APPS_ARCH=x86_64
  export DOTFILES_APPS_CONTAINER_MARKER="$HOME/not-a-container"
  export DOTFILES_APPS_APPLICATIONS="$HOME/Applications"
  unset XDG_CONFIG_HOME DOTFILES_APPS_INSTALL_TARGET DOTFILES_APPS_TABLE FAIL_INSTALL
  mkdir -p "$HOME/bin" "$HOME/brew/bin" "$HOME/.config/chezmoi"
  CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
  printf '[data]\ninstallTarget = "host"\n# keep this\nagentPlugins = false\n' > "$CONFIG"
  : > "$HOME/installed"
  : > "$HOME/flatpaks"
  # brew: installed packages are "<formula|cask> <name>" lines; a cask's binary lands in its prefix.
  cat > "$HOME/bin/brew" <<'STUB'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$HOME/calls"
case "$1" in
  --prefix) echo "$HOME/brew" ;;
  list) sed -n "s/^${2#--} //p" "$HOME/installed" ;;
  install)
    [ "${FAIL_INSTALL:-}" != "$3" ] || exit 1
    echo "${2#--} $3" >> "$HOME/installed"
    case "$3" in claude-code) : > "$HOME/brew/bin/claude" ;; codex) : > "$HOME/brew/bin/codex" ;; esac ;;
  *) exit 2 ;;
esac
STUB
  cat > "$HOME/bin/flatpak" <<'STUB'
#!/bin/sh
printf 'flatpak %s\n' "$*" >> "$HOME/calls"
case "$1" in
  info) grep -qxF -- "$2" "$HOME/flatpaks" ;;
  remote-add) ;;
  install) for a in "$@"; do last="$a"; done; echo "$last" >> "$HOME/flatpaks" ;;
  *) exit 2 ;;
esac
STUB
  printf '#!/bin/sh\nprintf "host-exec %%s\\n" "$*" >> "$HOME/calls"\nexec "$@"\n' > "$HOME/bin/distrobox-host-exec"
  printf '#!/bin/sh\nprintf "npm %%s\\n" "$*" >> "$HOME/calls"\n' > "$HOME/bin/npm"
  printf '#!/bin/sh\nprintf "chezmoi %%s\\n" "$*" >> "$HOME/calls"\n' > "$HOME/bin/chezmoi"
  chmod +x "$HOME/bin/"*
  mkdir -p "$HOME/shell"; ln -s "$BASH" "$HOME/shell/bash"
  export PATH="$HOME/bin:$HOME/brew/bin:$HOME/shell:/usr/bin:/bin"
}
teardown() { rm -rf "$HOME"; }

installs() { { cat "$HOME/calls" 2>/dev/null || true; } | grep -c -e '^brew install' -e 'flatpak install' || true; }
fixture() { # a catalog with one Flatpak app and one community-labelled Flatpak app
  export DOTFILES_APPS_TABLE="$HOME/catalog.tsv"
  cat > "$DOTFILES_APPS_TABLE" <<'TSV'
# id|platform|method|package|vendor|label|source|note
codex|all|cask|codex|bin:codex|-|https://example.invalid/codex|CLI
painter|darwin|cask|painter|app:Painter.app|-|https://example.invalid/painter|Desktop
painter|linux|flatpak|org.example.Painter|-|-|https://example.invalid/painter|Desktop
sculptor|linux-x86_64|flatpak|org.example.Sculptor|-|community|https://example.invalid/sculptor|Desktop
TSV
}

@test "the catalog lists each app once, in file order" {
  run "$MANAGER" ids
  [ "$status" -eq 0 ]
  [ "$output" = "$(awk -F '|' '!/^#/ && NF && !seen[$1]++ {print $1}' "$REPO/lib/workstation-apps.tsv")" ]
  [[ "$output" == *herdr-desktop* ]] || false
  [[ "$output" != *codex-desktop* ]] || false
}

@test "list is the default and shows each app's selection and route here" {
  printf 'workstationApps = ["codex"]\n' >> "$CONFIG"
  run "$CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex            on   Homebrew cask codex"* ]] || false
  [[ "$output" == *"herdr-cli        off  Homebrew formula herdr"* ]] || false
  [[ "$output" == *"blender          off  manual"* ]] || false
}

@test "preview is read-only and distinguishes Linux manual apps from Homebrew" {
  run "$CLI" preview codex claude-code herdr-cli herdr-desktop blender comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'cask codex'* ]] || false
  [[ "$output" == *'formula herdr'* ]] || false
  [[ "$output" == *'Gear Lever'* ]] || false
  [[ "$output" == *'some apps are left for you'* ]] || false
  [ "$(installs)" -eq 0 ]
}

@test "install uses explicit brew types and is idempotent" {
  run "$MANAGER" install herdr-cli codex claude-code
  [ "$status" -eq 0 ]
  grep -qx 'brew install --formula herdr' "$HOME/calls"
  grep -qx 'brew install --cask codex' "$HOME/calls"
  grep -qx 'brew install --cask claude-code' "$HOME/calls"
  run "$MANAGER" install herdr-cli codex claude-code
  [ "$status" -eq 0 ]
  [ "$(installs)" -eq 3 ]
}

@test "manual entries return incomplete without vendor installs" {
  run "$MANAGER" install blender comfyui claude-desktop chatgpt-desktop herdr-desktop
  [ "$status" -eq 3 ]
  [[ "$output" == *'manual: not automated here'* ]] || false
  [ "$(installs)" -eq 0 ]
}

@test "Apple silicon desktop choices resolve to Homebrew casks" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" install blender comfyui claude-desktop chatgpt-desktop herdr-desktop
  [ "$status" -eq 0 ]
  for app in blender comfy claude chatgpt herdr-app; do
    grep -qx "brew install --cask $app" "$HOME/calls"
  done
}

@test "the ChatGPT app carries Codex's desktop experience; no separate Codex desktop entry" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=x86_64
  run "$MANAGER" preview chatgpt-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *'cask chatgpt'*'Codex desktop experience'* ]] || false
  run "$MANAGER" preview codex-desktop
  [ "$status" -eq 2 ]
}

@test "Intel Mac does not claim Apple silicon-only apps install" {
  export DOTFILES_APPS_OS=darwin
  run "$MANAGER" install comfyui herdr-desktop
  [ "$status" -eq 3 ]
  [ "$(installs)" -eq 0 ]
}

@test "an unknown app on the command line fails before anything installs" {
  run "$MANAGER" install codex nope
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/calls" ]
}

@test "an option-shaped app name is rejected as an app, not passed to grep" {
  run "$CLI" preview -v
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown app: -v'* ]] || false
  [[ "$output" != *[Uu]sage:*grep* ]] || false
  printf 'workstationApps = ["codex"]\n' >> "$CONFIG"
  run "$CLI" enable -e
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown app: -e'* ]] || false
}

@test "a failed brew install is not success, and the other apps still install" {
  export FAIL_INSTALL=codex
  run "$MANAGER" install codex herdr-cli
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed: brew install --cask codex'* ]] || false
  grep -qx 'brew install --formula herdr' "$HOME/calls"
}

@test "Bazzite host: Homebrew apps are refused, host Flatpak apps install" {
  fixture
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" install codex painter
  [ "$status" -eq 3 ]
  [[ "$output" == *'codex'*'Homebrew apps install in the box'* ]] || false
  ! grep -q '^brew install' "$HOME/calls" || false
  grep -qx 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$HOME/calls"
  grep -qx 'flatpak install --user --noninteractive flathub org.example.Painter' "$HOME/calls"
  ! grep -q '^host-exec' "$HOME/calls" || false
}

@test "inside the box: Homebrew installs there and Flatpak apps go to the host" {
  fixture
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  touch "$DOTFILES_APPS_CONTAINER_MARKER"
  run "$MANAGER" install codex painter
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
  grep -qx 'host-exec flatpak install --user --noninteractive flathub org.example.Painter' "$HOME/calls"
  run "$MANAGER" install painter
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (Flatpak)'* ]] || false
  [ "$(grep -c '^flatpak install' "$HOME/calls")" -eq 1 ]
}

@test "plain Linux host: the same split without a box, and macOS has no Flatpak route" {
  fixture
  run "$MANAGER" install codex painter
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
  grep -qx 'flatpak install --user --noninteractive flathub org.example.Painter' "$HOME/calls"
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" install painter
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask painter' "$HOME/calls"
}

@test "a Flatpak app is skipped, not failed, where flatpak is unreachable" {
  fixture
  # A PATH with only the basics, so neither the stub nor a system flatpak is found.
  mkdir -p "$HOME/sys"
  for t in awk sed grep tr uname dirname readlink cat; do ln -s "$(command -v "$t")" "$HOME/sys/$t"; done
  run env PATH="$HOME/sys" "$BASH" "$MANAGER" install painter
  [ "$status" -eq 3 ]
  [[ "$output" == *"flatpak isn't reachable here"* ]] || false
}

@test "without Homebrew, apply skips Homebrew apps instead of failing" {
  mkdir -p "$HOME/sys"
  for t in awk sed grep tr uname dirname readlink cat; do ln -s "$(command -v "$t")" "$HOME/sys/$t"; done
  run env PATH="$HOME/sys" "$BASH" "$MANAGER" apply codex
  [ "$status" -eq 0 ]
  [[ "$output" == *'codex: skipped: Homebrew not found'* ]] || false
}

@test "community packages are labelled wherever they are listed" {
  fixture
  run "$MANAGER" preview sculptor
  [[ "$output" == *'flatpak org.example.Sculptor [community]'* ]] || false
  run "$CLI" list
  [[ "$output" == *'sculptor         off  Flatpak org.example.Sculptor (Flathub, host) [community]'* ]] || false
  export DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" preview sculptor
  [ "$status" -eq 0 ]
  [[ "$output" == *'no route for linux/arm64'* ]] || false
}

@test "the shipped catalog adds no community package without approval" {
  run awk -F '|' '!/^#/ && NF && $6 != "-"' "$REPO/lib/workstation-apps.tsv"
  [ -z "$output" ]
}

@test "a vendor copy of a Homebrew app is reported and skipped, never doubled" {
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions" "$HOME/.claude"
  : > "$HOME/.local/share/claude/versions/1.0"
  ln -s "$HOME/.local/share/claude/versions/1.0" "$HOME/.local/bin/claude"
  run "$MANAGER" install claude-code
  [ "$status" -eq 3 ]
  [[ "$output" == *"found $HOME/.local/bin/claude (vendor installer)"* ]] || false
  [[ "$output" == *'workstation-apps vendor remove claude-code'* ]] || false
  ! grep -q '^brew install' "$HOME/calls" || false
  run "$MANAGER" vendor
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code: $HOME/.local/bin/claude (vendor installer)"* ]] || false
}

@test "an npm global under Homebrew's Node is a vendor copy, removed with npm" {
  mkdir -p "$HOME/brew/lib/node_modules/@anthropic-ai/claude-code"
  : > "$HOME/brew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
  chmod +x "$HOME/brew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
  ln -s ../lib/node_modules/@anthropic-ai/claude-code/cli.js "$HOME/brew/bin/claude"
  run "$MANAGER" install claude-code
  [ "$status" -eq 3 ]
  [[ "$output" == *"found $HOME/brew/bin/claude (global npm package @anthropic-ai/claude-code)"* ]] || false
  ! grep -q '^brew install' "$HOME/calls" || false
  run "$MANAGER" drift claude-code
  [[ "$output" == *$'app-vendor\tclaude-code '"$HOME/brew/bin/claude"* ]] || false
  run "$MANAGER" vendor remove claude-code <<<"y"
  [ "$status" -eq 0 ]
  grep -qxF "npm uninstall -g --prefix $(cd -P "$HOME/brew" && pwd) @anthropic-ai/claude-code" "$HOME/calls"
}

@test "vendor remove asks first and removes nothing unless you confirm" {
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions" "$HOME/.claude"
  : > "$HOME/.local/share/claude/versions/1.0"
  ln -s "$HOME/.local/share/claude/versions/1.0" "$HOME/.local/bin/claude"
  run "$MANAGER" vendor remove claude-code </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *'nothing removed'* ]] || false
  [ -L "$HOME/.local/bin/claude" ]
  run "$MANAGER" vendor remove claude-code <<<"n"
  [ "$status" -eq 1 ]
  [ -L "$HOME/.local/bin/claude" ]
  run "$MANAGER" vendor remove claude-code <<<"y"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude" ] && [ ! -L "$HOME/.local/bin/claude" ]
  [ ! -e "$HOME/.local/share/claude" ]
  [ -d "$HOME/.claude" ]
  run "$MANAGER" install claude-code
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask claude-code' "$HOME/calls"
  run "$MANAGER" vendor claude-code
  [[ "$output" == *'no copies outside Homebrew'* ]] || false
}

@test "an npm-installed copy is removed with npm, not rm" {
  mkdir -p "$HOME/.local/bin" "$HOME/npm/lib/node_modules/@openai/codex/bin"
  : > "$HOME/npm/lib/node_modules/@openai/codex/bin/codex.js"
  ln -s "$HOME/npm/lib/node_modules/@openai/codex/bin/codex.js" "$HOME/.local/bin/codex"
  run "$MANAGER" vendor codex
  [[ "$output" == *'global npm package @openai/codex'* ]] || false
  run "$MANAGER" vendor remove codex <<<"y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm uninstall -g --prefix $(cd -P "$HOME/npm" && pwd) @openai/codex"* ]] || false
  grep -qxF "npm uninstall -g --prefix $(cd -P "$HOME/npm" && pwd) @openai/codex" "$HOME/calls"
}

@test "a macOS app bundle Homebrew doesn't manage goes to the Trash only when confirmed" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  mkdir -p "$HOME/Applications/Claude.app/Contents"
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 3 ]
  ! grep -q '^brew install' "$HOME/calls" || false
  run "$MANAGER" vendor remove claude-desktop <<<"y"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.Trash/Claude.app" ]
  [ ! -e "$HOME/Applications/Claude.app" ]
}

@test "apply never fails on manual, host-skipped or retired apps, and is quiet when installed" {
  run "$MANAGER" apply codex blender future-app
  [ "$status" -eq 0 ]
  [[ "$output" == *'workstation-apps: future-app is no longer in the catalog; skipped. Remove it from the selection with: workstation-apps disable future-app'* ]] || false
  [[ "$output" == *'workstation-apps: blender: manual'* ]] || false
  grep -qx 'brew install --cask codex' "$HOME/calls"
  run "$MANAGER" apply codex
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" apply herdr-cli
  [ "$status" -eq 0 ]
  [[ "$output" == *'herdr-cli: skipped'* ]] || false
  export FAIL_INSTALL=herdr DOTFILES_APPS_INSTALL_TARGET=host
  run "$MANAGER" apply herdr-cli
  [ "$status" -eq 1 ]
}

@test "drift flags selected-but-missing, installed-but-unselected, retired and vendor copies" {
  echo 'cask codex' >> "$HOME/installed"
  mkdir -p "$HOME/.local/bin"; : > "$HOME/.local/bin/claude"
  run "$MANAGER" drift herdr-cli claude-code retired-app
  [ "$status" -eq 0 ]
  [[ "$output" == *$'app-retired\tretired-app\tworkstation-apps disable retired-app'* ]] || false
  [[ "$output" == *$'app-missing\therdr-cli\tworkstation-apps install herdr-cli'* ]] || false
  [[ "$output" == *$'app-unselected\tcodex\tworkstation-apps enable codex (or /codify)'* ]] || false
  [[ "$output" == *$'app-vendor\tclaude-code '"$HOME/.local/bin/claude"$'\tworkstation-apps vendor remove claude-code'* ]] || false
  [[ "$output" != *blender* ]] || false
  ! grep -q 'install' "$HOME/calls" || false
}

@test "drift flags an unselected app's vendor copies apart from Homebrew installs" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  mkdir -p "$HOME/.local/bin" "$HOME/Applications/Claude.app"
  : > "$HOME/.local/bin/herdr"
  echo 'cask codex' >> "$HOME/installed"; : > "$HOME/brew/bin/codex"
  run "$MANAGER" drift
  [ "$status" -eq 0 ]
  [[ "$output" == *$'app-unselected-vendor\therdr-cli '"$HOME/.local/bin/herdr"$'\tworkstation-apps enable herdr-cli, then workstation-apps vendor remove herdr-cli'* ]] || false
  [[ "$output" == *$'app-unselected-vendor\tclaude-desktop '"$HOME/Applications/Claude.app"$'\tworkstation-apps enable claude-desktop, then workstation-apps vendor remove claude-desktop'* ]] || false
  [[ "$output" == *$'app-unselected\tcodex\t'* ]] || false
  [[ "$output" != *$'app-unselected-vendor\tcodex'* ]] || false
  [[ "$output" != *app-vendor* ]] || false
}

@test "drift checks host Flatpaks and leaves Homebrew alone on a Bazzite host" {
  fixture
  echo org.example.Painter >> "$HOME/flatpaks"
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" drift codex
  [ "$status" -eq 0 ]
  [ "$output" = $'app-unselected\tpainter\tworkstation-apps enable painter (or /codify)' ]
}

@test "enable and disable (and on/off) change only the selection; enable then applies" {
  run "$CLI" enable codex blender
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex", "blender"\]' "$CONFIG"
  grep -qx '# keep this' "$CONFIG"
  grep -qx 'agentPlugins = false' "$CONFIG"
  grep -qx 'chezmoi apply --include scripts' "$HOME/calls"
  run "$CLI" off blender
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex"\]' "$CONFIG"
  [[ "$output" == *'nothing was uninstalled'* ]] || false
  run "$CLI" on herdr-cli
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["herdr-cli", "codex"\]' "$CONFIG"
  run "$CLI" disable herdr-cli
  [ "$status" -eq 0 ]
  [ "$(installs)" -eq 0 ]
  run "$CLI" install
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
}

@test "a retired saved app warns and is skipped; it stays saved until disabled" {
  printf 'workstationApps = ["future-app", "codex"]\n' >> "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 0 ]
  [[ "$output" == *'future-app is no longer in the catalog; skipped'*'workstation-apps disable future-app'* ]] || false
  grep -qx 'brew install --cask codex' "$HOME/calls"
  run "$CLI" list
  [[ "$output" == *'future-app       on   retired'* ]] || false
  run "$CLI" enable blender
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex", "blender", "future-app"\]' "$CONFIG"
  run "$CLI" disable future-app
  [ "$status" -eq 0 ]
  grep -qx 'workstationApps = \["codex", "blender"\]' "$CONFIG"
  run "$CLI" disable future-app
  [ "$status" -eq 2 ]
}

@test "empty selection is a no-op and a malformed one is never evaluated" {
  run "$CLI" install
  [ "$status" -eq 0 ]
  [ "$(installs)" -eq 0 ]
  printf 'workstationApps = bad\n' >> "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 2 ]
  [ "$(installs)" -eq 0 ]
}

@test "the selection is parsed only by commands that need it, and a trailing comment is fine" {
  printf 'workstationApps = [\n  "codex",\n]\n' >> "$CONFIG"
  run "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'enable <app>'* ]] || false
  run "$CLI" list
  [ "$status" -eq 0 ]
  [[ "$output" == *'one-line array'*'codex            ?'* ]] || false
  run "$CLI" preview codex
  [ "$status" -eq 0 ]
  run "$CLI" install
  [ "$status" -eq 2 ]
  [[ "$output" == *'one-line array'* ]] || false
  [ "$(installs)" -eq 0 ]
  printf '[data]\nworkstationApps = ["codex"] # mine\ninstallTarget = "host" # here\n' > "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
}

@test "selection parser rejects missing commas and accepts TOML whitespace" {
  printf 'workstationApps = ["codex" "blender"]\n' >> "$CONFIG"
  run "$CLI" preview
  [ "$status" -eq 2 ]
  printf '[data]\nworkstationApps = [\t"codex"\t,\t"herdr-cli"\t]\n' > "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
  grep -qx 'brew install --formula herdr' "$HOME/calls"
}

@test "saved distrobox target also guards the user command" {
  printf '[data]\ninstallTarget = "distrobox"\nworkstationApps = ["codex"]\n' > "$CONFIG"
  run "$CLI" install
  [ "$status" -eq 3 ]
  [ "$(installs)" -eq 0 ]
}

@test "without chezmoi the command never runs lib/ from the current directory" {
  unset DOTFILES_APPS_REPO
  rm "$HOME/bin/chezmoi"
  mkdir -p "$HOME/planted/lib"
  for f in workstation-apps.sh toml-set.sh; do printf '#!/bin/sh\necho PLANTED-RAN\n' > "$HOME/planted/lib/$f"; done
  touch "$HOME/planted/lib/workstation-apps.tsv"
  chmod +x "$HOME/planted/lib/"*.sh
  run env PATH="$HOME/bin:/usr/bin:/bin" "$BASH" -c 'cd "$1" && "$2" "$3" list' _ "$HOME/planted" "$BASH" "$CLI"
  [ "$status" -eq 1 ]
  [[ "$output" == *'chezmoi not found'* ]] || false
  [[ "$output" != *PLANTED-RAN* ]] || false
  DOTFILES_APPS_REPO=lib run "$CLI" list
  [ "$status" -eq 1 ]
}

@test "the apply step renders the saved selection and installs it" {
  render() { PATH="$ORIG_PATH" chezmoi --source "$REPO" --config "$HOME/render.toml" execute-template < "$REPO/home/.chezmoiscripts/run_before_01-workstation-apps.sh.tmpl"; }
  printf '[data]\n' > "$HOME/render.toml"
  run render
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '[data]\nworkstationApps = []\n' > "$HOME/render.toml"
  run render
  [ -z "$output" ]
  printf '[data]\nworkstationApps = "codex"\n' > "$HOME/render.toml"
  run render
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '[data]\ninstallTarget = "distrobox"\nworkstationApps = ["codex", "$(touch pwned)", "herdr-cli"]\n' > "$HOME/render.toml"
  run render
  [ "$status" -eq 0 ]
  [[ "$output" == *'export DOTFILES_APPS_INSTALL_TARGET=distrobox'* ]] || false
  [[ "$output" == *'/lib/workstation-apps.sh" apply codex herdr-cli'* ]] || false
  [[ "$output" != *pwned* ]] || false
  printf '[data]\nworkstationApps = ["codex"]\n' > "$HOME/render.toml"
  render > "$HOME/apply.sh"
  run sh "$HOME/apply.sh"
  [ "$status" -eq 0 ]
  grep -qx 'brew install --cask codex' "$HOME/calls"
}
