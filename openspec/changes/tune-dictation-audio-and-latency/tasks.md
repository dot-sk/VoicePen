## 1. Contract and tests

- [x] 1.1 Cover missing RNNoise default, initialization, persisted true/false, and manual toggling in AppSettingsStoreTests: loadEnablesAudioProcessingDefaultsWhenMissing, updateDictationDenoisingEnabledPublishesAndPersistsValue, loadPreservesSavedDenoisingChoice
- [x] 1.2 Cover successful stop/readiness/total timing with an injected monotonic clock, original deferred-release boundary, and absent completed timing for skipped attempts: completeLatencyIncludesRecordingStopReadinessAndReleaseWait, deferredStopPreservesFirstReleaseTimeAndResetsForNextRecording, skippedDictationHasNoCompletedLatency; retain existing cancellation/error coverage
- [x] 1.3 Cover old timing JSON compatibility and new history timing round-trip: oldTimingJSONDoesNotInventCompleteLatency, completeLatencyAndAdditionalStagesRoundTrip

## 2. Implementation

- [x] 2.1 Change only unsaved dictation RNNoise defaults
- [x] 2.2 Carry original stop request time through startup and record complete latency plus stop/readiness stages
- [x] 2.3 Expose available new timing rows in session metadata

## 3. Verification

- [x] 3.1 Run strict OpenSpec validation for both new changes
- [x] 3.2 Run make test: 727 tests in 80 suites passed in the final standalone run
- [x] 3.3 Run make build for app wiring and inspect the scoped diff: build succeeded; git diff --check and strict swift-format lint passed for all nine changed Swift files
