#!/usr/bin/env bats
# workstation-apps: the catalog, preview, install, the chezmoi apply step, drift lines and vendor
# copies. Stub brew, apt-get, dpkg-query, sudo, curl, gpg, sha256sum, sha512sum, distrobox-export,
# distrobox-host-exec, xdg-mime, update-desktop-database, npm and chezmoi log their calls into a
# throwaway HOME; PATH leaves out the real ~/.local/bin and Homebrew, so nothing real is found,
# downloaded, installed or exported. The stub curl writes a small stand-in for Blender's tarball.
REPO="$BATS_TEST_DIRNAME/.."
MANAGER="$REPO/lib/workstation-apps.sh"
CLI="$REPO/home/dot_local/bin/executable_workstation-apps"
ORIG_PATH="$PATH"

setup() {
  export HOME="$(mktemp -d)" DOTFILES_APPS_REPO="$REPO"
  export DOTFILES_APPS_OS=linux DOTFILES_APPS_ARCH=x86_64
  export DOTFILES_APPS_CONTAINER_MARKER="$HOME/not-a-container"
  export DOTFILES_APPS_APPLICATIONS="$HOME/Applications"
  export DOTFILES_APPS_ROOT="$HOME/root"
  unset XDG_CONFIG_HOME DOTFILES_APPS_INSTALL_TARGET DOTFILES_APPS_TABLE FAIL_INSTALL BAD_KEY BAD_SUM FAIL_CURL CONTAINER_ID
  mkdir -p "$HOME/bin" "$HOME/brew/bin" "$HOME/.config/chezmoi" "$HOME/.local/share/applications" \
    "$HOME/root/etc/apt/sources.list.d" "$HOME/root/usr/share/keyrings"
  CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
  printf '[data]\ninstallTarget = "host"\n# keep this\nagentPlugins = false\n' > "$CONFIG"
  : > "$HOME/installed"
  : > "$HOME/debs"
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
  # apt: installed packages are lines in $HOME/debs; a local .deb installs as its name before "_".
  cat > "$HOME/bin/apt-get" <<'STUB'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$HOME/calls"
[ "$1" = install ] || exit 0
shift
for a in "$@"; do
  case "$a" in -*) ;; *.deb) b="${a##*/}"; echo "${b%%_*}" >> "$HOME/debs" ;; *) echo "$a" >> "$HOME/debs" ;; esac
done
STUB
  cat > "$HOME/bin/dpkg-query" <<'STUB'
#!/bin/sh
for a in "$@"; do pkg="$a"; done
grep -qxF -- "$pkg" "$HOME/debs" || exit 1
printf 'install ok installed'
STUB
  printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> "$HOME/calls"\nexec "$@"\n' > "$HOME/bin/sudo"
  # curl: the Herdr installer creates its app; any other download is a placeholder file.
  cat > "$HOME/bin/curl" <<'STUB'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$HOME/calls"
[ -z "${FAIL_CURL:-}" ] || exit 22
out="" prev=""
for a in "$@"; do
  case "$prev" in -o|-fsSLo) out="$a" ;; esac
  prev="$a"; url="$a"
done
case "$url" in
  */install.sh) printf 'mkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\n" > "$HOME/.local/bin/herdr-app"\nchmod +x "$HOME/.local/bin/herdr-app"\n' > "$out" ;;
  *.tar.xz) # a small tarball laid out like Blender's: <top>/blender, blender.desktop and blender.svg
    top="${url##*/}"; top="${top%.tar.xz}"; d="$(mktemp -d)"; mkdir "$d/$top"
    printf '#!/bin/sh\n' > "$d/$top/blender"; chmod +x "$d/$top/blender"
    printf '[Desktop Entry]\nName=Blender\nExec=blender %%f\nIcon=blender\nTerminal=false\nType=Application\nMimeType=application/x-blender;\nStartupWMClass=Blender\n' > "$d/$top/blender.desktop"
    echo '<svg/>' > "$d/$top/blender.svg"
    tar -cJf "$out" -C "$d" "$top"; rm -rf "$d" ;;
  *) echo placeholder > "$out" ;;
