## 1. Contract and tests

- [x] 1.1 Define source-audio archive behavior and map each scenario to focused automated coverage.

Coverage: dictation source/short/error tests in `DictationPipelineTests`; meeting source/offset/cancel/retry/error tests in `MeetingPipelineTests`; raw mix and timing tests in meeting chunker tests; archive copy and retention tests in `SavedAudioArchiveTests` and `SavedAudioArchiveSchedulerTests`.
- [x] 1.2 Update meeting and archive tests for one raw mix, effect-free samples, failure, retry, copy lifetime, and file pruning.

## 2. Implementation

- [x] 2.1 Save one raw dictation source before processing and update settings copy.
- [x] 2.2 Create one raw meeting mix and await its archive copy before source cleanup.
- [x] 2.3 Remove the track-folder/manifest archive path and retain per-file pruning.

## 3. Verification

- [x] 3.1 Reconcile superseded clauses into main specs, run strict OpenSpec validation and `make test`.
- [x] 3.2 Run `make build` for app wiring.
- [x] 3.3 Inspect a short real dictation saved by the new dev build: one readable 16 kHz mono Float32 WAV with non-silent samples.
- [x] 3.4 Inspect a short real meeting saved by the new dev build: one readable 16 kHz mono WAV matching the captured microphone and system sources. The system source in this recording was silent, so audible system contribution was not exercised.

## 4. Preserve level when a captured source is silent

- [x] 4.1 Add raw-mix tests for either silent source, non-silent overlap, and output-range clipping.
- [x] 4.2 Sum captured samples without averaging and clamp only out-of-range output.
- [x] 4.3 Run strict OpenSpec validation and `make test`; verify the new mixer against the recorded microphone and silent system source.
