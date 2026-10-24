#!/usr/bin/env bash
# Claude Code hook: speak a short line when an agent stops or needs attention.
# Usage: speak-alert.sh <stop|notify>   (hook JSON on stdin)
# stop says a calm done line; notify speaks Claude's own reason (the payload's "message").
# Voice: SPEAK_ALERT_VOICE, else the first installed English Premium voice, else the macOS system voice
# (System Settings > Accessibility > Read & Speak > System voice, which can be a Siri voice).
# Silent for fleet workers (FM_TASK_ID set), for headless `claude -p` runs such as review
# pipelines and helper agents (CLAUDE_CODE_ENTRYPOINT other than cli), and when
# ~/.config/speak-alert/muted exists.
# Always exits 0 so it can never block Claude Code.

[ -n "${FM_TASK_ID:-}" ] && exit 0
case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in cli) ;; *) exit 0 ;; esac
[ -e "$HOME/.config/speak-alert/muted" ] && exit 0

case "${1:-}" in
  stop) phrase="All done. Ready for you." ;;
  notify)
    phrase="$(jq -r '.message // empty' 2>/dev/null)"
    phrase="${phrase:-Claude needs you}"
    case "$phrase" in *[.!?]) ;; *) phrase="$phrase." ;; esac
    ;;
  *) exit 0 ;;
esac

if [ -n "${SPEAK_ALERT_DRY_RUN:-}" ] && [ "$SPEAK_ALERT_DRY_RUN" != voice ]; then
  echo "$phrase"
  exit 0
fi

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