esac
STUB
  # sha256sum and sha512sum: a download prints its pinned sum (PIN_SHA256 for a tarball, PIN_SHA512
  # for a .deb), unless BAD_SUM names its extension; anything else gets a sum that matches nothing.
  for bits in 256 512; do
    cat > "$HOME/bin/sha${bits}sum" <<STUB
#!/bin/sh
case "\$1" in *.tar.xz) s="\$PIN_SHA256" ;; *.deb) s="\$PIN_SHA512" ;; *) s=none ;; esac
[ "\$s" = "\$PIN_SHA${bits}" ] || s=wrong-algorithm
[ "\${BAD_SUM:-}" != "\${1##*.}" ] || s=0000
printf '%s  %s\n' "\$s" "\$1"
STUB
  done
  # The vendors' published sums: blender.org's sha256 file for 5.3.0 and Comfy's latest-linux.yml for 1.1.9.
  export PIN_SHA256=dacb8264197a3f7fda6001285a5a506fc97ee943881261c2c3bd63c882f22e05
  export PIN_SHA512=60fdc25374000d0c26b94257d8907fb5a1aa318df8bbad0c867b6ae0831859eef611d594446d7fcb8db4adac57850c72d4a5bf65159a0de2431e3c35092bb68c
  cat > "$HOME/bin/gpg" <<'STUB'
#!/bin/sh
if [ -n "${BAD_KEY:-}" ]; then echo 'fpr:::::::::0000000000000000000000000000000000000000:'; else echo 'fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:'; fi
STUB
  # distrobox-export --app <command>: the launcher it writes, named <box>-<desktop id>.desktop.
  cat > "$HOME/bin/distrobox-export" <<'STUB'
#!/bin/sh
printf 'distrobox-export %s\n' "$*" >> "$HOME/calls"
case "$2" in
  chatgpt) id=chatgpt ;; claude-desktop) id=com.anthropic.Claude ;; painter) id=org.example.Painter ;;
  comfyui-desktop-2) id=comfyui-desktop-2 ;;
  /*.desktop) [ -f "$2" ] || exit 1; id="${2##*/}"; id="${id%.desktop}" ;;
  *) exit 1 ;;
esac
printf '[Desktop Entry]\nName=%s\nExec=/usr/bin/distrobox-enter -n ubuntu-dev -- %s %%U\n' "$2" "$2" > "$HOME/.local/share/applications/ubuntu-dev-$id.desktop"
STUB
  # xdg-mime: defaults live in $HOME/mime/<scheme>. Refreshing the index lets an exported ChatGPT
  # take over https when the host pinned no browser, as GNOME can.
  mkdir -p "$HOME/mime"
  cat > "$HOME/bin/xdg-mime" <<'STUB'
#!/bin/sh
case "$1" in query) ;; *) printf 'xdg-mime %s\n' "$*" >> "$HOME/calls" ;; esac
case "$1 $2" in
  "query default") cat "$HOME/mime/${3#x-scheme-handler/}" 2>/dev/null || true ;;
  "default "*) echo "$2" > "$HOME/mime/${3#x-scheme-handler/}" ;;
esac
STUB
  cat > "$HOME/bin/update-desktop-database" <<'STUB'
#!/bin/sh
printf 'update-desktop-database %s\n' "$*" >> "$HOME/calls"
[ ! -f "$1/ubuntu-dev-chatgpt.desktop" ] || { echo ubuntu-dev-chatgpt.desktop > "$HOME/mime/https"; echo ubuntu-dev-chatgpt.desktop > "$HOME/mime/http"; }
STUB
  printf '#!/bin/sh\nprintf "host-exec %%s\\n" "$*" >> "$HOME/calls"\nexec "$@"\n' > "$HOME/bin/distrobox-host-exec"
  printf '#!/bin/sh\nprintf "npm %%s\\n" "$*" >> "$HOME/calls"\n' > "$HOME/bin/npm"
  printf '#!/bin/sh\nprintf "chezmoi %%s\\n" "$*" >> "$HOME/calls"\n' > "$HOME/bin/chezmoi"
  chmod +x "$HOME/bin/"*
  mkdir -p "$HOME/shell"; ln -s "$BASH" "$HOME/shell/bash"
  export PATH="$HOME/bin:$HOME/brew/bin:$HOME/shell:/usr/bin:/bin"
}
teardown() { rm -rf "$HOME"; }

