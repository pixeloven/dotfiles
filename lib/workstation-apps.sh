#!/usr/bin/env bash
# Workstation app catalog (lib/workstation-apps.tsv): preview, install, drift and vendor copies.
# Usage: workstation-apps.sh ids | routes
#        workstation-apps.sh preview|install [--saved] [app...]
#        workstation-apps.sh apply [app...]      the chezmoi apply step for the saved selection
#        workstation-apps.sh drift [app...]      kind<TAB>target<TAB>action lines for bin/drift
#        workstation-apps.sh vendor [app...] | vendor remove <app>...
# Routes: formula and cask install with Homebrew (inside the box when installTarget = distrobox).
# apt installs a vendor's Ubuntu package (inside the box on Bazzite, where distrobox-export then
# puts it in the host menu; natively on an apt-based host). installer runs a vendor's official
# Linux installer into ~/.local when the app is missing. manual is never automated. An app named on the command line must be in the catalog; with --saved (and
# for apply and drift) an ID the catalog no longer has is a retired app: warned about and skipped.
# Copies of a Homebrew-routed app that Homebrew doesn't manage are left alone and reported; only
# `vendor remove`, after you confirm, uninstalls them. Never execute this output as shell code.
# Test seams: DOTFILES_APPS_OS, _ARCH, _TABLE, _CONTAINER_MARKER, _APPLICATIONS, _INSTALL_TARGET,
# _ROOT (prefix for /etc and /usr/share/keyrings in the apt recipes).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
table="${DOTFILES_APPS_TABLE:-$repo/lib/workstation-apps.tsv}"
cmd="${1:-preview}"
[ "$#" -eq 0 ] || shift
os="${DOTFILES_APPS_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
arch="${DOTFILES_APPS_ARCH:-$(uname -m)}"
case "$arch" in aarch64) arch=arm64 ;; esac
case "$os" in darwin|linux) ;; *) echo "workstation-apps: unsupported OS: $os" >&2; exit 2 ;; esac
target="${DOTFILES_APPS_INSTALL_TARGET:-host}"
case "$target" in host|distrobox) ;; *) echo "workstation-apps: invalid installTarget: $target" >&2; exit 2 ;; esac
in_box=false
[ ! -e "${DOTFILES_APPS_CONTAINER_MARKER:-/run/.containerenv}" ] || in_box=true
apps_dir="${DOTFILES_APPS_APPLICATIONS:-/Applications}"
root="${DOTFILES_APPS_ROOT:-}"
box="${CONTAINER_ID:-ubuntu-dev}"

ids() { awk -F '|' '!/^#/ && NF && !seen[$1]++ {print $1}' "$table"; }
known() { ids | grep -qxF -- "$1"; }
row() { # <id> : the catalog row for this OS and arch (os-arch, then os, then all)
  awk -F '|' -v id="$1" -v os="$os" -v arch="$arch" '
    $1 == id {
      if ($2 == "all") base=$0
      if ($2 == os) platform=$0
      if ($2 == os "-" arch) exact=$0
    }
    END { if (exact) print exact; else if (platform) print platform; else if (base) print base }
  ' "$table"
}
fields() { # <id> : sets method package vendor label source note (method empty: no row here)
  local record
  record="$(row "$1")"
  method="" package="" vendor="" label="" source="" note=""
  [ -n "$record" ] || return 0
  IFS='|' read -r _ _ method package vendor label source note <<<"$record"
  return 0
}
tag() { [ "$label" = community ] && printf ' [community]' || true; }

