#!/usr/bin/env bash
# Claude Code and Codex hook: speak a short line when an agent stops or needs attention.
# Usage: speak-alert.sh <stop|notify|summary|codex-stop|codex-permission|codex-summary>   (hook JSON on stdin)
# stop and codex-stop say a calm done line; notify speaks Claude's own reason (the payload's
# "message") for permission, idle and elicitation prompts only; codex-permission names the tool
# Codex wants to use.
# Summaries (opt-in, ~/.config/speak-alert/summaries exists): summary and codex-summary speak the
# project name and the first sentences of the reply instead of the done line. With
# SPEAK_ALERT_SUMMARIZER=claude, Haiku writes that sentence for Claude replies (claude-all: Codex too).
# Codex: silent for headless `codex exec` runs, read from the session's transcript metadata.
# Engine (SPEAK_ALERT_ENGINE): say on macOS, kokoro elsewhere (local Kokoro-82M via speak-kokoro,
# silent until its model is installed), openai-compatible (any OpenAI-style speech server, via
# voice-cloud), or none. Rendered alerts are cached in ~/.cache/speak-alert.
# Voice: SPEAK_ALERT_VOICE, else for say the first installed English Premium voice, else the macOS
# system voice (System Settings > Accessibility > Read & Speak > System voice, which can be a Siri
# voice); af_heart for kokoro; alloy for openai-compatible.
# Silent where the engine is missing, for fleet workers (FM_TASK_ID set), for headless `claude -p` runs such as review
# pipelines and helper agents (CLAUDE_CODE_ENTRYPOINT other than cli), and when
# ~/.config/speak-alert/muted exists.
# Each call adds one line to ~/.local/state/speak-alert/events.log saying what it decided.
# Always exits 0 so it can never block Claude Code or Codex.

note() { # <decision> : log one line, keeping the log short
  local log="$HOME/.local/state/speak-alert/events.log"
  mkdir -p "${log%/*}" 2>/dev/null || return 0
  printf '%s %s %s\n' "$(date '+%F %T')" "${mode:-?}" "$1" >> "$log" 2>/dev/null
  [ "$(wc -l < "$log" 2>/dev/null)" -gt 500 ] && tail -200 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  return 0
}

mode="${1:-}"
[ -n "${FM_TASK_ID:-}" ] && { note "silent: fleet worker"; exit 0; }
case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in cli) ;; *) note "silent: headless claude"; exit 0 ;; esac
[ -e "$HOME/.config/speak-alert/muted" ] && { note "silent: muted"; exit 0; }

done_line="All done. Ready for you."
summaries_on() { [ -e "$HOME/.config/speak-alert/summaries" ]; }

codex_headless() { # <hook json> : true for a headless `codex exec` session
  # Codex hooks don't say whether the session is headless; its transcript's first line does.
  local transcript
  transcript="$(jq -r '.transcript_path // empty' 2>/dev/null <<<"$1")"
  [ -n "$transcript" ] && head -1 "$transcript" 2>/dev/null |
    jq -e '.payload.originator == "codex_exec" or .payload.source == "exec"' >/dev/null 2>&1
}