installs() { { cat "$HOME/calls" 2>/dev/null || true; } | grep -c -e '^brew install' -e '^apt-get install' -e '^curl ' || true; }
in_box() { touch "$DOTFILES_APPS_CONTAINER_MARKER"; export DOTFILES_APPS_INSTALL_TARGET=distrobox; }
fixture() { # a catalog with one apt app and one community-labelled apt app
  export DOTFILES_APPS_TABLE="$HOME/catalog.tsv"
  cat > "$DOTFILES_APPS_TABLE" <<'TSV'
# id|platform|method|package|vendor|label|source|note
codex|all|cask|codex|bin:codex|-|https://example.invalid/codex|CLI
painter|darwin|cask|painter|app:Painter.app|-|https://example.invalid/painter|Desktop
painter|linux|apt|painter|desktop:painter:org.example.Painter:painter|-|https://example.invalid/painter|Desktop
sculptor|linux-x86_64|apt|sculptor|-|community|https://example.invalid/sculptor|Desktop
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
  [[ "$output" == *"blender          off  official tarball blender (in the box on Bazzite, exported to the host menu)"* ]] || false
  [[ "$output" == *"comfyui          off  apt comfyui-desktop-2 (in the box on Bazzite, exported to the host menu)"* ]] || false
  export DOTFILES_APPS_ARCH=arm64
  run "$CLI"
  [[ "$output" == *"blender          off  manual"* ]] || false
}

@test "preview is read-only and distinguishes Linux manual apps from Homebrew" {
  run "$CLI" preview codex claude-code herdr-cli herdr-desktop blender comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'cask codex'* ]] || false
  [[ "$output" == *'formula herdr'* ]] || false
  [[ "$output" == *'not installed (official tarball https://mirror.blender.org/release/'* ]] || false
  [[ "$output" == *'not installed (apt)'* ]] || false
  export DOTFILES_APPS_ARCH=arm64
  run "$CLI" preview codex blender comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'some apps are left for you'* ]] || false
  [ "$(installs)" -eq 0 ]
  [ ! -e "$HOME/.local/opt" ]
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
  export DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" install blender comfyui chatgpt-desktop
  [ "$status" -eq 3 ]
  [[ "$output" == *'Only the x86_64 tarball is automated here'* ]] || false
  [[ "$output" == *'Only the x86_64 package is automated here'* ]] || false
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

@test "Bazzite host: Homebrew and apt apps wait for the box; the Herdr installer still runs" {
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" install codex claude-desktop herdr-desktop
  [ "$status" -eq 3 ]
  [[ "$output" == *'Homebrew apps install in the box'* ]] || false
  [[ "$output" == *'apt apps install in the box'* ]] || false
  ! grep -q -e '^brew install' -e '^apt-get' -e '^distrobox-export' "$HOME/calls" || false
  grep -q '^curl -fsSL -o .*/install\.sh https://releases\.herdr\.dev/app/install\.sh$' "$HOME/calls"
  [ -x "$HOME/.local/bin/herdr-app" ]
}

@test "in the box: Claude desktop installs from Anthropic's pinned repo, then exports with a link handler" {
  in_box
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 0 ]
  grep -qx 'sudo apt-get install -y curl gnupg' "$HOME/calls"
  grep -qx "sudo curl -fsSLo $HOME/root/usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc" "$HOME/calls"
  grep -qx 'deb \[arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc\] https://downloads.claude.ai/claude-desktop/apt/stable stable main' "$HOME/root/etc/apt/sources.list.d/claude-desktop.list"
  grep -qx 'sudo apt-get update' "$HOME/calls"
  grep -qx 'sudo apt-get install -y claude-desktop libsecret-1-0' "$HOME/calls"
  grep -qx 'distrobox-export --app claude-desktop' "$HOME/calls"
  A="$HOME/.local/share/applications"
  [ -f "$A/ubuntu-dev-com.anthropic.Claude.desktop" ]
  # The app rewrites its default to com.anthropic.Claude.desktop on every start; that name opens the box.
  grep -qx 'NoDisplay=true' "$A/com.anthropic.Claude.desktop"
  grep -qx 'X-Dotfiles-Alias-Of=ubuntu-dev-com.anthropic.Claude.desktop' "$A/com.anthropic.Claude.desktop"
  grep -qx 'Exec=/usr/bin/distrobox-enter -n ubuntu-dev -- claude-desktop %U' "$A/com.anthropic.Claude.desktop"
  grep -qx 'host-exec xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude' "$HOME/calls"
  grep -qx "host-exec update-desktop-database $A" "$HOME/calls"
  ! grep -q -- '--delete' "$HOME/calls" || false
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (apt)'* ]] || false
  [ "$(grep -c '^sudo apt-get install -y claude-desktop' "$HOME/calls")" -eq 1 ]
  [ "$(grep -c '^distrobox-export' "$HOME/calls")" -eq 1 ]
}

