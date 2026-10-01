## Context

See `proposal.md` for the failure and `specs/transcription-model-loading/spec.md` for the behavior contract.

`WhisperCppTranscriptionClient` is the shared actor used by warmup, push-to-talk dictation, and Meeting transcription. It currently creates `WhisperCppContext` synchronously on that actor. Context creation enters `whisper_init_from_file_with_params`, which may spend tens of seconds compiling Metal code, loading the GGML model, and loading the Core ML encoder without observing Swift task cancellation.

`AsyncOperationTimeout` cancels the warmup task after 30 seconds, but cancellation cannot stop a native call already in progress. The shared actor stays occupied even though the app reports the requester as timed out or canceled. `AppController` also starts the dictation processing timer before `DictationPipeline.stopAndProcess`, so waiting behind that native call consumes the same 30-second budget as audio processing and decoding.

## Goals / Non-Goals

**Goals:**

- Keep native context initialization independent from the lifetime of any one requester.
- Allow same-model requesters to share one load and cancel their own wait promptly.
- Keep the shared ASR path serialized without loading two large models at once.
- Start the existing dictation processing budget after the selected model is ready.
- Make concurrency and cancellation behavior testable without loading a real Whisper model.

**Non-Goals:**

- Making `whisper.cpp`, Metal, or Core ML initialization interruptible.
- Increasing the existing 30-second warmup or dictation processing limits.
- Preloading every installed model or retaining several model contexts in memory.
- Changing model files, decoding settings, audio preprocessing, Meeting processing limits, or audio-input selection.
- Adding a third-party concurrency framework or a new persistent setting.

## Decisions

### Run native context creation outside the client actor

Keep model-load ownership with the shared Whisper client, but move synchronous context construction into one app-lifetime unstructured task that does not inherit requester cancellation. The client actor stores a load record containing the model identity, a generation token, the underlying task, and its waiting requests.

The actor remains responsive while the native function runs. A request for the same model joins the load record. A request for another model waits for the current non-interruptible load to finish, then starts the requested load if the requester is still active. VoicePen will not load two large Whisper contexts concurrently.

When loading succeeds, the actor installs the context only if the generation and model identity still match the load record. The client keeps one resident context, matching current behavior. When loading fails, it clears the record and resumes every waiter with the same error.

Inject context construction behind a small internal loader boundary. Production uses `WhisperCppContext`; tests use controlled loaders that can ignore cancellation and complete or fail on demand.

Alternative considered: keep synchronous construction on the actor and rely on actor serialization. Rejected because queued callers cannot distinguish waiting for model readiness from decoding, and the actor cannot register or cancel individual waiters while native initialization blocks it.

### Cancel waiters without canceling native initialization

Represent each warmup, dictation, or Meeting request as a separate waiter on the load record. A task cancellation removes and resumes only that waiter. It does not cancel the underlying native task after initialization has started.

Warmup keeps its existing 30-second requester timeout and runtime failure state. If native initialization later succeeds, the client caches the context. A later warmup or transcription request then observes readiness without another load. Current model identity checks remain responsible for app-facing runtime state, so completion for an old selection cannot mark a different selected model ready.

Alternative considered: propagate every requester cancellation to the native load. Rejected because the native function does not observe Swift cancellation, which creates false canceled state while work continues.

### Prepare a routed transcription request before starting its processing timer

Split local transcription into readiness and execution phases through an internal prepared-request boundary. The readiness phase captures the selected backend and model, joins or starts its model load, and returns an execution handle bound to that exact model and context. The execution phase performs decoding and returns the existing text, segment, timing, and model metadata result.

For push-to-talk, `DictationPipeline` stops and validates the recording, prepares the routed transcription request, then applies the existing 30-second timeout to subsequent preprocessing, decoding, normalization, and insertion. Moving timeout ownership into the pipeline gives it direct access to the readiness boundary and keeps phase rules out of the SwiftUI-facing `AppController`. Escape cancellation continues to cancel the complete dictation task during either phase.

Meeting transcription uses the same preparation path and load coordinator, but retains its existing processing timeout policy.

Alternative considered: increase the global dictation timeout. Rejected because cold-load time varies by device and the app would still misreport abandoned native work as canceled.

Alternative considered: pause and resume the current `AppController` timer from model-load callbacks. Rejected because callbacks would couple the transcription backend to app UI orchestration and make timeout races harder to test.

### Log load and request lifecycles separately

Emit structured messages for native load start, same-model join, different-model wait, load completion or failure, and requester cancellation. Include the model identity and generation token. Dictation timeout logs record that the timed phase began after readiness, so future reports separate cold loading from slow preprocessing or decoding.

Alternative considered: retain the existing warmup-only messages. Rejected because they describe the requester but hide native work that continues after that requester ends.

## Risks / Trade-offs

- [A cold native load can outlive every requester] -> Keep the loader task owned by the app-lifetime transcription client and release its result only through the generation-checked completion path.
- [A newly selected model waits for an obsolete non-interruptible load] -> Serialize native loads to avoid CPU and memory spikes, identify the wait in diagnostics, and start the new load as soon as the old call returns.
- [Cancellation and native completion can race] -> Register and remove waiters only on the client actor and resume each waiter once.
- [Total wall time for first dictation can exceed 30 seconds] -> Treat model readiness as a separate phase, keep it cancelable for the requester, and retain the 30-second limit for work after readiness.
- [Moving timeout ownership changes error propagation] -> Preserve the existing `TranscriptionError.transcriptionTimedOut` contract and AppController error handling, then cover timeout and cancellation transitions with direct behavior tests.

## Migration Plan

1. Update the push-to-talk dictation, local transcription, and model-loading
   behavior contracts with the readiness phase, timeout boundary, shared load
   behavior, and automated test tasks.
2. Add the injectable load coordinator behavior and non-cooperative loader tests.
3. Add the prepared transcription boundary and move dictation timeout ownership to the pipeline.
4. Wire warmup, dictation, and Meeting through the same coordinator without changing persisted settings or model assets.
5. Run focused tests, OpenSpec and repository spec validation, `make test`, and the app build.

Rollback restores the current synchronous actor load and AppController timeout monitor. No data migration or cleanup is required.
