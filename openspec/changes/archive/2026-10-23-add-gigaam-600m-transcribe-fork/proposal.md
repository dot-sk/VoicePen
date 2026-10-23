## Why

The measured GigaAM Multilingual 600M checkpoint currently runs through a Python/MLX research path. A pinned, narrowly patched transcribe.cpp fork would make the same checkpoint available through native C++/ggml Metal inference and a Swift-consumable package, with reproducible evidence that the port preserves recognition behavior.

## What Changes

- Promote the existing research converter and native prototype into a distinct GigaAM Multilingual 600M CTC profile in a pinned fork of `handy-computer/transcribe.cpp`. The primary candidate uses F16 storage, a Metal encoder, host CTC projection, and the measured 25-second window policy.
- Preserve the research source patch, scripts, and provenance in this change's `research/` handoff. Keep detailed benchmark results in ignored local storage and summarize conclusions in the implementation evidence.
- Validate floating-point parity and F16 against the complete frozen audio/reference corpus. Evaluate optional ggml Q8 independently; a failing Q8 candidate does not block accepted F16 availability. Keep model identity, numerical parity, recognition quality, and performance evidence separate.
- Expose accurate model capabilities, Metal execution diagnostics, cancellation, and errors through the existing native interface.
- Carry forward the measured host-versus-Metal CTC projection experiment. Keep the host-head baseline because the current experiment found no convincing end-to-end gain; retain parity and performance gates for any later placement change.
- Produce a reproducible macOS Apple Silicon library package with its C interface, Swift import smoke client, Metal resources, artifact checksums, license provenance, and rollback instructions.
- Keep the fork patch set and upstream update policy explicit. This proposal does not create or publish a hosted fork or release.

## Capabilities

### New Capabilities

- `native-gigaam-600m-runtime`: checkpoint-compatible native inference, quality acceptance, callable package behavior, and reproducible dependency artifacts.

### Modified Capabilities

None. VoicePen model selection, defaults, settings, downloads, dictation and Meeting routing, loading, and diagnostics are outside this backend/package change. The existing Whisper-only `use-metal-only-whisper` change is unchanged.

## Impact

Implementation promotes and hardens the preserved prototype in the maintained transcribe.cpp fork, its converter, GigaAM profile/frontend/encoder/decoder/capabilities, native tests, benchmark tooling, and library packaging. Python is allowed for offline conversion and validation; the packaged inference runtime must not require Python or MLX. No VoicePen production Swift, application dependency wiring, manifest, model delivery, or UI changes are planned here. Proposed ADR-0013 records the dependency and model strategy. A later app-integration change must decide supported product controls and migration behavior.