@test "a repository key with the wrong fingerprint stops the Claude desktop install" {
  in_box
  export BAD_KEY=1
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 1 ]
  [[ "$output" == *'unexpected key fingerprint'* ]] || false
  [ ! -e "$HOME/root/usr/share/keyrings/claude-desktop-archive-keyring.asc" ]
  [ ! -e "$HOME/root/etc/apt/sources.list.d/claude-desktop.list" ]
  ! grep -q 'apt-get install -y claude-desktop' "$HOME/calls" || false
}

@test "in the box: ChatGPT installs from OpenAI's package, and a host launcher of the same name is never touched" {
  in_box
  A="$HOME/.local/share/applications"
  printf '[Desktop Entry]\nName=host ChatGPT\n' > "$A/chatgpt.desktop"
  cp "$A/chatgpt.desktop" "$HOME/host-launcher"
  run "$MANAGER" install chatgpt-desktop
  [ "$status" -eq 0 ]
  grep -q '^curl -fsSL -o .*/chatgpt_amd64\.deb https://persistent\.oaistatic\.com/codex-app-prod/linux/deb/latest/chatgpt_amd64\.deb$' "$HOME/calls"
  grep -q '^sudo apt-get install -y .*/chatgpt_amd64.deb libsecret-1-0$' "$HOME/calls"
  [ -f "$A/ubuntu-dev-chatgpt.desktop" ]
  cmp "$HOME/host-launcher" "$A/chatgpt.desktop"
  [[ "$output" == *'chatgpt.desktop belongs to another install'* ]] || false
  grep -qx 'host-exec xdg-mime default ubuntu-dev-chatgpt.desktop x-scheme-handler/codex' "$HOME/calls"
  ! grep -q -- '--delete' "$HOME/calls" || false
  export DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" preview chatgpt-desktop
  [[ "$output" == *'manual'*'Only the x86_64 package'* ]] || false
}

@test "exporting ChatGPT keeps the host's default browser for http and https" {
  in_box
  echo firefox.desktop > "$HOME/mime/https"; echo firefox.desktop > "$HOME/mime/http"
  run "$MANAGER" install chatgpt-desktop
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/mime/https")" = firefox.desktop ]
  [ "$(cat "$HOME/mime/http")" = firefox.desktop ]
  grep -qx 'host-exec xdg-mime default firefox.desktop x-scheme-handler/https' "$HOME/calls"
  [ "$(cat "$HOME/mime/codex")" = chatgpt.desktop ]
  grep -qx 'NoDisplay=true' "$HOME/.local/share/applications/chatgpt.desktop"
}

BLENDER_URL=https://mirror.blender.org/release/Blender5.3/blender-5.3.0-linux-x64.tar.xz
COMFY_URL=https://download.todesktop.com/241130tqe9q3y/comfyui-desktop-2-1.1.9-build-2611063zxyb71c9-amd64.deb

