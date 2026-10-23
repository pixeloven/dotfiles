#!/usr/bin/env bash
# Claude Code hook: speak a short line when an agent stops or needs attention.
# Usage: speak-alert.sh <stop|notify>   (hook JSON on stdin; uses its "cwd")
# Silent for fleet workers (FM_TASK_ID set) and when ~/.config/speak-alert/muted exists.
# Always exits 0 so it can never block Claude Code.

[ -n "${FM_TASK_ID:-}" ] && exit 0
[ -e "$HOME/.config/speak-alert/muted" ] && exit 0

cwd="$(jq -r '.cwd // empty' 2>/dev/null)"
project="${cwd:+$(basename "$cwd")}"
project="${project:-Claude}"

case "${1:-}" in
  stop) phrase="$project finished" ;;
  notify) phrase="$project needs you" ;;
  *) exit 0 ;;
esac

if [ -n "${SPEAK_ALERT_DRY_RUN:-}" ]; then
  echo "$phrase"
else
  (say -v "${SPEAK_ALERT_VOICE:-Samantha}" -r "${SPEAK_ALERT_RATE:-210}" "$phrase" > /dev/null 2>&1 &)
fi
exit 0
