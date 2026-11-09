#!/bin/sh
# Inside an nvidia=true distrobox, add the NVIDIA EGL and Vulkan manifests distrobox doesn't map, so
# native Wayland (EGL) and Vulkan apps render on the GPU instead of falling back to llvmpipe.
# distrobox maps the driver libraries but only some EGL manifests, and the Vulkan manifest it maps
# names the host's /usr/lib64 path, which an Ubuntu box doesn't have. So this copies every host
# NVIDIA EGL manifest the box lacks into /etc/egl/egl_external_platform.d, and writes
# /etc/vulkan/icd.d/nvidia_box.json with the bare library name. It changes only those box-local
# files (the container's /etc, gone with a rebuild), never the host. Outside a box, or on a host
# without the NVIDIA driver, or a box made without nvidia=true, it does nothing.
# Test seams: DOTFILES_GPU_HOST_ROOT (default /run/host), DOTFILES_GPU_BOX_ROOT (default /),
# DOTFILES_GPU_CONTAINER_MARKER (default /run/.containerenv).
set -eu
host="${DOTFILES_GPU_HOST_ROOT:-/run/host}"
box="${DOTFILES_GPU_BOX_ROOT:-}"
[ -e "${DOTFILES_GPU_CONTAINER_MARKER:-/run/.containerenv}" ] || exit 0
egl_host="$host/usr/share/egl/egl_external_platform.d"
ls "$egl_host"/*nvidia*.json >/dev/null 2>&1 || exit 0
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "dotfiles: the host has the NVIDIA driver but this box has no GPU mapping; rebuild it with nvidia=true (RUNBOOK 9c)" >&2
  exit 0
fi

as_root() { if [ -w "$box/etc" ] || [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
put() { # <dest> <content file> : write it world-readable (0644) when its content or mode differs
  if [ -f "$1" ] && cmp -s "$1" "$2" && [ "$(stat -c %a "$1")" = 644 ]; then return 0; fi
  as_root mkdir -p "$(dirname "$1")"
  as_root install -m 0644 "$2" "$1"
  echo "dotfiles: wrote $1"
}

for f in "$egl_host"/*nvidia*.json; do
  name="${f##*/}"
  [ -e "$box/usr/share/egl/egl_external_platform.d/$name" ] && continue
  put "$box/etc/egl/egl_external_platform.d/$name" "$f"
done

icd=""
for f in "$host"/usr/share/vulkan/icd.d/nvidia_icd*.json "$host"/etc/vulkan/icd.d/nvidia_icd*.json; do
  [ -f "$f" ] && { icd="$f"; break; }
done
if [ -n "$icd" ]; then
  api="$(sed -n 's/.*"api_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$icd" | head -n 1)"
  tmp="$(mktemp)"
  printf '{ "file_format_version" : "1.0.1", "ICD": { "library_path": "libGLX_nvidia.so.0", "api_version" : "%s" } }\n' "${api:-1.3.0}" > "$tmp"
  put "$box/etc/vulkan/icd.d/nvidia_box.json" "$tmp"
  rm -f "$tmp"
fi