@test "in the box: Blender unpacks the pinned official tarball, then exports its launcher" {
  in_box
  run "$MANAGER" install blender
  [ "$status" -eq 0 ]
  grep -q "^curl -fsSL -o .*/blender-5\.3\.0-linux-x64\.tar\.xz $BLENDER_URL\$" "$HOME/calls"
  O="$HOME/.local/opt/blender" A="$HOME/.local/share/applications"
  [ -x "$O/blender-5.3.0-linux-x64/blender" ]
  [ "$(readlink "$O/current")" = blender-5.3.0-linux-x64 ]
  # The launcher calls the stable current link, so a pin bump needs no new export.
  grep -qxF "Exec=\"$O/current/blender\" %f" "$O/blender.desktop"
  grep -qxF "Icon=$O/current/blender.svg" "$O/blender.desktop"
  grep -qx 'StartupWMClass=Blender' "$O/blender.desktop"
  grep -qxF "distrobox-export --app $O/blender.desktop" "$HOME/calls"
  [ -f "$A/ubuntu-dev-blender.desktop" ]
  # No link scheme, so no hidden alias and no xdg-mime default; the user's menu has no host copy.
  [ ! -e "$A/blender.desktop" ]
  ! grep -q '^host-exec xdg-mime default' "$HOME/calls" || false
  grep -qx "host-exec update-desktop-database $A" "$HOME/calls"
  ! grep -q -- '--delete' "$HOME/calls" || false
  ! ls -A "$O" | grep -q '^\.unpack' || false
  run "$MANAGER" install blender
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (official tarball)'* ]] || false
  [ "$(grep -c '^curl ' "$HOME/calls")" -eq 1 ]
  [ "$(grep -c '^distrobox-export' "$HOME/calls")" -eq 1 ]
}

BLENDER_LIBS="libxi6 libsm6 libxkbcommon0 libxrender1 libxxf86vm1 libxfixes3 libgl1"

@test "in the box: Blender's missing runtime libraries are installed with apt, once" {
  in_box
  echo libgl1 >> "$HOME/debs"
  run "$MANAGER" install blender
  [ "$status" -eq 0 ]
  grep -qx 'sudo apt-get install -y libxi6 libsm6 libxkbcommon0 libxrender1 libxxf86vm1 libxfixes3' "$HOME/calls"
  for l in $BLENDER_LIBS; do grep -qx "$l" "$HOME/debs"; done
  # A rebuilt box keeps the tarball in the shared home but loses its libraries.
  : > "$HOME/debs"
  run "$MANAGER" apply blender
  [ "$status" -eq 0 ]
  grep -qx "sudo apt-get install -y $BLENDER_LIBS" "$HOME/calls"
  [ "$(grep -c '^curl ' "$HOME/calls")" -eq 1 ]
  : > "$HOME/calls"
  run "$MANAGER" apply blender
  [ "$status" -eq 0 ]
  ! grep -q '^apt-get' "$HOME/calls" || false
}

@test "Blender's libraries already present: no apt call" {
  in_box
  for l in $BLENDER_LIBS; do echo "$l" >> "$HOME/debs"; done
  run "$MANAGER" install blender
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (official tarball)'* ]] || false
  ! grep -q '^apt-get' "$HOME/calls" || false
}

@test "a Linux host without apt still installs the Blender tarball, without its libraries" {
  rm "$HOME/bin/apt-get" "$HOME/bin/dpkg-query" "$HOME/bin/sudo"
  mkdir -p "$HOME/sys"
  for t in awk sed grep tr uname dirname readlink cat id mktemp mkdir rm mv ln cp chmod tar xz; do
    ln -s "$(command -v "$t")" "$HOME/sys/$t"
  done
  run env PATH="$HOME/bin:$HOME/sys" "$BASH" "$MANAGER" install blender
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (official tarball)'* ]] || false
  [ -x "$HOME/.local/opt/blender/current/blender" ]
  [ -f "$HOME/.local/share/applications/blender.desktop" ]
  ! grep -q 'apt-get' "$HOME/calls" || false
}

@test "in the box: Comfy Desktop installs from Comfy's pinned package, then exports" {
  in_box
  run "$MANAGER" install comfyui
  [ "$status" -eq 0 ]
  grep -q "^curl -fsSL -o .*/comfyui-desktop-2_amd64\.deb $COMFY_URL\$" "$HOME/calls"
  grep -q '^sudo apt-get install -y .*/comfyui-desktop-2_amd64\.deb$' "$HOME/calls"
  grep -qx 'distrobox-export --app comfyui-desktop-2' "$HOME/calls"
  A="$HOME/.local/share/applications"
  [ -f "$A/ubuntu-dev-comfyui-desktop-2.desktop" ]
  [ ! -e "$A/comfyui-desktop-2.desktop" ]
  ! grep -q '^host-exec xdg-mime default' "$HOME/calls" || false
  ! grep -q -- '--delete' "$HOME/calls" || false
  # Nothing about models: no model paths, no extra_model_paths.yaml, no model downloads.
  ! grep -rqi 'model' "$HOME/calls" || false
  [ ! -e "$HOME/ComfyUI-Shared" ]
  run "$MANAGER" install comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (apt)'* ]] || false
  [ "$(grep -c '^curl ' "$HOME/calls")" -eq 1 ]
  [ "$(grep -c '^distrobox-export' "$HOME/calls")" -eq 1 ]
}

