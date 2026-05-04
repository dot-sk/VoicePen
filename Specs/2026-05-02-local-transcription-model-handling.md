---
id: SPEC-002
status: implemented
updated: 2026-05-05
tests:
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/Transcription/FluidAudioModelDownloadClientTests.swift
  - VoicePenTests/Transcription/WhisperCppTranscriptionClientTests.swift
  - VoicePenTests/Transcription/ModelDownloadProxyConfigurationTests.swift
  - VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift
  - VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift
---

# Local Transcription And Model Handling

## Problem

VoicePen needs usable offline transcription while model files are large, backend-specific, and installed only after user confirmation.

## Behavior

VoicePen loads a bundled model manifest, selects a compatible local model, routes transcription and downloads by backend, checks required artifacts, supports proxy settings for model downloads, and reports acceleration diagnostics. It does not provide cloud fallback transcription, automatic downloads without confirmation, or public model marketplace behavior.

## Acceptance Criteria

- When the saved selected model is missing or incompatible, VoicePen shall use the recommended model.
- When a Whisper.cpp model is selected, VoicePen shall require the expected model and Core ML companion artifacts before accelerated transcription.
- When a Whisper.cpp model is installed by download, VoicePen shall treat it as installed only after the full download set validates and a completed-download marker is written.
- When a transcription request runs, VoicePen shall route it to the backend that matches the selected model.
- When a model download starts, VoicePen shall route it to the backend-specific downloader.
- When model download progress is known, VoicePen shall show the same progress visually in the Model settings progress bar instead of an indeterminate progress animation.
- When a model download fails or is canceled before validation completes, VoicePen shall keep the model missing, allow retry without manual deletion, and may reuse artifacts that were individually completed.
- When a FluidAudio model is selected, VoicePen shall treat it as installed only when its completed-download marker exists and FluidAudio reports the model files present for that version.
- When FluidAudio reports progress for internal cache or compile steps, VoicePen shall keep visible download progress monotonic and switch non-download work to preparing/validating state.
- When proxy settings exist in the local environment settings file, VoicePen shall use them for model downloads.
- When diagnostics are copied, VoicePen shall report installed state, backend/source, version, size, and artifact status.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Missing saved model | Unknown selected model id | Recommended model is selected |
| Whisper.cpp artifact missing | Model exists without Core ML companion | Acceleration is unavailable |
| Blocked download | Network/proxy failure leaves a model file without a completed-download marker | Model remains Missing and Download Model remains available |
| Known download progress | Downloader reports 42% progress | Model settings shows determinate progress at the same fraction |
| Retry after partial success | Main GGML artifact completed but companion download failed | Retry may reuse the completed GGML artifact and continue remaining artifacts |
| Empty artifact | Blocked download leaves an empty GGML file | GGML is not reported ready |
| Partial Parakeet install | Parakeet folder and marker exist without FluidAudio-required files | Model remains Missing and Download Model remains available |
| Parakeet compile progress | FluidAudio emits 100%, then 50% for another internal step | Visible download progress does not move backward |
| FluidAudio selected | Transcription request | FluidAudio client handles transcription |
| Proxy configured | `http_proxy` or `https_proxy` in settings | Download uses proxy configuration |

## Test Mapping

- Automated: `VoicePenTests/App/AppControllerTests.swift` covers failed and canceled model downloads leaving the model missing and retryable.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that Model settings renders known download progress as determinate linear progress.
- Automated: `VoicePenTests/Transcription/FluidAudioModelDownloadClientTests.swift` covers FluidAudio installed-state checks and monotonic Parakeet progress despite FluidAudio cache and compile progress callbacks.
- Automated: `VoicePenTests/Transcription/WhisperCppTranscriptionClientTests.swift` covers artifact, acceleration, empty artifact, and completed-download marker checks.
- Automated: `VoicePenTests/Transcription/ModelDownloadProxyConfigurationTests.swift` covers proxy configuration.
- Automated: routing behavior belongs in `VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift` and `VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift` when those files are present.
- Manual: verify a fresh install prompts before downloading model files and can transcribe after required artifacts are installed.

## Notes

Keep backend decisions in routing clients rather than UI code. Keep model metadata in `VoicePen/Resources/model-manifest.json` and artifact path logic in the model/path helpers.

## Open Questions

- None.
