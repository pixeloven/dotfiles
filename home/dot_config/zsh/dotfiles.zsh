# zsh config — managed by chezmoi (~/Development/dotfiles). See CUSTOMIZE.md.
# Sourced from ~/.zshrc by the one line inside its "dotfiles" marker block; everything else in
# ~/.zshrc stays private. Load order matters: oh-my-zsh (runs compinit) → fzf-tab → fzf →
# zoxide → autosuggestions → syntax highlighting → starship. Each tool is skipped when absent.

[[ -o interactive ]] || return 0

_dotfiles_brew="${HOMEBREW_PREFIX:-/opt/homebrew}"
_dotfiles_dir="${${(%):-%x}:A:h}"

# oh-my-zsh, trimmed: no theme, no plugins, no auto-update. It runs compinit.
if [[ -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  export ZSH="$HOME/.oh-my-zsh"
  ZSH_THEME=""
  plugins=()
  zstyle ':omz:update' mode disabled
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit && compinit
fi

# History: large, shared between sessions, no duplicates; a leading space keeps a command out.
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=100000
SAVEHIST=100000
setopt extended_history share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_verify

# Completion: case-insensitive, coloured; fzf-tab draws the menu.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false

# fzf colours: Catppuccin Mocha (https://github.com/catppuccin/fzf). fd lists files and folders.
export FZF_DEFAULT_OPTS="\
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a,border:#6c7086,label:#cdd6f4"
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always --icons=auto {} 2>/dev/null'"

# fzf-tab: fuzzy Tab menu with previews, in the fzf colours above. Needs compinit first.
if [[ -r "$_dotfiles_brew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" ]] && (( $+commands[fzf] )); then
  source "$_dotfiles_brew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
  zstyle ':fzf-tab:*' use-fzf-default-opts yes
  zstyle ':fzf-tab:*' switch-group '<' '>'
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto $realpath'
  zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always --icons=auto $realpath'
fi

# fzf: Ctrl+R history, Ctrl+T files, Alt+C folders.
(( $+commands[fzf] )) && source <(fzf --zsh)

# zoxide: z <part of a path> jumps there, zi picks interactively.
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# fnm: Node versions, switching on cd when a folder has .node-version or .nvmrc.
(( $+commands[fnm] )) && eval "$(fnm env --use-on-cd --shell zsh)"

# eza: ls with icons (JetBrainsMono Nerd Font), git status and tree.
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias l='eza -l --git --icons=auto --group-directories-first'
  alias ll='eza -l --git --icons=auto --group-directories-first'
  alias la='eza -la --git --icons=auto --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto --git-ignore'
fi

# zsh-autosuggestions: grey ghost text from history, → accepts.
if [[ -r "$_dotfiles_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  source "$_dotfiles_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# zsh-syntax-highlighting with Catppuccin's theme; the theme goes first, the plugin last.
if [[ -r "$_dotfiles_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$_dotfiles_dir/catppuccin_mocha-zsh-syntax-highlighting.zsh"
  source "$_dotfiles_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Starship prompt (~/.config/starship.toml).
(( $+commands[starship] )) && eval "$(starship init zsh)"

unset _dotfiles_brew _dotfiles_dir
