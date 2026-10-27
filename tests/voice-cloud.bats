#!/usr/bin/env bats
# The opt-in cloud voice engine. curl and every key store are stubs: no network, no real keys.

SCRIPT="$BATS_TEST_DIRNAME/../home/dot_local/bin/executable_voice-cloud"

setup() {
  export HOME="$(mktemp -d)"
  unset VOICE_CLOUD_URL VOICE_CLOUD_KEY VOICE_CLOUD_OP_REF VOICE_CLOUD_TTS_MODEL VOICE_CLOUD_STT_MODEL
  mkdir -p "$HOME/bin"
  # curl logs its arguments and any config it reads on stdin (-K -), writes -o files, prints a transcript.
  cat > "$HOME/bin/curl" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$HOME/curl-args"
out=""; prev=""
for a; do
  [ "\$prev" = -K ] && [ "\$a" = - ] && cat > "$HOME/curl-config"
  [ "\$prev" = -o ] && out="\$a"
  prev="\$a"
done
if [ -n "\$out" ]; then printf 'RIFF' > "\$out"; else echo " hello world "; fi
STUB
  # Key stores that hold nothing unless a test fills them.
  for s in security secret-tool op; do
    printf '#!/bin/sh\necho "$*" >> "%s/%s-calls"\n[ -f "%s/%s-key" ] && cat "%s/%s-key" || exit 1\n' \
      "$HOME" "$s" "$HOME" "$s" "$HOME" "$s" > "$HOME/bin/$s"
  done
  chmod +x "$HOME/bin/"*
  export PATH="$HOME/bin:$PATH"
}

teardown() { rm -rf "$HOME"; }

@test "refuses to run without VOICE_CLOUD_URL, and never calls curl" {
  run "$SCRIPT" tts "Hello." "$HOME/out.wav"
  [ "$status" -eq 2 ]
  [[ "$output" == *"VOICE_CLOUD_URL"* ]] || false
  [ ! -e "$HOME/curl-args" ]
}

@test "refuses a base URL that is not http(s)" {
  VOICE_CLOUD_URL=file:///etc run "$SCRIPT" tts "Hello." "$HOME/out.wav"
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/curl-args" ]
}

@test "tts posts to <base>/audio/speech at any server, trailing slash or not" {
  VOICE_CLOUD_URL=http://localhost:8880/v1/ run "$SCRIPT" tts --voice af_heart --speed 0.8 "All done." "$HOME/out.wav"
  [ "$status" -eq 0 ]
  [ -s "$HOME/out.wav" ]
  [ "$(tail -1 "$HOME/curl-args")" = "http://localhost:8880/v1/audio/speech" ]
  body="$(grep '^{' "$HOME/curl-args")"
  [ "$(jq -r .input <<<"$body")" = "All done." ]
  [ "$(jq -r .voice <<<"$body")" = "af_heart" ]
  [ "$(jq -r .model <<<"$body")" = "tts-1" ]
  [ "$(jq -r .response_format <<<"$body")" = "wav" ]
  [ "$(jq -r .speed <<<"$body")" = "0.8" ]
}

@test "the model names are configurable" {
  VOICE_CLOUD_URL=https://speech.example.test/v1 VOICE_CLOUD_TTS_MODEL=kokoro run "$SCRIPT" tts "Hi." "$HOME/out.wav"
  [ "$(jq -r .model <<<"$(grep '^{' "$HOME/curl-args")")" = "kokoro" ]
}

@test "with no key anywhere it sends no Authorization header (self-hosted)" {
  VOICE_CLOUD_URL=http://localhost:8880/v1 run "$SCRIPT" tts "Hi." "$HOME/out.wav"
  [ "$status" -eq 0 ]
  ! grep -q -- '-K' "$HOME/curl-args"
  [ ! -e "$HOME/curl-config" ]
  ! grep -qi 'authorization' "$HOME/curl-args"
  [ ! -e "$HOME/op-calls" ]
}

@test "a key from VOICE_CLOUD_KEY reaches curl on stdin, never in its arguments" {
  VOICE_CLOUD_URL=http://localhost:8880/v1 VOICE_CLOUD_KEY=sk-test-123 run "$SCRIPT" tts "Hi." "$HOME/out.wav"
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer sk-test-123' "$HOME/curl-config"
  ! grep -q 'sk-test-123' "$HOME/curl-args"
  [ ! -e "$HOME/security-calls" ]
}

@test "key lookup order: env, then Keychain, then secret-tool, then op" {
  export VOICE_CLOUD_URL=http://localhost:8880/v1 VOICE_CLOUD_OP_REF="op://Private/voice/credential"
  echo op-key > "$HOME/op-key"
  run "$SCRIPT" key-source
  [ "$output" = "op" ]
  echo st-key > "$HOME/secret-tool-key"
  run "$SCRIPT" key-source
  [ "$output" = "secret-tool" ]
  grep -q 'lookup service dotfiles-voice' "$HOME/secret-tool-calls"
  echo kc-key > "$HOME/security-key"
  run "$SCRIPT" key-source
  [ "$output" = "keychain" ]
  grep -q 'find-generic-password -s dotfiles-voice -w' "$HOME/security-calls"
  VOICE_CLOUD_KEY=env-key run "$SCRIPT" key-source
  [ "$output" = "env" ]
  [[ "$output" != *key* ]] || false
}

@test "op is asked only when VOICE_CLOUD_OP_REF names an item" {
  echo op-key > "$HOME/op-key"
  run "$SCRIPT" key-source
  [ "$output" = "none" ]
  [ ! -e "$HOME/op-calls" ]
}

@test "the secret-tool key is the one sent" {
  echo st-key > "$HOME/secret-tool-key"
  VOICE_CLOUD_URL=http://localhost:8880/v1 run "$SCRIPT" tts "Hi." "$HOME/out.wav"
  grep -q 'Authorization: Bearer st-key' "$HOME/curl-config"
}

@test "stt posts the recording to <base>/audio/transcriptions and prints the text" {
  : > "$HOME/take.wav"
  VOICE_CLOUD_URL=http://localhost:8000/v1 run "$SCRIPT" stt --prompt "herdr, chezmoi" "$HOME/take.wav"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
  [ "$(tail -1 "$HOME/curl-args")" = "http://localhost:8000/v1/audio/transcriptions" ]
  grep -qx "file=@$HOME/take.wav" "$HOME/curl-args"
  grep -qx 'model=whisper-1' "$HOME/curl-args"
  grep -qx 'prompt=herdr, chezmoi' "$HOME/curl-args"
}

@test "rejects unknown commands" {
  run "$SCRIPT" bogus
  [ "$status" -eq 2 ]
}
