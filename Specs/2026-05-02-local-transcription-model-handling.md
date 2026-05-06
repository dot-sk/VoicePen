---
id: SPEC-002
status: implemented
updated: 2026-05-07
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/Transcription/WhisperCppTranscriptionClientTests.swift
  - VoicePenTests/Transcription/ModelDownloadProxyConfigurationTests.swift
  - VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift
  - VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift
---

# Local Transcription And Model Handling

## Problem

VoicePen needs usable offline transcription while model files are large, backend-specific, and installed only after user confirmation.

## Behavior

VoicePen loads a bundled model manifest, presents compatible local models with
plain-language selection names, selects a compatible local model, routes
transcription and downloads by backend, checks required artifacts, supports
proxy settings for model downloads, and reports acceleration diagnostics. It
does not provide cloud fallback transcription, automatic downloads without
confirmation, or public model marketplace behavior.

## Acceptance Criteria

- When the saved selected model is missing or incompatible, VoicePen shall use the recommended model.
- When VoicePen shows local transcription model choices, it shall expose Whisper large-v3 turbo `q5_0`, `q5_1`, and `q8_0` as multilingual options with clear size/quality tradeoffs.
- When VoicePen shows model details, it shall show whether the selected model is multilingual or English-only.
- When VoicePen shows Recognition controls in Model settings, it shall expose each control's explanation through a question-mark help icon next to that control instead of using shared explanatory text below the controls; the Primary language explanation shall mention that choosing a single language can be faster than auto-detect.
- When VoicePen shows Model settings, it shall place supported Meeting-only controls in a Meeting features section, including transcript timecodes and Meeting diarization; these controls shall not be duplicated as availability-only rows.
- When VoicePen shows Meeting feature controls, the Meeting timecodes explanation shall describe adding timecodes without implementation-specific segment details, and the Meeting diarization explanation shall describe speaker labels from a separate local diarization model.
- When VoicePen shows Model settings, it shall avoid redundant bottom explanatory text once model details, actions, feature support, and per-control help are visible.
- When a Whisper.cpp model is selected, VoicePen shall require the expected model and Core ML companion artifacts before accelerated transcription.
- When a Whisper.cpp model is installed by download, VoicePen shall treat it as installed only after the full download set validates and a completed-download marker is written.
- When a transcription request runs, VoicePen shall route it to the backend that matches the selected model.
- When a model download starts, VoicePen shall route it to the backend-specific downloader.
- When model download progress is known, VoicePen shall show the same progress visually in the Model settings progress bar instead of an indeterminate progress animation.
- When a model download fails or is canceled before validation completes, VoicePen shall keep the model missing, allow retry without manual deletion, and may reuse artifacts that were individually completed.
- When a model download does not complete within the download timeout, VoicePen shall cancel the download, leave the downloading state, keep the model retryable, and surface a timeout error.
- When model warmup does not complete within 30 seconds, VoicePen shall leave the warming state, mark warmup failed, and allow recording to retry the model later.
- VoicePen shall treat bundled local ASR models as timestamp-capable and route timestamp requests through the selected backend.
- When proxy settings exist in the local environment settings file, VoicePen shall use them for model downloads.
- When diagnostics are copied, VoicePen shall report installed state, language support, timestamp support, backend/source, version, size, and artifact status.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Missing saved model | Unknown selected model id | Recommended model is selected |
| Model picker | User opens Model settings | Model choices include Whisper `q5_0`, `q5_1`, `q8_0`, and Experimental Speaker Turns options |
| Model language detail | User selects any bundled model | Model details show Multilingual or English only |
| Recognition help | User hovers a question-mark icon beside Primary language | The explanation appears and mentions that a single selected language can be faster than auto-detect |
| Meeting feature support | User opens Model settings | Meeting timecode and diarization toggles appear in Meeting features without duplicate Available rows |
| Model settings bottom text | User opens Model settings | The view does not add an extra bottom text-only explanatory section |
| Whisper.cpp artifact missing | Model exists without Core ML companion | Acceleration is unavailable |
| Blocked download | Network/proxy failure leaves a model file without a completed-download marker | Model remains Missing and Download Model remains available |
| Known download progress | Downloader reports 42% progress | Model settings shows determinate progress at the same fraction |
| Hung model download | Downloader never completes | VoicePen exits downloading state and shows a timeout error |
| Hung model warmup | Warmup never completes | VoicePen exits warming state and reports warmup failure |
| Retry after partial success | Main GGML artifact completed but companion download failed | Retry may reuse the completed GGML artifact and continue remaining artifacts |
| Empty artifact | Blocked download leaves an empty GGML file | GGML is not reported ready |
| Proxy configured | `http_proxy` or `https_proxy` in settings | Download uses proxy configuration |

## Test Mapping

- Automated: `VoicePenTests/App/AppControllerTests.swift` covers failed, canceled, and timed-out model downloads leaving the model missing and retryable, plus warmup timeout recovery.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that Model settings renders known download progress as determinate linear progress, shows user-facing model language, timestamp and Meeting feature support, exposes Recognition explanations through help icons, and avoids redundant bottom explanatory text.
- Automated: `VoicePenTests/Transcription/WhisperCppTranscriptionClientTests.swift` covers artifact, acceleration, empty artifact, and completed-download marker checks.
- Automated: `VoicePenTests/Transcription/ModelDownloadProxyConfigurationTests.swift` covers proxy configuration.
- Automated: routing behavior belongs in `VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift` and `VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift` when those files are present.
- Manual: verify a fresh install prompts before downloading model files and can transcribe after required artifacts are installed.

## Notes

Keep backend decisions in routing clients rather than UI code. Keep model metadata in `VoicePen/Resources/model-manifest.json` and artifact path logic in the model/path helpers.

## Open Questions

- None.
