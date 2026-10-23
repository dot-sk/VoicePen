## Why

Update the bundled Whisper runtime from v1.8.5 to the latest stable upstream release, v1.9.5, while preserving installed models and existing transcription features.

## What Changes

- Pin the official v1.9.5 binary distribution and its verified checksum.
- Report the updated runtime identity in transcription diagnostics.
- Verify Metal execution, existing Q5/Q8 installations, confidence evidence, timestamp requests, and coexistence with GigaAM.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-transcription-model-handling`: preserve installed Whisper models and transcription features across a bundled runtime upgrade and identify the runtime in diagnostics.

## Impact

Local `whisper.spm` binary dependency, Whisper execution diagnostics, native regression tests. No weight downloads, model selection changes, decoding changes, or new UI.
