## Why

VoicePen already packages FluidAudio for diarization, which also provides a local English Nemotron recognizer. Users should be able to choose it for the existing record-then-transcribe workflow without live transcription or incremental text insertion.

## What Changes

- Add Nemotron Speech English 0.6B to the existing persistent model selector without changing current selections or the recommended Whisper model.
- Reuse the pinned FluidAudio dependency behind a local file-recognition adapter, with fixed English greedy RNNT capabilities and final text only.
- Install verified immutable Core ML assets through the existing confirmed, proxy-aware download flow.
- Preserve ordinary normalization, final insertion, history, cancellation and model resource lifecycle.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-transcription-model-handling`: Optional English Nemotron selection, verified installation and effective controls.
- `transcription-model-loading`: Local file recognition and isolated, serialized Nemotron request lifecycle.

## Impact

The bundled model manifest, recognition capabilities, backend routing, model installation, FluidAudio adapter, settings and tests. No new dependency, streaming UI, incremental insertion, automatic language-based model routing or database migration.