@test "a checksum mismatch stops that app, and the other apps still install" {
  in_box
  export BAD_SUM=deb
  run "$MANAGER" install comfyui blender
  [ "$status" -eq 1 ]
  [[ "$output" == *'comfyui-desktop-2_amd64.deb failed its sha512 check'* ]] || false
  [[ "$output" == *'failed: apt install comfyui-desktop-2'* ]] || false
  ! grep -q 'apt-get install -y .*comfyui-desktop-2' "$HOME/calls" || false
  [ ! -e "$HOME/.local/share/applications/ubuntu-dev-comfyui-desktop-2.desktop" ]
  [ -f "$HOME/.local/share/applications/ubuntu-dev-blender.desktop" ]
  export BAD_SUM=xz
  : > "$HOME/calls"
  rm -rf "$HOME/.local/opt/blender" "$HOME/.local/share/applications/ubuntu-dev-blender.desktop"
  run "$MANAGER" install blender claude-desktop
  [ "$status" -eq 1 ]
  [[ "$output" == *'blender-5.3.0-linux-x64.tar.xz failed its sha256 check'* ]] || false
  [ ! -e "$HOME/.local/opt/blender/blender-5.3.0-linux-x64" ]
  [ ! -e "$HOME/.local/opt/blender/current" ]
  ! grep -q '^distrobox-export --app /' "$HOME/calls" || false
  grep -qx 'sudo apt-get install -y claude-desktop libsecret-1-0' "$HOME/calls"
}

@test "Bazzite host: Blender and Comfy wait for the box, like the other desktop apps" {
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" install blender comfyui
  [ "$status" -eq 3 ]
  [[ "$output" == *'tarball apps install in the box'* ]] || false
  [[ "$output" == *'apt apps install in the box'* ]] || false
  [ ! -e "$HOME/calls" ]
  [ ! -e "$HOME/.local/opt" ]
  run "$MANAGER" apply blender comfyui
  [ "$status" -eq 0 ]
  [[ "$output" == *'blender: skipped'* ]] || false
}

@test "plain Linux host: Blender's launcher goes in the user's menu, and Comfy installs natively" {
  A="$HOME/.local/share/applications" O="$HOME/.local/opt/blender"
  run "$MANAGER" install blender comfyui
  [ "$status" -eq 0 ]
  grep -qxF "Exec=\"$O/current/blender\" %f" "$A/blender.desktop"
  grep -q '^sudo apt-get install -y .*/comfyui-desktop-2_amd64\.deb$' "$HOME/calls"
  ! grep -q -e '^distrobox-export' -e '^host-exec' -e '^xdg-mime' "$HOME/calls" || false
  # A blender.desktop from another install is left alone.
  printf '[Desktop Entry]\nName=distro Blender\n' > "$A/blender.desktop"
  cp "$A/blender.desktop" "$HOME/other-launcher"
  run "$MANAGER" install blender
  [ "$status" -eq 0 ]
  cmp "$HOME/other-launcher" "$A/blender.desktop"
  [[ "$output" == *'blender.desktop belongs to another install'* ]] || false
}

@test "macOS keeps Blender and Comfy on Homebrew; Linux arm64 leaves them manual" {
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" routes
  [[ "$output" == *$'blender\tcask\tblender\t-'* ]] || false
  [[ "$output" == *$'comfyui\tcask\tcomfy\t-'* ]] || false
  export DOTFILES_APPS_ARCH=x86_64
  run "$MANAGER" routes
  [[ "$output" == *$'blender\tcask\tblender\t-'* ]] || false
  [[ "$output" == *$'comfyui\tmanual\t-\t-'* ]] || false
  export DOTFILES_APPS_OS=linux DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" routes
  [[ "$output" == *$'blender\tmanual\t-\t-'* ]] || false
  [[ "$output" == *$'comfyui\tmanual\t-\t-'* ]] || false
}

