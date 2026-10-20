## Why

The native GigaAM Multilingual 600M work ends at a tested library package. VoicePen needs application integration so a user can select, install, and use that same model for dictation and Meetings, then compare its actual application output with the frozen quality corpus.

## What Changes

- Add GigaAM Multilingual 600M F16 to the existing Model settings selector alongside Whisper. Preserve the recommended Whisper model and existing saved selections.
- Connect the accepted package from `add-gigaam-600m-transcribe-fork` to the SwiftPM and macOS app builds. Use the accepted Metal encoder, host CTC head, and internal 25-second window policy without a Python inference dependency.
- Deliver the accepted GGUF through the existing confirmed, proxy-aware, size/hash-verified model installation flow and immutable GitHub model-assets release. Include progress, cancellation, retry, deletion, readiness, and restart behavior.
- Add native GigaAM download, warmup, and transcription routing shared by push-to-talk and Meeting processing, with model-isolated contexts, serialized native work, cancellation, retryable errors, history metadata, and actual backend diagnostics.
- Make recognition controls reflect model capabilities. The initial GigaAM integration uses automatic multilingual recognition and greedy CTC, supports dictionary replacement after recognition, and exposes no Whisper prompting or beam-search promise. It produces text-only Meetings without invented timestamps or speaker labels, while retaining saved Whisper preferences.
- Verify the packaged application adapter against the accepted native candidate on all 27 frozen inputs and preserve the existing Whisper workflow, including coexistence with the separate Metal-only Whisper change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-transcription-model-handling`: selectable GigaAM model, verified delivery, model capabilities, effective decoding controls, and backend diagnostics.
- `transcription-model-loading`: GigaAM readiness and resource lifecycle across warmup, model changes, and overlapping workflows.
- `push-to-talk-dictation-pipeline`: captured GigaAM routing and native cancellation through the existing dictation workflow.
- `meeting-recording-mode`: complete-master GigaAM transcription and explicit text-only behavior for unsupported timing features.
- `custom-dictionary-normalization`: preserve local replacements while gating decoder glossary prompting by capability.

## Impact

Touches the manifest/backend and capability models, verified download routing, a new GigaAM adapter/context, app composition and `AppModelRuntimeStore`, settings and native menu policy, dictation/Meeting request preparation, history metadata, acceleration diagnostics, dependency resources, build/distribution configuration, and focused automated coverage. Extend existing feature ownership; keep `AppController` a facade.

This change depends on acceptance of the package/model pair from `add-gigaam-600m-transcribe-fork`; it does not redo the port or its research. `use-metal-only-whisper` remains independent, and Whisper stays on whisper.cpp. Model/library asset publication and signed app release are reviewable delivery steps, not actions performed by this proposal. A distributable selector entry requires real immutable asset coordinates and digests, never placeholder URLs or runtime Hugging Face access. No remote ASR, Python service, automatic migration to GigaAM, optional Q8 selection, or new timestamp/alignment engine is included.