# Level 0 summary: drop code blocks, headings, tables and rules, strip markdown marks, then keep
# the first one or two sentences, at most about 220 characters.
# shellcheck disable=SC2016  # a jq program, not shell expansions
HEURISTIC_JQ='
  (split("\n") | reduce .[] as $l ({fence: false, out: []};
      if ($l | test("^\\s*(```|~~~)")) then .fence |= not
      elif .fence then .
      else .out += [$l] end) | .out)
  | map(select(test("^\\s*(#|\\||(-{3,}|\\*{3,}|_{3,})\\s*$)") | not)
      | sub("^\\s*>\\s?"; "") | sub("^\\s*([-*+]|[0-9]+[.)])\\s+"; "")
      | gsub("!?\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; .t)
      | gsub("<?https?://[^\\s>]+>?"; "")
      | gsub("`|\\*\\*|__|\\*"; "")
      | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
      | select(length > 0)
      | if test("[.!?:;]$") then . else . + "." end)
  | join(" ")
  | [match("(.+?[.!?])(\\s+|$)"; "g") | .captures[0].string] as $s
  | ($s[0] // "") as $one
  | (if ($s | length) > 1 and (($one + " " + $s[1]) | length) <= 220 then $one + " " + $s[1] else $one end)
  | if length > 220 then .[0:220] | sub("\\s+\\S*$"; "") else . end'

with_timeout() { # <seconds> <stdin file> <command...> : run it, killed after that long
  local secs="$1" input="$2" pid watcher rc
  shift 2
  "$@" < "$input" &
  pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watcher=$!
  wait "$pid"
  rc=$?
  kill "$watcher" 2>/dev/null
  return "$rc"
}

summarize() { # <hook json> : the phrase to speak for this reply
  local input="$1" message text="" project tmp
  message="$(jq -r '.last_assistant_message // empty' 2>/dev/null <<<"$input")"
  project="$(jq -r '.cwd // empty' 2>/dev/null <<<"$input")"
  project="${project##*/}"
  [ -n "$message" ] || { echo "$done_line"; return; }
  # Level 1: Haiku on the Claude subscription, hooks off. Codex replies would go to Anthropic
  # too, so they need claude-all.
  case "${SPEAK_ALERT_SUMMARIZER:-}:$mode" in
    claude:summary|claude-all:summary|claude-all:codex-summary)
      if command -v claude >/dev/null 2>&1 && tmp="$(mktemp 2>/dev/null)"; then
        printf '%s' "$message" > "$tmp"
        # A failed call (signed out, timed out) prints its error, so only a clean exit counts.
        text="$(with_timeout "${SPEAK_ALERT_SUMMARY_TIMEOUT:-15}" "$tmp" env -u CLAUDECODE claude -p \
          --model haiku --no-session-persistence --settings '{"disableAllHooks":true}' \
          "Summarize the reply on stdin as one short spoken sentence of at most 25 words, for someone looking away from the screen. No code, paths, URLs or markdown. Reply with only that sentence." 2>/dev/null)" &&
          text="$(printf '%s' "$text" | tr '\n' ' ' | jq -rR 'gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:220]')" ||
          text=""
        rm -f "$tmp"
      fi
      ;;
  esac
  [ -n "$text" ] || text="$(jq -rn --arg m "$message" "\$m | $HEURISTIC_JQ" 2>/dev/null)"
  [ -n "$text" ] || { echo "$done_line"; return; }
  echo "${project:+$project. }$text"
}

pick_engine() { # sets engine, or fails when it can't speak on this machine
  engine="${SPEAK_ALERT_ENGINE:-}"
  if [ -z "$engine" ]; then
    case "$(uname -s 2>/dev/null)" in Darwin) engine=say ;; *) engine=kokoro ;; esac
  fi
  kokoro_model="${SPEAK_KOKORO_MODEL:-$HOME/.local/share/kokoro/kokoro-v1.0.onnx}"
  kokoro_voices="${SPEAK_KOKORO_VOICES:-$HOME/.local/share/kokoro/voices-v1.0.bin}"
  case "$engine" in
    say) command -v say >/dev/null 2>&1 ;;
    kokoro) [ -x "$HOME/.local/bin/speak-kokoro" ] && [ -f "$kokoro_model" ] && [ -f "$kokoro_voices" ] ;;
    openai-compatible) [ -x "$HOME/.local/bin/voice-cloud" ] && [ -n "${VOICE_CLOUD_URL:-}" ] ;;
    # A realtime or full-duplex engine would slot in here.
    *) false ;;
  esac
}

pick_player() { # sets player (a WAV player), or fails
  player=()
  if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
    command -v afplay >/dev/null 2>&1 && player=(afplay)
  elif command -v paplay >/dev/null 2>&1; then player=(paplay)
  fi
  [ ${#player[@]} -gt 0 ]
}

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

render() { # <wav> : render $phrase with $engine into this file, with the lead-in silence
  local wav="$1" raw="${1%.wav}.$$.raw.wav" part="${1%.wav}.$$.wav"
  mkdir -p "${wav%/*}" || return 1
  case "$engine" in
    kokoro)
      "$HOME/.local/bin/speak-kokoro" --model "$kokoro_model" --voices "$kokoro_voices" \
        --voice "$voice" --speed "$speed" --out "$raw" "$phrase" ;;
    openai-compatible)
      "$HOME/.local/bin/voice-cloud" tts --voice "$voice" --speed "$speed" "$phrase" "$raw" ;;
  esac >/dev/null 2>&1 || { rm -f "$raw"; return 1; }
  # Lead with silence so the audio device is awake before the first word (HDMI sinks clip it).
  if [ "$lead" -gt 0 ] 2>/dev/null && command -v ffmpeg >/dev/null 2>&1 &&
    ffmpeg -nostdin -loglevel error -y -i "$raw" -af "adelay=$lead:all=1" "$part" >/dev/null 2>&1; then
    rm -f "$raw"
  else
    mv "$raw" "$part"
  fi
  mv "$part" "$wav"
}

