## Why

Cold loading a Whisper model, its Metal kernels, and its Core ML encoder can exceed the current warmup timeout. Swift task cancellation cannot interrupt that native initialization, so VoicePen may report the warmup as canceled while it still occupies the shared transcription client and causes the next valid dictation to time out before decoding begins.

## What Changes

- Coordinate one in-flight native model load for the selected model and share it between warmup and transcription requests.
- Let a warmup requester time out or cancel without canceling, duplicating, or losing track of native initialization that is already running.
- Keep the 30-second dictation processing limit for audio processing and transcription work, but do not spend that budget waiting for an existing cold model load.
- Reuse a successfully loaded context after the original warmup requester has timed out or canceled.
- Keep model identities isolated so a load for an old selection cannot satisfy a request for a newly selected model.
- Surface native model-load failures to waiting requests and preserve retry behavior.
- Add lifecycle diagnostics and automated coverage for a model loader that ignores cooperative task cancellation.

## Capabilities

### New Capabilities

- `transcription-model-loading`: Covers shared cold model loading, requester cancellation, model changes, failures, and dictation timeout boundaries.

### Modified Capabilities

- None.

## Impact

- Whisper.cpp context creation and runtime state in the shared transcription client.
- Model warmup orchestration and dictation timeout orchestration.
- Routing between the selected model, warmup, push-to-talk dictation, and Meeting transcription.
- Automated tests for non-cooperative native loading, concurrent request coordination, cancellation, model changes, failures, and timeout phases.
- The push-to-talk dictation, local transcription, and model-loading behavior
  contracts must be updated before production code.
