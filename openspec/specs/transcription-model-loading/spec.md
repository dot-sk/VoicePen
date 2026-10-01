# transcription-model-loading Specification

## Purpose

Keep local transcription reliable while a selected model is loading, including when native initialization does not respond to Swift task cancellation.

## Requirements

### Requirement: Concurrent requesters share one model load

VoicePen SHALL coordinate model readiness across warmup, push-to-talk dictation, and Meeting transcription. While a model is loading, every request for that same model SHALL wait for the existing load instead of starting another native initialization.

#### Scenario: Dictation starts during warmup

- **WHEN** warmup is loading the selected model and push-to-talk dictation requests that same model
- **THEN** dictation waits for the existing load and VoicePen performs only one native initialization for that model

#### Scenario: Meeting and dictation request a cold model

- **WHEN** Meeting transcription and push-to-talk dictation request the same unloaded model concurrently
- **THEN** both requests share one model load before their transcription work is serialized

### Requirement: Requester cancellation does not abandon native loading

When native model initialization has started, a warmup timeout or requester cancellation SHALL stop that requester from waiting without treating the underlying initialization as stopped. VoicePen SHALL keep the load tracked until it succeeds or fails, and SHALL reuse a successful result for later requests for the same model.

#### Scenario: Warmup times out during non-cooperative loading

- **WHEN** warmup reaches its timeout while native initialization continues without observing cancellation
- **THEN** VoicePen leaves the warming state, keeps the native load tracked, and does not start a duplicate load for the same model

#### Scenario: Recording cancels its warmup requester

- **WHEN** recording starts while warmup is waiting for native initialization
- **THEN** recording starts without waiting for warmup, the warmup requester ends, and the native load remains available to the later transcription request

#### Scenario: Native loading completes after warmup cancellation

- **WHEN** native initialization succeeds after its warmup requester has timed out or been canceled
- **THEN** VoicePen stores the loaded context and reuses it for the next request for that model

### Requirement: Cold loading does not consume the dictation processing timeout

VoicePen SHALL exclude time spent waiting for the selected model to become ready from the 30-second dictation processing timeout. Once the model is ready, subsequent audio preprocessing, transcription, normalization, and insertion SHALL share that processing timeout.

#### Scenario: Cold model takes longer than the warmup timeout

- **WHEN** a valid dictation waits more than 30 seconds for its selected model to finish loading and its remaining processing completes within the processing timeout
- **THEN** VoicePen returns the transcription instead of reporting a dictation processing timeout

#### Scenario: Processing hangs after model readiness

- **WHEN** the selected model is ready but subsequent dictation processing exceeds the 30-second processing timeout
- **THEN** VoicePen cancels the dictation request, leaves the transcribing state, surfaces a timeout error, and allows another recording attempt

#### Scenario: User cancels while waiting for model readiness

- **WHEN** the user cancels dictation while it is waiting for a cold model
- **THEN** VoicePen ends that dictation wait promptly without requiring native initialization to stop

### Requirement: Model loads remain isolated by model identity

VoicePen MUST associate every in-flight load and loaded context with its exact model identity. A request SHALL NOT use a context loaded for another model.

#### Scenario: Selection changes during an old model load

- **WHEN** one model is loading and the user selects a different model before that load finishes
- **THEN** requests for the new selection do not join or use the old model load

#### Scenario: Old model finishes after selection changes

- **WHEN** initialization for the previous selection finishes after a different model becomes active
- **THEN** VoicePen does not mark the active model ready from the old result

### Requirement: Model-load failures are retryable

VoicePen SHALL deliver a native model-load failure to every request waiting for that load, clear the failed in-flight operation, and allow a later request to start a fresh load.

#### Scenario: Shared model load fails

- **WHEN** native initialization fails while warmup and transcription are waiting for the same model
- **THEN** both requesters receive the model-load failure and VoicePen keeps no failed load as ready

#### Scenario: Request retries after failure

- **WHEN** a later request asks for the same model after the failed load has been cleared
- **THEN** VoicePen starts a new model-load attempt

### Requirement: Diagnostics identify model loading and waiting

VoicePen SHALL log model-load start, shared-load wait, completion, cancellation of a requester, and failure with the associated model identity. Dictation timeout diagnostics SHALL distinguish time spent waiting for model readiness from timed audio processing or transcription.

#### Scenario: Warmup requester times out but loading continues

- **WHEN** the warmup requester times out during native initialization
- **THEN** diagnostics show that the requester ended while the identified model load remained in progress

#### Scenario: Dictation joins a load

- **WHEN** dictation waits for an existing model load
- **THEN** diagnostics identify the joined model load and do not report that a second load started
