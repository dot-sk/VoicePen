## Why

VoicePen has no manually verified audio/reference corpus for measuring recognition quality. Sergey needs to correct and confirm real dictations before comparing quality and latency hypotheses, especially word/term errors and unwanted repetitions.

## What Changes

- Prepare a private local draft corpus of long, potentially difficult dictations from saved audio and history, preserving audio and provenance. Start with the user's selected 27 recordings of at least 20 seconds.
- Provide a loopback review page with audio playback, editable reference text, explicit confirmation, exclusion, and progress.
- Export immutable, fingerprinted golden snapshots containing only manually confirmed references and their audio.
- Document reference-writing rules and keep personal audio, drafts, and exports outside Git.
- Keep recognition experiments and model changes for the next stage after human review.

## Capabilities

### New Capabilities

- `asr-golden-dataset`: Local corpus preparation, human review, and reproducible confirmed exports.

### Modified Capabilities

None.

## Impact

Adds standalone development tooling under `Tools/ASRQuality`, focused tooling tests and make commands. No macOS application, model, recognition parameter, or user database changes; no new third-party dependencies.