speak() { # <phrase> : say it with the chosen engine (or the dry run's stand-in)
  phrase="$1"
  # Dry runs, for tests: any value prints the phrase, except voice, engine, cache (the file a
  # rendered alert lives in) and play (renders, then prints the player instead of playing).
  case "${SPEAK_ALERT_DRY_RUN:-}" in
    ''|voice|engine|cache|play) ;;
    *) note "spoke: $phrase"; echo "$phrase"; return ;;
  esac

  # Stay silent rather than log a line that was never spoken.
  pick_engine || { note "silent: no speech backend"; return; }
  if [ "$engine" != say ]; then
    pick_player || { note "silent: no audio player"; return; }
  fi
  [ "${SPEAK_ALERT_DRY_RUN:-}" = engine ] && { echo "$engine"; return; }
  note "spoke: $phrase"

  rate="${SPEAK_ALERT_RATE:-120}"
  lead="${SPEAK_ALERT_LEAD_MS:-800}"
  case "$engine" in
    say) voice="${SPEAK_ALERT_VOICE:-$(say -v '?' 2>/dev/null | sed -nE 's/^(.+ \(Premium\)) +en_.*/\1/p' | head -1)}" ;;
    kokoro) voice="${SPEAK_ALERT_VOICE:-af_heart}" ;;
    *) voice="${SPEAK_ALERT_VOICE:-alloy}" ;;
  esac
  [ "${SPEAK_ALERT_DRY_RUN:-}" = voice ] && { echo "${voice:-system}"; return; }

  if [ "$engine" = say ]; then
    voice_args=()
    [ -n "$voice" ] && voice_args=(-v "$voice")
    [ -n "${SPEAK_ALERT_DRY_RUN:-}" ] && { echo "say ${voice_args[*]} -r $rate"; return; }
    (say "${voice_args[@]}" -r "$rate" "[[slnc $lead]] $phrase" > /dev/null 2>&1 &)
    return
  fi

  # Rendered engines: words per minute map to a speed where 150 is the voice's natural pace.
  speed="$(awk -v r="$rate" 'BEGIN { printf "%.2f", r / 150 }')"
  case "$engine" in
    kokoro) model="$kokoro_model" ;;
    *) model="${VOICE_CLOUD_URL%/} ${VOICE_CLOUD_TTS_MODEL:-tts-1}" ;;
  esac
  wav="$HOME/.cache/speak-alert/$(printf '%s' "$engine|$model|$voice|$rate|$lead|$phrase" | sha256).wav"
  [ "${SPEAK_ALERT_DRY_RUN:-}" = cache ] && { echo "$wav"; return; }
  # Alerts repeat, so they stay cached; a summary is played once and removed.
  keep=1
  case "$mode" in *summary) [ "$phrase" = "$done_line" ] || keep="" ;; esac
  if [ -n "${SPEAK_ALERT_DRY_RUN:-}" ]; then
    [ -s "$wav" ] || render "$wav" || { note "failed: $engine render"; return; }
    echo "${player[*]} $wav"
    return
  fi
  (
    { [ -s "$wav" ] || render "$wav"; } || { note "failed: $engine render"; exit 0; }
    "${player[@]}" "$wav"
    [ -n "$keep" ] || rm -f "$wav"
  ) > /dev/null 2>&1 < /dev/null &
}

case "$mode" in
  stop)
    summaries_on && { note "silent: summary instead"; exit 0; }
    phrase="$done_line"
    ;;
  notify)
    input="$(cat)"
    type="$(jq -r '.notification_type // empty' 2>/dev/null <<<"$input")"
    case "$type" in
      ''|permission_prompt|idle_prompt|elicitation_*|agent_needs_input) ;;
      *) note "silent: notification $type"; exit 0 ;;
    esac
    phrase="$(jq -r '.message // empty' 2>/dev/null <<<"$input")"
    phrase="${phrase:-Claude needs you}"
    case "$phrase" in *[.!?]) ;; *) phrase="$phrase." ;; esac
    ;;
  codex-stop|codex-permission)
    input="$(cat)"
    if codex_headless "$input"; then
      note "silent: headless codex exec"
      exit 0
    fi
    if [ "$mode" = codex-stop ]; then
      summaries_on && { note "silent: summary instead"; exit 0; }
      phrase="$done_line"
    else
      tool="$(jq -r '.tool_name // empty' 2>/dev/null <<<"$input")"
      phrase="Codex needs your permission${tool:+ to use $tool}."
    fi
    ;;
  summary|codex-summary)
    summaries_on || { note "silent: summaries off"; exit 0; }
    input="$(cat)"
    if [ "$mode" = codex-summary ] && codex_headless "$input"; then
      note "silent: headless codex exec"
      exit 0
    fi
    # Summarizing can take seconds (Haiku), so outside a dry run it all happens in the background.
    if [ -n "${SPEAK_ALERT_DRY_RUN:-}" ]; then
      speak "$(summarize "$input")"
    else
      (speak "$(summarize "$input")") > /dev/null 2>&1 < /dev/null &
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac

speak "$phrase"
exit 0