@test "drift checks the Blender tarball in the box and leaves it alone on the Bazzite host" {
  mkdir -p "$HOME/.local/opt/blender/blender-5.3.0-linux-x64"
  printf '#!/bin/sh\n' > "$HOME/.local/opt/blender/blender-5.3.0-linux-x64/blender"
  chmod +x "$HOME/.local/opt/blender/blender-5.3.0-linux-x64/blender"
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" drift
  [ "$status" -eq 0 ]
  [[ "$output" != *blender* ]] || false
  touch "$DOTFILES_APPS_CONTAINER_MARKER"
  run "$MANAGER" drift
  [[ "$output" == *$'app-unselected\tblender\tworkstation-apps enable blender (or /codify)'* ]] || false
  rm -rf "$HOME/.local/opt/blender"
  run "$MANAGER" drift blender
  [[ "$output" == *$'app-missing\tblender\tworkstation-apps install blender'* ]] || false
}

@test "plain Ubuntu host: apt apps install natively, with no export or host crossing" {
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 0 ]
  grep -qx 'sudo apt-get install -y claude-desktop libsecret-1-0' "$HOME/calls"
  ! grep -q -e '^distrobox-export' -e '^host-exec' -e '^xdg-mime' "$HOME/calls" || false
  [ ! -e "$HOME/.local/share/applications/com.anthropic.Claude.desktop" ]
}

@test "a Linux host without apt skips apt apps instead of failing" {
  mkdir -p "$HOME/sys"
  for t in awk sed grep tr uname dirname readlink cat; do ln -s "$(command -v "$t")" "$HOME/sys/$t"; done
  run env PATH="$HOME/sys" "$BASH" "$MANAGER" apply claude-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *'claude-desktop: skipped: needs apt (Debian or Ubuntu)'* ]] || false
}

@test "Herdr desktop runs Herdr's installer only when the app is missing" {
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/herdr-app" ]
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed (vendor installer; it updates itself)'* ]] || false
  [ "$(grep -c '^curl ' "$HOME/calls")" -eq 1 ]
  rm "$HOME/.local/bin/herdr-app"
  export FAIL_CURL=1
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 1 ]
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  unset FAIL_CURL
  run "$MANAGER" install herdr-desktop
  grep -qx 'brew install --cask herdr-app' "$HOME/calls"
}

@test "drift checks apt apps in the box and leaves them alone on the Bazzite host" {
  echo claude-desktop >> "$HOME/debs"
  export DOTFILES_APPS_INSTALL_TARGET=distrobox
  run "$MANAGER" drift
  [ "$status" -eq 0 ]
  [[ "$output" != *claude-desktop* ]] || false
  touch "$DOTFILES_APPS_CONTAINER_MARKER"
  run "$MANAGER" drift
  [[ "$output" == *$'app-unselected\tclaude-desktop\tworkstation-apps enable claude-desktop (or /codify)'* ]] || false
  run "$MANAGER" drift claude-desktop chatgpt-desktop
  [[ "$output" == *$'app-missing\tchatgpt-desktop\tworkstation-apps install chatgpt-desktop'* ]] || false
  [[ "$output" != *$'\tclaude-desktop\t'* ]] || false
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
  [[ "$output" == *'apt sculptor [community]'* ]] || false
  run "$CLI" list
  [[ "$output" == *'sculptor         off  apt sculptor (in the box on Bazzite, exported to the host menu) [community]'* ]] || false
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

@test "a bun or yarn global is reported, and vendor remove leaves it to that package manager" {
  mkdir -p "$HOME/.bun/bin" "$HOME/.bun/install/global/node_modules/@anthropic-ai/claude-code"
  : > "$HOME/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js"
  chmod +x "$HOME/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js"
  ln -s "$HOME/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js" "$HOME/.bun/bin/claude"
  export PATH="$HOME/.bun/bin:$PATH"
  run "$MANAGER" vendor claude-code
  [[ "$output" == *"$HOME/.bun/bin/claude (global package @anthropic-ai/claude-code from another package manager"* ]] || false
  run "$MANAGER" vendor remove claude-code <<<"y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$HOME/.bun/bin/claude (global package @anthropic-ai/claude-code): uninstall it with the package manager that installed it"* ]] || false
  [[ "$output" != *'removed.'* ]] || false
  [ -L "$HOME/.bun/bin/claude" ]
  ! grep -q '^npm' "$HOME/calls" || false
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
  export DOTFILES_APPS_ARCH=arm64
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

