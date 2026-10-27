#!/usr/bin/env bats
# op-env.zsh: the 1Password service-account token and opEnv variables, sourced by dotfiles.zsh.
# A fake `op` on PATH logs each call and answers from the ref; the token is random each run.

REPO="$BATS_TEST_DIRNAME/.."
ZSH_DIR="$REPO/home/dot_config/zsh"

setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/home/.config" "$TMP/bin"
  cp -R "$ZSH_DIR" "$TMP/home/.config/zsh"
  TOKEN_FILE="$TMP/home/.config/harmony/op-sa-token"
  TOKEN="ops_$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 40)"
  cat > "$TMP/bin/op" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/op.log"
case "\$*" in
  *op://slow/*) exec sleep 30 ;; # one process, like the real op binary
  *op://fail/*) echo 'not found' >&2; exit 1 ;;
  *) printf 'value-of-%s' "\${4#op://}" ;;
esac
EOF
  chmod +x "$TMP/bin/op"
}
teardown() { rm -rf "$TMP"; }

token() { mkdir -p "${TOKEN_FILE%/*}"; printf '%s\n' "$TOKEN" > "$TOKEN_FILE"; chmod "${1:-600}" "$TOKEN_FILE"; }

render() { # <opEnv JSON> : render op-env.zsh beside dotfiles.zsh with that opEnv data
  chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template --override-data "{\"opEnv\":$1}" \
    < "$ZSH_DIR/op-env.zsh.tmpl" > "$TMP/home/.config/zsh/op-env.zsh"
}

# A zsh that sources dotfiles.zsh in the scratch HOME, then runs "$1". $PATH has the fake op.
in_zsh() {
  local zsh; zsh="$(command -v zsh)"
  env -u OP_SERVICE_ACCOUNT_TOKEN -u LITELLM_API_KEY -u OTHER_KEY HOME="$TMP/home" HOMEBREW_PREFIX="$TMP/no-brew" \
    DOTFILES_OSTREE_MARKER="$TMP/no-ostree" DOTFILES_CONTAINER_MARKER="$TMP/no-containerenv" \
    PATH="$TMP/bin:/usr/bin:/bin" "${@:2}" "$zsh" -f -c "source ~/.config/zsh/dotfiles.zsh; $1"
}

show='print -r -- "tok=${OP_SERVICE_ACCOUNT_TOKEN-unset} lite=${LITELLM_API_KEY-unset} other=${OTHER_KEY-unset} fn=$+functions[_dotfiles_op_env]"'

@test "op-env renders and parses with and without opEnv data" {
  for data in '{}' '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key"}'; do
    render "$data"
    run zsh -n "$TMP/home/.config/zsh/op-env.zsh"
    [ "$status" -eq 0 ] || { echo "$data: $output"; false; }
  done
  # no data: an empty refs table, so no op:// ref is wired in for anyone
  run chezmoi --source "$REPO" --config "$TMP/none.toml" execute-template < "$ZSH_DIR/op-env.zsh.tmpl"
  [[ "$output" == *$'local -A refs=(\n  )'* ]] || false
}

@test "opEnv rejects a bad variable name or ref" {
  run render '{"BAD-NAME":"op://a/b/c"}'
  [ "$status" -ne 0 ]
  run render '{"OK":"https://example.com"}'
  [ "$status" -ne 0 ]
  run render "{\"OK\":\"op://a/b'c\"}"
  [ "$status" -ne 0 ]
}

@test "no token file: nothing exported, nothing printed, op never runs" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key"}'
  run in_zsh "$show"
  [ "$status" -eq 0 ]
  [ "$output" = "tok=unset lite=unset other=unset fn=0" ]
  [ ! -e "$TMP/op.log" ]
}

@test "an empty token file is the same as none" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key"}'
  token; : > "$TOKEN_FILE"
  run in_zsh "$show"
  [ "$output" = "tok=unset lite=unset other=unset fn=0" ]
  [ ! -e "$TMP/op.log" ]
}

@test "token file: exports the token and each opEnv variable, silently" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key","OTHER_KEY":"op://v/i/f"}'
  token
  run in_zsh "$show"
  [ "$status" -eq 0 ]
  [ "$output" = "tok=$TOKEN lite=value-of-Harmony/LiteLLM/workstation_key other=value-of-v/i/f fn=0" ]
  grep -qx 'read --no-newline -- op://Harmony/LiteLLM/workstation_key' "$TMP/op.log"
}

@test "token file but no opEnv data: only the token, and op never runs" {
  render '{}'
  token
  run in_zsh "$show"
  [ "$output" = "tok=$TOKEN lite=unset other=unset fn=0" ]
  [ ! -e "$TMP/op.log" ]
}

@test "no op installed: only the token" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key"}'
  token
  rm "$TMP/bin/op"
  run in_zsh "$show"
  [ "$output" = "tok=$TOKEN lite=unset other=unset fn=0" ]
}

@test "a variable already set is kept and not read again" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key","OTHER_KEY":"op://v/i/f"}'
  token
  run in_zsh "export LITELLM_API_KEY=mine; source ~/.config/zsh/op-env.zsh; $show"
  [[ "$output" == *"lite=mine"* ]] || false
  [ "$(grep -c workstation_key "$TMP/op.log")" -eq 1 ] # only the first source, before it was set
}

@test "a failing op read leaves that variable unset and the shell starts" {
  render '{"LITELLM_API_KEY":"op://fail/x/y","OTHER_KEY":"op://v/i/f"}'
  token
  run in_zsh "$show; echo rc=\$?"
  [ "$output" = "tok=$TOKEN lite=unset other=value-of-v/i/f fn=0
rc=0" ]
}

@test "a hung op read is cut off at the timeout" {
  render '{"LITELLM_API_KEY":"op://slow/x/y"}'
  token
  local start=$SECONDS
  run in_zsh "$show" DOTFILES_OP_READ_TIMEOUT=1
  [ "$output" = "tok=$TOKEN lite=unset other=unset fn=0" ]
  (( SECONDS - start < 10 )) || { echo "took $((SECONDS - start))s"; false; }
}

@test "a token file not mode 600 warns once on stderr, without the token, and still loads" {
  render '{}'
  token 644
  run in_zsh "$show"
  [ "$(grep -c 'not 600' <<<"$output")" -eq 1 ]
  [[ "$output" == *"is mode 644, not 600; run: chmod 600 $TOKEN_FILE"* ]] || false
  [[ "$(grep 'not 600' <<<"$output")" != *"$TOKEN"* ]] || false
  [[ "$output" == *"tok=$TOKEN "* ]] || false
}

@test "mode 600 prints nothing" {
  render '{}'
  token
  run in_zsh 'true'
  [ -z "$output" ]
}

@test "set -x never prints the token or a value" {
  render '{"LITELLM_API_KEY":"op://Harmony/LiteLLM/workstation_key"}'
  token
  run in_zsh 'set -x; source ~/.config/zsh/op-env.zsh; set +x; print ok' LITELLM_API_KEY=
  [[ "$output" == *ok* ]] || false
  [[ "$output" != *"$TOKEN"* ]] || false
  [[ "$output" != *value-of-* ]] || false
}
