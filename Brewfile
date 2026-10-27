# Apps
if OS.mac?
  cask "ghostty"
end
cask "font-jetbrains-mono"
cask "font-jetbrains-mono-nerd-font"
cask "1password-cli"

# CLI
brew "chezmoi"
brew "bat"
brew "git-delta"
brew "glow"
brew "jq"
brew "gh"
brew "tmux"
brew "uv"
brew "node"
brew "awscli"
brew "ffmpeg"

# Shell (zsh): prompt, suggestions, search, completion menu, smart cd, ls, Node
brew "starship"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf"
brew "fzf-tab"
brew "fd"
brew "zoxide"
brew "eza"
brew "fnm"

# Dev tooling for this repo
brew "bats-core"
brew "shellcheck"
brew "gitleaks"

# Linux only: clipboard helpers for herdr when the terminal ignores OSC 52 (Ptyxis/VTE)
if OS.linux?
  brew "wl-clipboard"
  brew "xclip"
end

# Ops tools, on any Linux that is not an image-based host (/run/ostree-booted): the distrobox, or a
# plain Linux dev machine. Never on the image host, and not on the Mac. docker is the CLI only;
# RUNBOOK section 9 has the podman-socket option. terraform comes from HashiCorp's tap (not in
# homebrew-core: BUSL licence).
if OS.linux? && !File.exist?("/run/ostree-booted")
  tap "hashicorp/tap"
  tap "siderolabs/tap"
  brew "kubernetes-cli"
  brew "helm"
  brew "argocd"
  brew "siderolabs/tap/talosctl"
  brew "siderolabs/tap/omnictl"
  brew "hashicorp/tap/terraform"
  brew "ansible"
  brew "docker"
end