# Homebrew: allowed on a host target, or inside a container (the box) for a distrobox target.
brew_here() { [ "$target" = host ] || $in_box; }
brew_lists=""
brew_installed() { # <method> <package>
  if [ -z "$brew_lists" ]; then
    brew_lists="$({ brew list --formula 2>/dev/null | sed 's/^/formula /'; brew list --cask 2>/dev/null | sed 's/^/cask /'; } || true)"
    brew_lists="${brew_lists:-none}"
  fi
  grep -qxF -- "$1 $2" <<<"$brew_lists"
}
brew_prefix="" brew_real=""
under_brew() { # <path> : Homebrew's own copy; an npm global under Homebrew's Node is not
  if [ -z "$brew_prefix" ]; then
    brew_prefix="$(brew --prefix 2>/dev/null || echo /nonexistent-brew)"
    brew_real="$(cd -P "$brew_prefix" 2>/dev/null && pwd || echo "$brew_prefix")"
  fi
  case "$1" in "$brew_prefix"/*) ;; *) return 1 ;; esac
  case "$(resolve "$1")" in "$brew_real"/lib/node_modules/*) return 1 ;; esac
  return 0
}

# apt: the box's (installTarget = distrobox), or an apt-based host's. Never the Bazzite host.
apt_skip() { # prints why apt apps can't install here; nothing when they can
  [ "$os" = linux ] || { echo "apt apps are Linux only"; return 0; }
  if [ "$target" = distrobox ] && ! $in_box; then echo "installTarget is distrobox and this is the host; apt apps install in the box"; return 0; fi
  command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1 || echo "needs apt (Debian or Ubuntu)"
}
apt_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
apt_recipe() { # <package> : the vendor's documented Ubuntu install, plus libsecret for the keyring
  local key list tmp fpr
  case "$1" in
    claude-desktop) # Anthropic's signed apt repository; the key is checked against its fingerprint
      key="$root/usr/share/keyrings/claude-desktop-archive-keyring.asc"
      list="$root/etc/apt/sources.list.d/claude-desktop.list"
      if [ ! -s "$list" ]; then
        as_root apt-get install -y curl gnupg || return 1
        as_root curl -fsSLo "$key" https://downloads.claude.ai/claude-desktop/key.asc || return 1
        fpr="$(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
        if [ "$fpr" != 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE ]; then
          echo "workstation-apps: unexpected key fingerprint for claude-desktop (${fpr:-none}); not adding the repository" >&2
          as_root rm -f "$key"; return 1
        fi
        echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" |
          as_root tee "$list" >/dev/null || return 1
        as_root apt-get update || return 1
      fi
      as_root apt-get install -y claude-desktop libsecret-1-0 ;;
    chatgpt) # OpenAI's Ubuntu package; its postinst adds OpenAI's apt repository for updates
      tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/chatgpt_amd64.deb" https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb &&
        as_root apt-get install -y "$tmp/chatgpt_amd64.deb" libsecret-1-0
      local rc=$?; rm -rf "$tmp"; return "$rc" ;;
    *) as_root apt-get install -y "$1" ;;
  esac
}
on_host() { # <cmd>... : run on the host; from the box through distrobox-host-exec, from $HOME
  if $in_box; then (cd "$HOME" && distrobox-host-exec "$@"); else "$@"; fi
}
refresh_icon_cache() { # Linux only: GNOME misses new hicolor icons until the host's cache is rebuilt
  local dir="$HOME/.local/share/icons/hicolor"
  [ "$os" = linux ] && [ -f "$dir/icon-theme.cache" ] || return 0
  on_host gtk-update-icon-cache -f -t "$dir" >/dev/null 2>&1 || true
}
export_app() { # in the box only: launcher in the host menu, a link handler the app's own rewrite matches
  local cmdname desktop scheme apps exported alias default
  $in_box || return 0
  IFS=: read -r _ cmdname desktop scheme <<<"$vendor"
  [ -n "$desktop" ] || return 0
  apps="$HOME/.local/share/applications" exported="$apps/$box-$desktop.desktop" alias="$apps/$desktop.desktop"
  # ChatGPT, for one, registers for http and https; keep the host's browser as their default.
  local s web=""
  for s in http https; do web="$web $s=$(on_host xdg-mime query default "x-scheme-handler/$s" 2>/dev/null || true)"; done
  if [ ! -f "$exported" ]; then
    distrobox-export --app "$cmdname" >/dev/null || { echo "workstation-apps: distrobox-export --app $cmdname failed" >&2; return 1; }
    [ -f "$exported" ] || { echo "workstation-apps: distrobox-export wrote no $exported" >&2; return 1; }
  fi
  # Each app rewrites its link default to <desktop>.desktop on every start. A hidden alias with that
  # name opens the box's copy, unless another install already owns the name (then it wins for now).
  default="$box-$desktop.desktop"
  if [ ! -e "$alias" ] || grep -q '^X-Dotfiles-Alias-Of=' "$alias"; then
    { sed '/^NoDisplay=/d; /^X-Dotfiles-Alias-Of=/d' "$exported" | awk -v of="$box-$desktop.desktop" '
        { print } /^\[Desktop Entry\]/ && !done { print "NoDisplay=true"; print "X-Dotfiles-Alias-Of=" of; done = 1 }'; } > "$alias.tmp" &&
      mv "$alias.tmp" "$alias"
    default="$desktop.desktop"
  else
    echo "workstation-apps: $alias belongs to another install; $scheme:// links may open it until it is removed" >&2
  fi
  [ -z "$scheme" ] || on_host xdg-mime default "$default" "x-scheme-handler/$scheme" || true
  # distrobox-export's own refresh can fail silently; refresh the host's link-handler index here.
  on_host update-desktop-database "$apps" || true
  for s in $web; do
    [ -n "${s#*=}" ] || continue
    [ "$(on_host xdg-mime query default "x-scheme-handler/${s%%=*}" 2>/dev/null || true)" = "${s#*=}" ] ||
      on_host xdg-mime default "${s#*=}" "x-scheme-handler/${s%%=*}" || true
  done
  refresh_icon_cache
}

# installer: a vendor's official Linux installer into ~/.local (shared with the box), when missing.
installer_installed() { [ -x "$HOME/.local/bin/$1" ] || command -v "$1" >/dev/null 2>&1; }
run_installer() { # <url>
  local tmp rc
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/install.sh" "$1" && sh "$tmp/install.sh"
  rc=$?; rm -rf "$tmp"; return "$rc"
}

resolve() { # <path> : follow symlinks with plain readlink (no -f on older macOS)
  local p="$1" l d n=0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    l="$(readlink "$p")"
    case "$l" in /*) p="$l" ;; *) p="$(dirname "$p")/$l" ;; esac
    n=$((n + 1))
  done
  if d="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd)"; then p="$d/${p##*/}"; fi
  printf '%s\n' "$p"
}
copies() { # <id> : vendor copies of its Homebrew-routed app, as kind<TAB>path<TAB>extra lines
  local kind name extra p seen=""
  fields "$1"
  case "$method" in formula|cask) ;; *) return 0 ;; esac
  IFS=: read -r kind name extra <<<"$vendor"
  case "$kind" in
    bin)
      for p in $(type -a -p "$name" 2>/dev/null) "$HOME/.local/bin/$name"; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        case " $seen " in *" $p "*) continue ;; esac
        seen="$seen $p"
        under_brew "$p" && continue
        printf 'bin\t%s\t%s\n' "$p" "$extra"
      done ;;
    app)
      [ "$os" = darwin ] && [ -d "$apps_dir/$name" ] || return 0
      brew_installed "$method" "$package" && return 0
      printf 'app\t%s\t\n' "$apps_dir/$name" ;;
  esac
}
npm_package() { # <resolved path> : the global npm package that owns it, if any
  local rest="${1##*/node_modules/}" first
  [ "$rest" != "$1" ] || return 0
  first="${rest%%/*}"
  case "$first" in @*) rest="${rest#*/}"; printf '%s/%s\n' "$first" "${rest%%/*}" ;; *) printf '%s\n' "$first" ;; esac
}
owner() { # <path> : sets pkg and npm_prefix; npm_prefix only for an npm global (<prefix>/lib/node_modules)
  local real
  real="$(resolve "$1")"; pkg="$(npm_package "$real")"; npm_prefix=""
  case "$real" in */lib/node_modules/*) npm_prefix="${real%%/lib/node_modules/*}" ;; esac
}
describe() { # kind path extra : one readable line for a vendor copy
  local pkg npm_prefix
  case "$1" in
    app) echo "$2 (app bundle Homebrew doesn't manage)" ;;
    bin)
      owner "$2"
      if [ -n "$npm_prefix" ]; then echo "$2 (global npm package $pkg)"
      elif [ -n "$pkg" ]; then echo "$2 (global package $pkg from another package manager, such as bun or yarn)"
      else echo "$2 (vendor installer)"; fi ;;
  esac
}

saved=false
if [ "${1:-}" = --saved ]; then saved=true; shift; fi
case "$cmd" in apply|drift) saved=true ;; esac
picked=()
check_ids() { # validate before anything installs; with --saved, retired IDs warn and are skipped
  local id
  for id in "$@"; do
    if known "$id"; then picked+=("$id"); continue; fi
    $saved || { echo "workstation-apps: unknown app: $id (try workstation-apps list)" >&2; exit 2; }
    [ "$cmd" = drift ] && continue
    echo "workstation-apps: $id is no longer in the catalog; skipped. Remove it from the selection with: workstation-apps disable $id" >&2
  done
}

said=""
say() { # <id> <status> : apply prints one line per status, and nothing for an app already installed
  if [ "$cmd" = apply ]; then
    case "$2" in installed*) ;; *) echo "workstation-apps: $1: $2" ;; esac
    return 0
  fi
  if [ "$said" != "$1" ]; then
    local pkg="${package#-}"
    said="$1"
    printf '%s [%s/%s]: %s%s%s — %s\n  %s\n' "$1" "$os" "$arch" "${method:-none}" "${pkg:+ $pkg}" "$(tag)" "$note" "$source"
  fi
  printf '  %s\n' "$2"
}
install_one() { # <id> : 0 installed or present, 3 left for you, 1 failed
  local id="$1" c p x found=""
  fields "$id"
  case "$method" in
    manual) say "$id" "manual: not automated here"; return 3 ;;
    formula|cask)
      if ! brew_here; then
        say "$id" "skipped: installTarget is distrobox and this is the host; Homebrew apps install in the box"; return 3
      fi
      command -v brew >/dev/null 2>&1 || { say "$id" "skipped: Homebrew not found"; return 3; }
      if brew_installed "$method" "$package"; then say "$id" "installed (Homebrew)"; return 0; fi
      found="$(copies "$id")"
      if [ -n "$found" ]; then
        while IFS=$'\t' read -r c p x; do say "$id" "found $(describe "$c" "$p" "$x")"; done <<<"$found"
        say "$id" "skipped so there is one copy: workstation-apps vendor remove $id, then install again"
        return 3
      fi
      [ "$cmd" != preview ] || { say "$id" "not installed"; return 0; }
      [ "$cmd" != apply ] || echo "workstation-apps: $id: brew install --$method $package"
      brew install "--$method" "$package" || { say "$id" "failed: brew install --$method $package" >&2; return 1; }
      [ "$cmd" = apply ] || say "$id" "installed (Homebrew)" ;;
    apt)
      local why; why="$(apt_skip)"
      [ -z "$why" ] || { say "$id" "skipped: $why"; return 3; }
      if apt_installed "$package"; then
        [ "$cmd" = preview ] || export_app || { say "$id" "failed: exporting $package to the host menu" >&2; return 1; }
        say "$id" "installed (apt)"; return 0
      fi
      [ "$cmd" != preview ] || { say "$id" "not installed (apt$($in_box && echo ' in the box, exported to the host menu'))"; return 0; }
      [ "$cmd" != apply ] || echo "workstation-apps: $id: apt install $package"
      apt_recipe "$package" || { say "$id" "failed: apt install $package" >&2; return 1; }
      export_app || { say "$id" "failed: exporting $package to the host menu" >&2; return 1; }
      [ "$cmd" = apply ] || say "$id" "installed (apt)" ;;
    installer)
      [ "$os" = linux ] || { say "$id" "skipped: the installer route is Linux only"; return 3; }
      if installer_installed "$package"; then say "$id" "installed (vendor installer; it updates itself)"; return 0; fi
      [ "$cmd" != preview ] || { say "$id" "not installed (runs ${vendor#installer:})"; return 0; }
      echo "workstation-apps: $id: running the vendor's installer ${vendor#installer:}"
      run_installer "${vendor#installer:}" || { say "$id" "failed: ${vendor#installer:}" >&2; return 1; }
      refresh_icon_cache
      installer_installed "$package" || { say "$id" "failed: the installer left no $package" >&2; return 1; }
      [ "$cmd" = apply ] || say "$id" "installed (vendor installer; it updates itself)" ;;
    "") say "$id" "no route for $os/$arch"; return 3 ;;
    *) say "$id" "unknown method in the catalog: $method" >&2; return 1 ;;
  esac
}

run_installs() {
  local id rc pending=0 failed=0
  [ "${#picked[@]}" -gt 0 ] || { echo "workstation-apps: none selected"; return 0; }
  for id in "${picked[@]}"; do
    rc=0; install_one "$id" || rc=$?
    case "$rc" in 0) ;; 3) pending=1 ;; *) failed=1 ;; esac
  done
  [ "$pending" -eq 0 ] || [ "$cmd" = apply ] || echo "workstation-apps: some apps are left for you (above); see docs/workstation-apps.md."
  [ "$failed" -eq 0 ] || return 1
  [ "$pending" -eq 0 ] || [ "$cmd" != install ] || return 3
  return 0
}

drift() { # selected IDs : what differs from the selection, for apps routed on this machine
  local id x
  for id in "$@"; do
    known "$id" || printf 'app-retired\t%s\t%s\n' "$id" "workstation-apps disable $id"
  done
  for id in $(ids); do
    fields "$id"
    local on=false have=false
    for x in "$@"; do [ "$x" != "$id" ] || on=true; done
    case "$method" in
      formula|cask)
        if ! brew_here || ! command -v brew >/dev/null 2>&1; then continue; fi
        ! brew_installed "$method" "$package" || have=true ;;
      apt)
        [ -z "$(apt_skip)" ] || continue
        ! apt_installed "$package" || have=true ;;
      installer)
        [ "$os" = linux ] || continue
        ! installer_installed "$package" || have=true ;;
      *) continue ;;
    esac
    if $on && ! $have; then printf 'app-missing\t%s\t%s\n' "$id" "workstation-apps install $id"; fi
    if ! $on && $have; then printf 'app-unselected\t%s\t%s\n' "$id" "workstation-apps enable $id (or /codify)"; fi
    copies "$id" | while IFS=$'\t' read -r _ p _; do
      if $on; then printf 'app-vendor\t%s %s\t%s\n' "$id" "$p" "workstation-apps vendor remove $id"
      else printf 'app-unselected-vendor\t%s %s\t%s\n' "$id" "$p" "workstation-apps enable $id, then workstation-apps vendor remove $id"; fi
    done
  done
}

vendor_list() {
  local id any=false c p x
  for id in "$@"; do
    while IFS=$'\t' read -r c p x; do
      [ -n "$c" ] || continue
      any=true; echo "$id: $(describe "$c" "$p" "$x")"
    done <<<"$(copies "$id")"
  done
  if $any; then echo "Homebrew can own these after: workstation-apps vendor remove <app>..."; else echo "workstation-apps: no copies outside Homebrew found"; fi
}

vendor_remove() { # confirmed, never automatic; settings, sign-ins and app data are kept
  local id c p x pkg npm_prefix plan=() kept=() reply i
  [ "$#" -gt 0 ] || { echo "workstation-apps: name the apps: workstation-apps vendor remove <app>..." >&2; exit 2; }
  for id in "$@"; do
    while IFS=$'\t' read -r c p x; do
      [ -n "$c" ] || continue
      case "$c" in
        app) plan+=("trash|$p") ;;
        bin)
          owner "$p"
          if [ -n "$npm_prefix" ]; then plan+=("npm|$npm_prefix|$pkg")
          elif [ -n "$pkg" ]; then kept+=("$p (global package $pkg): uninstall it with the package manager that installed it")
          else
            plan+=("rm|$p")
            # shellcheck disable=SC2088 # the catalog writes ~ literally; expanded here only
            case "$x" in "~/"?*) [ ! -e "$HOME/${x#\~/}" ] || plan+=("rmdir|$HOME/${x#\~/}") ;; esac
          fi ;;
      esac
    done <<<"$(copies "$id")"
  done
  if [ "${#kept[@]}" -gt 0 ]; then
    echo "workstation-apps: not removed here:"
    for i in "${kept[@]}"; do echo "  $i"; done
  fi
  if [ "${#plan[@]}" -eq 0 ]; then
    [ "${#kept[@]}" -eq 0 ] || return 1
    echo "workstation-apps: no copies outside Homebrew found for: $*"; return 0
  fi
  echo "workstation-apps: this removes (settings, sign-ins and app data stay):"
  for i in "${plan[@]}"; do
    case "${i%%|*}" in
      trash) echo "  move ${i#*|} to ~/.Trash" ;;
      npm) x="${i#*|}"; echo "  npm uninstall -g --prefix ${x%%|*} ${x#*|}" ;;
      rm) echo "  rm ${i#*|}" ;;
      rmdir) echo "  rm -r ${i#*|} (the installer's versions)" ;;
    esac
  done
  printf 'Remove them? [y/N] '
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) ;; *) echo "workstation-apps: nothing removed"; return 1 ;; esac
  for i in "${plan[@]}"; do
    case "${i%%|*}" in
      trash) mkdir -p "$HOME/.Trash"; mv "${i#*|}" "$HOME/.Trash/" ;;
      npm) x="${i#*|}"; npm uninstall -g --prefix "${x%%|*}" "${x#*|}" ;;
      rm) rm -f "${i#*|}" ;;
      rmdir) rm -rf "${i#*|}" ;;
    esac
  done
  [ "${#kept[@]}" -eq 0 ] || { echo "workstation-apps: removed the rest; uninstall the copies above, then: workstation-apps install $*"; return 1; }
  echo "workstation-apps: removed. Next: workstation-apps install $*"
}
warm() { # fill the Homebrew caches here, not in the subshells that call copies
  brew_here && command -v brew >/dev/null 2>&1 || return 0
  under_brew / || true
  brew_installed - - || true
}

case "$cmd" in
  ids) ids ;;
  routes) # id<TAB>method<TAB>package<TAB>label for this OS and arch
    for id in $(ids); do fields "$id"; printf '%s\t%s\t%s\t%s\n' "$id" "${method:-none}" "$package" "$label"; done ;;
  preview|install|apply)
    check_ids "$@"; warm
    run_installs || exit $? ;;
  drift)
    check_ids "$@"; warm
    drift "$@" ;;
  vendor)
    if [ "${1:-}" = remove ]; then
      shift; check_ids "$@"; warm; vendor_remove ${picked[@]+"${picked[@]}"}
    else
      # shellcheck disable=SC2046 # catalog IDs are [a-z0-9-]
      [ "$#" -gt 0 ] || set -- $(ids)
      check_ids "$@"; warm; vendor_list ${picked[@]+"${picked[@]}"}
    fi ;;
  *) echo "workstation-apps: use ids, routes, preview, install, apply, drift or vendor" >&2; exit 2 ;;
esac
