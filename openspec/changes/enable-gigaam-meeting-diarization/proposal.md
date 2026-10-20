## Why

GigaAM Meeting recordings currently save plain text even when speaker labeling is enabled. The native CTC result contains token timing that VoicePen can use to align the recognized words with local diarization, so skipping the entire stage is unnecessary.

## What Changes

- Derive word timing from GigaAM's native token alignment when a Meeting requests timestamps, without another ASR pass.
- Enable the existing Meeting timecode and speaker-label options for GigaAM while keeping VAD, forced language, prompts, and beam search unavailable.
- Preserve the plain transcript if token alignment is invalid or speaker analysis fails.
- Leave existing saved Meetings untouched; retry from retained audio can regenerate a labeled transcript.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `meeting-recording-mode`: GigaAM Meeting recordings can run local diarization using aligned words.
- `local-transcription-model-handling`: GigaAM exposes effective Meeting timing while native timestamp output remains unsupported.

## Impact

GigaAM adapter, recognition capability policy, Meeting settings and diagnostics, Meeting pipeline tests, and native integration verification. No new dependency or model download.
