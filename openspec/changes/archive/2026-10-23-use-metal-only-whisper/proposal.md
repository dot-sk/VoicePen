## Why

VoicePen requires a large Core ML companion for Whisper ASR and can trigger an unpredictable first compilation. The existing pinned runtime can execute both encoder and decoder on Metal with the same installed weights, as demonstrated by the local benchmark.

## What Changes

- Run both Whisper ASR stages through Metal on Apple Silicon, including with legacy Core ML files installed.
- Require and download selected weights only. Reuse valid installed weights without another download or encoder compilation.
- Preserve model IDs, recommended quantization, selections, language, profiles, glossary, timestamps, shared loading, and dictation/Meeting routing.
- Report actual ASR acceleration and surface unavailable Metal initialization without silently using CPU inference.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-transcription-model-handling`: Metal-only Whisper ASR, weights-only installation and migration, and actual acceleration diagnostics.

## Impact

Reuses the pinned whisper.cpp framework through an app-owned isolated weight path. Touches Whisper initialization, manifest/fallback, readiness, downloads, diagnostics, and focused tests. Adds no model family or runtime dependency. Separate Meeting diarization retains its current execution path. Proposed ADR-0012 records the backend decision.
