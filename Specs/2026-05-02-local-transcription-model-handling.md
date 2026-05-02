---
id: SPEC-002
status: implemented
updated: 2026-05-02
tests:
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
- When a transcription request runs, VoicePen shall route it to the backend that matches the selected model.
- When a model download starts, VoicePen shall route it to the backend-specific downloader.
- When proxy settings exist in the local environment settings file, VoicePen shall use them for model downloads.
- When diagnostics are copied, VoicePen shall report installed state, backend/source, version, size, and artifact status.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Missing saved model | Unknown selected model id | Recommended model is selected |
| Whisper.cpp artifact missing | Model exists without Core ML companion | Acceleration is unavailable |
| FluidAudio selected | Transcription request | FluidAudio client handles transcription |
| Proxy configured | `http_proxy` or `https_proxy` in settings | Download uses proxy configuration |

## Test Mapping

- Automated: `VoicePenTests/Transcription/WhisperCppTranscriptionClientTests.swift` covers artifact and acceleration checks.
- Automated: `VoicePenTests/Transcription/ModelDownloadProxyConfigurationTests.swift` covers proxy configuration.
- Automated: routing behavior belongs in `VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift` and `VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift` when those files are present.
- Manual: verify a fresh install prompts before downloading model files and can transcribe after required artifacts are installed.

## Notes

Keep backend decisions in routing clients rather than UI code. Keep model metadata in `VoicePen/Resources/model-manifest.json` and artifact path logic in the model/path helpers.

## Open Questions

- None.
