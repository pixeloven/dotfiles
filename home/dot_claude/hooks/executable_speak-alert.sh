#!/usr/bin/env bash
# Claude Code and Codex hook: speak a short line when an agent stops or needs attention.
# Usage: speak-alert.sh <stop|notify|codex-stop|codex-permission>   (hook JSON on stdin)
# stop and codex-stop say a calm done line; notify speaks Claude's own reason (the payload's
# "message"); codex-permission names the tool Codex wants to use.
# Codex: silent for headless `codex exec` runs, read from the session's transcript metadata.
# Voice: SPEAK_ALERT_VOICE, else the first installed English Premium voice, else the macOS system voice
# (System Settings > Accessibility > Read & Speak > System voice, which can be a Siri voice).
# Silent where no `say` is installed (Linux, for now), for fleet workers (FM_TASK_ID set), for headless `claude -p` runs such as review
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

case "${1:-}" in
  stop) phrase="All done. Ready for you." ;;
  notify)
    phrase="$(jq -r '.message // empty' 2>/dev/null)"
    phrase="${phrase:-Claude needs you}"
    case "$phrase" in *[.!?]) ;; *) phrase="$phrase." ;; esac
    ;;
  codex-stop|codex-permission)
    input="$(cat)"
    # Codex hooks don't say whether the session is headless; its transcript's first line does.
    transcript="$(jq -r '.transcript_path // empty' 2>/dev/null <<<"$input")"
    if [ -n "$transcript" ] && head -1 "$transcript" 2>/dev/null |
      jq -e '.payload.originator == "codex_exec" or .payload.source == "exec"' >/dev/null 2>&1; then
      note "silent: headless codex exec"
      exit 0
    fi
    if [ "$1" = codex-stop ]; then
      phrase="All done. Ready for you."
    else
      tool="$(jq -r '.tool_name // empty' 2>/dev/null <<<"$input")"
      phrase="Codex needs your permission${tool:+ to use $tool}."
    fi
    ;;
  *) exit 0 ;;
esac

if [ -n "${SPEAK_ALERT_DRY_RUN:-}" ] && [ "$SPEAK_ALERT_DRY_RUN" != voice ]; then
  note "spoke: $phrase"
  echo "$phrase"
  exit 0
fi

# Linux has no `say`; stay silent rather than log a line that was never spoken.
command -v say >/dev/null 2>&1 || { note "silent: no speech backend"; exit 0; }
note "spoke: $phrase"

voice="${SPEAK_ALERT_VOICE:-$(say -v '?' 2>/dev/null | sed -nE 's/^(.+ \(Premium\)) +en_.*/\1/p' | head -1)}"
voice_args=()
[ -n "$voice" ] && voice_args=(-v "$voice")

if [ "${SPEAK_ALERT_DRY_RUN:-}" = voice ]; then
  echo "${voice:-system}"
else
  # Lead with silence so the audio device is awake before the first word (avoids a clipped, "mic click" start).
  (say "${voice_args[@]}" -r "${SPEAK_ALERT_RATE:-120}" "[[slnc ${SPEAK_ALERT_LEAD_MS:-800}]] $phrase" > /dev/null 2>&1 &)
fi
exit 0
