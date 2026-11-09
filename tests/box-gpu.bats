#!/usr/bin/env bats
# lib/distrobox/nvidia-manifests.sh against a fake host (/run/host) and box root in a throwaway dir.
# Nothing here reads or writes the real /etc, the real host, or a real box.

SCRIPT="$BATS_TEST_DIRNAME/../lib/distrobox/nvidia-manifests.sh"

setup() {
  TMP="$(mktemp -d)"
  export DOTFILES_GPU_HOST_ROOT="$TMP/host" DOTFILES_GPU_BOX_ROOT="$TMP/box" DOTFILES_GPU_CONTAINER_MARKER="$TMP/containerenv"
  touch "$DOTFILES_GPU_CONTAINER_MARKER"
  E="usr/share/egl/egl_external_platform.d"
  mkdir -p "$TMP/host/$E" "$TMP/host/usr/share/vulkan/icd.d" "$TMP/box/$E" "$TMP/box/etc" "$TMP/bin"
  # The host has five NVIDIA EGL manifests; distrobox maps two of them into the box.
  for f in 09_nvidia_wayland2 10_nvidia_wayland 15_nvidia_gbm 20_nvidia_xcb 20_nvidia_xlib; do
    echo "{\"name\": \"$f\"}" > "$TMP/host/$E/$f.json"
  done
  cp "$TMP/host/$E/10_nvidia_wayland.json" "$TMP/host/$E/15_nvidia_gbm.json" "$TMP/box/$E/"
  printf '{\n  "file_format_version" : "1.0.1",\n  "ICD": {\n    "library_path": "/usr/lib64/libGLX_nvidia.so.0",\n    "api_version" : "1.4.351"\n  }\n}\n' \
    > "$TMP/host/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json"
  printf '#!/bin/sh\n' > "$TMP/bin/nvidia-smi"
  printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\nexec "$@"\n' "$TMP" > "$TMP/bin/sudo"
  chmod +x "$TMP/bin/"*
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "in an nvidia box it adds the EGL manifests distrobox misses and a Vulkan manifest by bare name" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  for f in 09_nvidia_wayland2 20_nvidia_xcb 20_nvidia_xlib; do
    cmp "$TMP/host/$E/$f.json" "$TMP/box/etc/egl/egl_external_platform.d/$f.json"
  done
  [ ! -e "$TMP/box/etc/egl/egl_external_platform.d/10_nvidia_wayland.json" ]
  grep -q '"library_path": "libGLX_nvidia.so.0"' "$TMP/box/etc/vulkan/icd.d/nvidia_box.json"
  grep -q '"api_version" : "1.4.351"' "$TMP/box/etc/vulkan/icd.d/nvidia_box.json"
}

@test "it is idempotent: a second run writes nothing" {
  "$SCRIPT"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "it does nothing outside a box, or on a host without the NVIDIA driver" {
  rm "$DOTFILES_GPU_CONTAINER_MARKER"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/box/etc/egl" ]
  touch "$DOTFILES_GPU_CONTAINER_MARKER"
  rm "$TMP/host/$E/"*
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TMP/box/etc/vulkan" ]
}

@test "a box made without nvidia=true is told to rebuild, and nothing is written" {
  rm "$TMP/bin/nvidia-smi"
  run env PATH="$TMP/bin:/usr/bin:/bin" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rebuild it with nvidia=true"* ]] || false
  [ ! -e "$TMP/box/etc/egl" ]
}

@test "the apply step runs it only on Bazzite (Linux with installTarget distrobox)" {
  render() { chezmoi --source "$BATS_TEST_DIRNAME/.." --config "$TMP/none.toml" execute-template --override-data "$1" \
    < "$BATS_TEST_DIRNAME/../home/.chezmoiscripts/run_after_45-box-gpu.sh.tmpl"; }
  [ -z "$(render '{"chezmoi":{"os":"darwin"},"installTarget":"distrobox"}')" ]
  [ -z "$(render '{"chezmoi":{"os":"linux"},"installTarget":"host"}')" ]
  [[ "$(render '{"chezmoi":{"os":"linux"},"installTarget":"distrobox"}')" == *'/lib/distrobox/nvidia-manifests.sh"'* ]] || false
}
