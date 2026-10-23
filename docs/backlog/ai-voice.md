# AI voice: natural TTS and STT for the agent terminal

Status: proposed (to file as a GitHub issue once the repo is published).

## Goal
Talk to agents and hear them back with modern AI voice quality, not macOS `say`:
- **STT (speech to text):** dictate prompts into Claude Code or herdr panes with high accuracy on technical terms (code identifiers, CLI flags, repo names).
- **TTS (text to speech):** natural-sounding spoken replies or summaries when an agent finishes or needs attention, beyond the current one-line `speak-alert.sh`.

## Options to evaluate
- STT, local: whisper.cpp / MLX Whisper (large-v3-turbo) behind a push-to-talk hotkey; Superwhisper or MacWhisper as packaged apps.
- STT, cloud: OpenAI or Deepgram streaming; Wispr Flow.
- TTS, local: Kokoro, Piper, or the macOS Premium voices (the current baseline).
- TTS, cloud: ElevenLabs, OpenAI TTS, Cartesia.
- Integration points: Claude Code hooks (Stop and Notification payloads for spoken summaries), Claude Code's built-in voice input if available, herdr notifications.

## Questions
- Local only, or is a cloud API acceptable (cost, privacy for work repos)?
- Speak the full reply, a summary, or only alerts? Who summarizes, and with which model?
- Push-to-talk key and which panes it targets.

## Done when
A runbook plus config in this repo gives push-to-talk dictation and natural spoken alerts/summaries, toggleable, with API keys kept out of the repo (env or Keychain, never committed).
