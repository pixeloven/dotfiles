# 1Password service account for this shell — managed by chezmoi. Sourced by dotfiles.zsh. Holds no
# secret: the token lives only in ~/.config/harmony/op-sa-token (mode 0600, placed by hand, never
# committed; RUNBOOK section 11). Without that file, or with it empty, this does nothing. With it,
# it exports OP_SERVICE_ACCOUNT_TOKEN, then, when op is installed and LITELLM_API_KEY is not
# already set, LITELLM_API_KEY from `op read`. An `op read` that fails or takes longer than the
# timeout leaves it unset. xtrace is off inside, so `set -x` never prints a value.
# DOTFILES_OP_TOKEN_FILE is a test seam.
_dotfiles_op_env() {
  setopt local_options no_xtrace
  local file=${DOTFILES_OP_TOKEN_FILE:-$HOME/.config/harmony/op-sa-token} mode value
  [[ -f $file && -r $file && -s $file ]] || return 0
  mode=$(stat -c %a -- "$file" 2>/dev/null || stat -f %Lp -- "$file" 2>/dev/null)
  [[ $mode == 600 ]] || print -ru2 -- "dotfiles: $file is mode ${mode:-unknown}, not 600; run: chmod 600 $file"
  export OP_SERVICE_ACCOUNT_TOKEN="$(<$file)"
  (( $+commands[op] )) && [[ -z ${LITELLM_API_KEY:-} ]] || return 0
  value=$(_dotfiles_op_read 'op://Harmony/LiteLLM/workstation_key') && [[ -n $value ]] && export LITELLM_API_KEY=$value
}

# op read <ref>, killed after DOTFILES_OP_READ_TIMEOUT seconds (default 3) so a slow or offline
# 1Password never holds up the prompt. Portable: macOS has no timeout(1).
_dotfiles_op_read() {
  op read --no-newline -- "$1" </dev/null 2>/dev/null &
  local pid=$!
  ( trap 'kill $s' TERM; sleep ${DOTFILES_OP_READ_TIMEOUT:-3} & s=$!; wait $s && kill $pid ) >/dev/null 2>&1 &
  local timer=$!
  wait $pid
  local rc=$?
  kill $timer 2>/dev/null
  return $rc
}

_dotfiles_op_env
unfunction _dotfiles_op_env _dotfiles_op_read
