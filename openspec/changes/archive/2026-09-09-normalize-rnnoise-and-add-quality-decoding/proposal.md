## Why

Some RNNoise-processed microphone recordings reach local transcription with
sample magnitudes above the normal full-scale range, which can make recognition
quality unstable. VoicePen also always uses greedy Whisper decoding, so users
cannot trade additional latency for a more exhaustive local decode when
accuracy matters more than speed.

## What Changes

- Bound RNNoise output before silence analysis, saved transcription-input
  audio, mixing, and local transcription without amplifying already safe or
  quiet audio.
- Preserve the existing RNNoise failure fallback, microphone timeline, raw
  recordings, and microphone-boost behavior.
- Add a persistent local decoding profile in Model settings with the current
  greedy behavior as the default and an opt-in maximum-quality beam-search
  profile.
- Apply the selected decoding profile consistently to future push-to-talk and
  Meeting transcription requests while keeping warmup lightweight.
- Add diagnostics and automated coverage for audio attenuation, safe-signal
  pass-through, decoding-strategy selection, defaults, persistence, and invalid
  stored values.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-settings-voice-processing`: Bound successful RNNoise microphone output
  before downstream processing while preserving timeline and failure fallback.
- `push-to-talk-dictation-pipeline`: Require saved and transcribed derived
  dictation audio to use the bounded RNNoise output.
- `local-transcription-model-handling`: Add a persistent global decoding profile
  and route ordinary local transcription through greedy or beam-search
  decoding.
- `history-settings-persistence`: Define the decoding-profile default,
  normalization, and immediate SQLite persistence behavior.

## Impact

- RNNoise microphone post-processing shared by dictation and Meeting Mode.
- Saved dictation transcription-input audio and Meeting microphone mastering.
- Whisper.cpp decoding options and diagnostics.
- Model settings UI, `AppSettingsStore`, `AppController`, and live transcription
  wiring.
- Swift Testing coverage for audio processing, settings persistence, controller
  bindings, and decoder parameter selection.
- No new model assets, cloud services, dependencies, database schema migration,
  or ADR.
