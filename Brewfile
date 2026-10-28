# Apps
if OS.mac?
  cask "ghostty"
  # Global push-to-talk dictation, on-device (RUNBOOK section 4)
  cask "voiceink"
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

# Linux only: voice. paplay/parecord reach the desktop's PipeWire (also from a distrobox) for spoken
# alerts and `dictate`; whisper.cpp is dictate's local speech to text (RUNBOOK sections 4 and 5).
if OS.linux?
  brew "pulseaudio"
  brew "whisper.cpp"
end

# Ops tool sets from lib/toolsets.txt, only the ones chezmoi init's toolsets answer turns on (any
# OS); the brew-bundle script passes them as HOMEBREW_DOTFILES_TOOLSETS=kubernetes,terraform, and
# `all` lists every set (bin/drift uses it). Unknown names are ignored. docker is the CLI only;
# RUNBOOK section 9a has the podman-socket option for a distrobox. terraform comes from HashiCorp's
# tap (not in homebrew-core: BUSL licence).
wanted = ENV.fetch("HOMEBREW_DOTFILES_TOOLSETS", "").split(",")
picked = File.readlines(File.join(__dir__, "lib/toolsets.txt")).filter_map do |line|
  set, *formulae = line.sub(/#.*/, "").split
  formulae if set && (wanted.include?("all") || wanted.include?(set))
end.flatten
picked.filter_map { |f| f.split("/")[0, 2].join("/") if f.count("/") == 2 }.uniq.each { |t| tap t }
picked.each { |f| brew f }
