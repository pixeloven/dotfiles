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

# Optional tool sets from lib/toolsets.txt, only the ones chezmoi init's toolsets answer turns on
# (any OS); the brew-bundle script passes them as HOMEBREW_DOTFILES_TOOLSETS=kubernetes,voice, and
# `all` lists every set (bin/drift uses it). Unknown names are ignored. A cask:<name> entry is a cask,
# and an @darwin or @linux suffix keeps an entry to that OS. docker is the CLI only; RUNBOOK section
# 9a has the podman-socket option for a distrobox. terraform comes from HashiCorp's tap (not in
# homebrew-core: BUSL licence). voice is VoiceInk (macOS push-to-talk), ffmpeg (the alerts' lead-in
# silence) and, on Linux, paplay/parecord (pulseaudio) and whisper.cpp for spoken alerts and
# `dictate` (RUNBOOK sections 4 and 5).
wanted = ENV.fetch("HOMEBREW_DOTFILES_TOOLSETS", "").split(",")
os = OS.mac? ? "darwin" : "linux"
picked = File.readlines(File.join(__dir__, "lib/toolsets.txt")).filter_map do |line|
  set, *entries = line.sub(/#.*/, "").split
  entries if set && (wanted.include?("all") || wanted.include?(set))
end.flatten.filter_map do |entry|
  name, only = entry.match(/\A(.+)@(darwin|linux)\z/)&.captures || [entry, nil]
  name unless only && only != os
end
casks, formulae = picked.partition { |e| e.start_with?("cask:") }
formulae.filter_map { |f| f.split("/")[0, 2].join("/") if f.count("/") == 2 }.uniq.each { |t| tap t }
formulae.each { |f| brew f }
casks.each { |c| cask c.delete_prefix("cask:") }
