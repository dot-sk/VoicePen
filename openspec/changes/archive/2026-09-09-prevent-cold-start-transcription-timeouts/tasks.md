## 1. Update behavior contracts

- [x] 1.1 Capture that model-readiness waiting is outside the 30-second dictation processing budget while post-readiness processing and cancellation keep their existing behavior and automated coverage.
- [x] 1.2 Capture shared in-flight loading, non-cooperative native initialization, same-model reuse, model-identity isolation, failure retry, diagnostics, and automated coverage.

## 2. Coordinate native model loading

- [x] 2.1 Add an injectable Whisper context-loading boundary that lets tests control native initialization without loading real model artifacts.
- [x] 2.2 Move synchronous context creation off the shared transcription actor executor into one client-owned load task with model identity and generation tracking.
- [x] 2.3 Implement cancellation-aware per-request waiters so canceling warmup, dictation, or Meeting waiting does not cancel or orphan the native load.
- [x] 2.4 Serialize different-model loads, join same-model loads, retain only the current resident context, and prevent stale completion from satisfying another model.
- [x] 2.5 Clear failed load state, deliver the failure to all current waiters, and allow the next request for that model to retry.
- [x] 2.6 Add transcription-client tests for one same-model load, non-cooperative cancellation, late reuse, concurrent Meeting and dictation readiness, model changes, completion races, shared failure, and retry.

## 3. Separate readiness from timed dictation processing

- [x] 3.1 Add an internal prepared-transcription request that captures the routed backend, model identity, loaded context, and existing result metadata.
- [x] 3.2 Make warmup, push-to-talk dictation, and Meeting transcription use the same model-readiness coordinator while preserving their existing decode serialization.
- [x] 3.3 Move the 30-second dictation processing timeout from `AppController` to the post-readiness portion of `DictationPipeline`.
- [x] 3.4 Preserve `TranscriptionError.transcriptionTimedOut`, idle-state recovery, overlay errors, later retry, and Escape cancellation during both readiness and processing phases.
- [x] 3.5 Add pipeline and app-controller tests proving that a cold load longer than 30 seconds can still produce a transcript, post-readiness hangs still time out, and user cancellation ends model waiting promptly.

## 4. Improve lifecycle diagnostics

- [x] 4.1 Log native load start, same-model join, different-model wait, completion, and failure with model identity and generation.
- [x] 4.2 Log requester cancellation separately from native-load completion and identify the timed phase when dictation processing expires.
- [x] 4.3 Add direct behavior tests for diagnostic event selection without asserting incidental log wording.

## 5. Verify

- [x] 5.1 Run `openspec validate prevent-cold-start-transcription-timeouts --strict`, `make validate-specs`, and `make format-check`.
- [x] 5.2 Run `make test`.
- [x] 5.3 Run `make build`.
- [x] 5.4 Reproduce a cold `ggml-large-v3-turbo-q5_1` startup on the app target and confirm that dictation waits for the existing load, performs one native initialization, and completes recognition without a premature processing timeout.
