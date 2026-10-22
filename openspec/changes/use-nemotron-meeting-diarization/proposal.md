## Why

The user selected Nemotron-3 offline after local meeting comparisons and a Release size comparison. VoicePen should use that tested model/runtime combination instead of maintaining the old SpeakerKit pipeline.

## What Changes

- Replace SpeakerKit/Argmax with FluidAudio's pinned Nemotron-3 offline Core ML runtime, with optional text normalization disabled.
- Retain full-timeline 16 kHz audio, one speaker cache per recording, current transcript mapping and current turn postprocessing.
- Download pinned compiled model files through VoicePen's proxy-aware verified downloader and install them transactionally.
- Normalize old backend preferences to the sole Nemotron backend. Existing SpeakerKit artifacts do not establish Nemotron readiness and are replaced only after a successful download.
- Preserve existing history, ASR, UI surfaces, cancellation and transcript preservation on diarization failure.

- Load the diarization runtime only for analysis and release it immediately after the last active request, including errors/cancellation. Do not prewarm on startup, enable or download.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `meeting-recording-mode`: replace the diarization backend and artifact installation contract while retaining the existing meeting workflow.

## Impact

Meeting runtime adapter and download metadata, SwiftPM/Xcode dependencies, settings normalization, model lifecycle tests and native meeting regression checks. A superseding ADR records the backend decision. This replaces the intended direction of the unimplemented slim-diarization-runtime proposal; participant filtering and custom signature matching are outside scope.