icon_cache() { # a stub gtk-update-icon-cache and an existing hicolor cache under the throwaway HOME
  printf '#!/bin/sh\nprintf "gtk-update-icon-cache %%s\\n" "$*" >> "$HOME/calls"\n' > "$HOME/bin/gtk-update-icon-cache"
  chmod +x "$HOME/bin/gtk-update-icon-cache"
  mkdir -p "$HOME/.local/share/icons/hicolor"; : > "$HOME/.local/share/icons/hicolor/icon-theme.cache"
}

@test "in the box: exporting an app refreshes the host's hicolor icon cache" {
  in_box; icon_cache
  run "$MANAGER" install claude-desktop
  [ "$status" -eq 0 ]
  grep -qx "host-exec gtk-update-icon-cache -f -t $HOME/.local/share/icons/hicolor" "$HOME/calls"
}

@test "Linux host: the Herdr installer is followed by a direct icon cache refresh" {
  icon_cache
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  grep -qx "gtk-update-icon-cache -f -t $HOME/.local/share/icons/hicolor" "$HOME/calls"
  ! grep -q '^host-exec gtk' "$HOME/calls" || false
}

@test "a missing hicolor dir or cache is a silent no-op" {
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  ! grep -q 'gtk-update-icon-cache' "$HOME/calls" || false
  rm -rf "$HOME/.local/bin/herdr-app"; icon_cache; rm "$HOME/.local/share/icons/hicolor/icon-theme.cache"
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  ! grep -q 'gtk-update-icon-cache' "$HOME/calls" || false
}

without_icon_tool() { # PATH keeps the system tools but no gtk-update-icon-cache, stub or real
  icon_cache; rm "$HOME/bin/gtk-update-icon-cache"
  mkdir -p "$HOME/sys"
  [ /bin -ef /usr/bin ] || ln -sf /bin/* "$HOME/sys/"
  ln -sf /usr/bin/* "$HOME/sys/"
  rm -f "$HOME/sys/gtk-update-icon-cache"
  NO_ICON_TOOL_PATH="$HOME/bin:$HOME/brew/bin:$HOME/shell:$HOME/sys"
  ! PATH="$NO_ICON_TOOL_PATH" command -v gtk-update-icon-cache || false
}

@test "Linux host without gtk-update-icon-cache: the Herdr install succeeds silently" {
  without_icon_tool
  run env PATH="$NO_ICON_TOOL_PATH" "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  [[ "$output" != *gtk-update-icon-cache* ]] || false
  [ -x "$HOME/.local/bin/herdr-app" ]
}

@test "in the box, a host without gtk-update-icon-cache: the export succeeds silently" {
  in_box; without_icon_tool
  run env PATH="$NO_ICON_TOOL_PATH" "$MANAGER" install claude-desktop
  [ "$status" -eq 0 ]
  [[ "$output" != *gtk-update-icon-cache* ]] || false
  grep -q '^distrobox-export --app claude-desktop' "$HOME/calls"
}

@test "a failing icon cache refresh never fails the install" {
  icon_cache
  printf '#!/bin/sh\necho boom >&2\nexit 1\n' > "$HOME/bin/gtk-update-icon-cache"
  run "$MANAGER" install herdr-desktop
  [ "$status" -eq 0 ]
  [[ "$output" != *boom* ]] || false
}

@test "macOS never refreshes an icon cache" {
  icon_cache
  export DOTFILES_APPS_OS=darwin DOTFILES_APPS_ARCH=arm64
  run "$MANAGER" install herdr-desktop claude-desktop
  [ "$status" -eq 0 ]
  ! grep -q 'gtk-update-icon-cache' "$HOME/calls" || false
}
