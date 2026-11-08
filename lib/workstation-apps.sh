#!/usr/bin/env bash
# Workstation app planner/installer. Only Homebrew-backed entries are automated.
# Usage: workstation-apps.sh list | plan [app...] | install [app...]
# DOTFILES_APPS_OS/ARCH/CONTAINER_MARKER are test seams. Never execute plan output as shell code.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
table="$repo/lib/workstation-apps.tsv"
cmd="${1:-plan}"
[ "$#" -eq 0 ] || shift
os="${DOTFILES_APPS_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
arch="${DOTFILES_APPS_ARCH:-$(uname -m)}"
case "$arch" in aarch64) arch=arm64 ;; esac
case "$os" in darwin|linux) ;; *) echo "workstation-apps: unsupported OS: $os" >&2; exit 2 ;; esac
ids() { awk -F '|' '!/^#/ && NF && !seen[$1]++ {print $1}' "$table"; }
row() {
  awk -F '|' -v id="$1" -v os="$os" -v arch="$arch" '
    $1 == id {
      if ($2 == "all") base=$0
      if ($2 == os) platform=$0
      if ($2 == os "-" arch) exact=$0
    }
    END { if (exact) print exact; else if (platform) print platform; else if (base) print base }
  ' "$table"
}
if [ "$cmd" = list ]; then ids; exit 0; fi
case "$cmd" in plan|install) ;; *) echo "workstation-apps: use list, plan or install" >&2; exit 2 ;; esac
# Validate every ID before running any installation.
for id in "$@"; do
  ids | grep -qxF "$id" || { echo "workstation-apps: unknown app: $id" >&2; exit 2; }
done
[ "$#" -gt 0 ] || { echo "workstation-apps: none selected"; exit 0; }
if [ "$cmd" = install ]; then
  target="${DOTFILES_APPS_INSTALL_TARGET:-host}"
  case "$target" in
    host) ;;
    distrobox)
      [ -e "${DOTFILES_APPS_CONTAINER_MARKER:-/run/.containerenv}" ] || {
        echo "workstation-apps: installTarget=distrobox; run inside the box, not on its host" >&2
        exit 2
      } ;;
    *) echo "workstation-apps: invalid installTarget: $target" >&2; exit 2 ;;
  esac
fi
pending=0
for id in "$@"; do
  record="$(row "$id")"
  if [ -z "$record" ]; then
    echo "$id: no catalog entry for $os/$arch" >&2; pending=1; continue
  fi
  IFS='|' read -r _ _platform method package source note <<<"$record"
  printf '%s [%s/%s]: %s %s — %s\n  %s\n' "$id" "$os" "$arch" "$method" "$package" "$note" "$source"
  if [ "$method" = manual ]; then pending=1; continue; fi
  if [ "$cmd" = install ]; then
    command -v brew >/dev/null 2>&1 || { echo "workstation-apps: Homebrew is required" >&2; exit 1; }
    # Type is explicit: Codex and Claude Code are casks even on Linux.
    if brew list "--$method" "$package" >/dev/null 2>&1; then
      echo "  already installed via Homebrew; no upgrade"
    else
      brew install "--$method" "$package"
    fi
  fi
done
if [ "$pending" -eq 1 ]; then
  echo "workstation-apps: manual items remain; see docs/workstation-apps.md. No vendor scripts were run."
  [ "$cmd" = plan ] || exit 3
fi
