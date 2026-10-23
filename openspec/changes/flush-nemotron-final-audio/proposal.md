## Why

Short English recordings can produce empty Nemotron results because the final speech needs another chunk of context. A local experiment recovered the same speech by appending a silent chunk before finalization.

## What Changes

- Feed an internal 2.24-second silent tail after all original audio for every Nemotron English request.
- Preserve original recording files, duration and original input-frame accounting.
- Keep cancellation, session reset, final-only output and other backends unchanged.

## Capabilities

### New Capabilities

### Modified Capabilities

- `local-transcription-model-handling`: Nemotron-only final audio context.

## Impact

Native Nemotron file adapter and automated native regression tests. No downloads, dependencies, settings or saved-audio format changes.
