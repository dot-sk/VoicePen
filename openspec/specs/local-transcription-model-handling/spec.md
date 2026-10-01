# Local Transcription And Model Handling Specification

## Purpose

VoicePen needs usable offline transcription while model files are large, backend-specific, and installed only after user confirmation.

## Requirements

### Requirement: Local Transcription And Model Handling

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen loads a bundled model manifest, presents compatible local models with
plain-language selection names, selects a compatible local model, routes
transcription and downloads by backend, checks required artifacts, supports
proxy settings for model downloads, and reports acceleration diagnostics. It does not
provide cloud fallback transcription, automatic downloads without confirmation,
or public model marketplace behavior.

#### Scenario: Saved selected model is missing or incompatible

- **WHEN** the saved selected model is missing or incompatible
- **THEN** VoicePen shall use the recommended model.

#### Scenario: Shows local transcription model choices

- **WHEN** VoicePen shows local transcription model choices
- **THEN** it shall expose Whisper large-v3 turbo `q5_0`, `q5_1`, and `q8_0` as multilingual options with clear size/quality tradeoffs.

#### Scenario: Shows model details

- **WHEN** VoicePen shows model details
- **THEN** it shall show whether the selected model is multilingual or English-only.

#### Scenario: Shows Recognition controls in Model settings

- **WHEN** VoicePen shows Recognition controls in Model settings
- **THEN** it shall expose each control's explanation through a question-mark help icon next to that control instead of using shared explanatory text below the controls; the Primary language explanation shall mention that choosing a single language can be faster than auto-detect.

#### Scenario: Shows Model settings

- **WHEN** VoicePen shows Model settings
- **THEN** it shall place supported Meeting-only controls in a Meeting features section, including transcript timecodes and Meeting diarization; these controls shall not be duplicated as availability-only rows.

#### Scenario: Shows Meeting feature controls

- **WHEN** VoicePen shows Meeting feature controls
- **THEN** the Meeting timecodes explanation shall describe adding timecodes without implementation-specific segment details, and the Meeting diarization explanation shall describe speaker labels from a separate local diarization model.

#### Scenario: Shows Model settings 2

- **WHEN** VoicePen shows Model settings
- **THEN** it shall avoid redundant bottom explanatory text once model details, actions, feature support, and per-control help are visible.

#### Scenario: Shows the tray menu

- **WHEN** VoicePen shows the tray menu
- **THEN** it shall expose a Recognition Language submenu backed by the same supported language options and persisted setting as Model settings; the selected language shall be visibly marked, and choosing an option shall update the global transcription language for future dictation and Meeting transcription.

#### Scenario: Whisper.cpp model is selected

- **WHEN** a Whisper.cpp model is selected
- **THEN** VoicePen shall require the expected model and Core ML companion artifacts before accelerated transcription.

#### Scenario: Whisper.cpp runs on Apple Silicon

- **WHEN** Whisper.cpp runs on Apple Silicon
- **THEN** VoicePen shall make the packaged Metal kernels discoverable from both the app bundle and SwiftPM runtime bundles so the decoder does not fall back to CPU because of resource lookup.

#### Scenario: Whisper.cpp model is installed by download

- **WHEN** a Whisper.cpp model is installed by download
- **THEN** VoicePen shall treat it as installed only after the full download set validates and a completed-download marker is written.

#### Scenario: Downloads a transcription model

- **WHEN** VoicePen downloads a transcription model
- **THEN** every runtime model URL shall use the dedicated immutable GitHub model-assets release rather than Hugging Face.

#### Scenario: Downloads a transcription model artifact

- **WHEN** VoicePen downloads a transcription model artifact
- **THEN** it shall validate the declared byte size and SHA-256 digest before writing the artifact completion marker.

#### Scenario: Downloaded transcription model artifact is an archive

- **WHEN** a downloaded transcription model artifact is an archive
- **THEN** VoicePen shall extract it into a temporary directory, validate its required contents, and install it atomically so an interrupted extraction cannot replace a working artifact with a partial one.

#### Scenario: Transcription request runs

- **WHEN** a transcription request runs
- **THEN** VoicePen shall route it to the backend that matches the selected model.

#### Scenario: Whisper.cpp decodes audio

- **WHEN** Whisper.cpp decodes audio
- **THEN** VoicePen shall use the default audio context and a conservative thread count of `min(4, processorCount - 2)`, floored at `1`.

#### Scenario: Model download starts

- **WHEN** a model download starts
- **THEN** VoicePen shall route it to the backend-specific downloader.

#### Scenario: Model download progress is known

- **WHEN** model download progress is known
- **THEN** VoicePen shall show the same progress visually in the Model settings progress bar instead of an indeterminate progress animation.

#### Scenario: Startup permissions are granted but the selected local ASR model is not installed

- **WHEN** startup permissions are granted but the selected local ASR model is not installed
- **THEN** VoicePen shall remain in the missing-model state instead of reporting Ready.

#### Scenario: Selected local ASR model is not installed

- **WHEN** the selected local ASR model is not installed
- **THEN** VoicePen shall not start push-to-talk dictation recording.

#### Scenario: Model download fails or is canceled before validation completes

- **WHEN** a model download fails or is canceled before validation completes
- **THEN** VoicePen shall keep the model missing, allow retry without manual deletion, and may reuse artifacts that were individually completed.

#### Scenario: Model download does not complete within the download timeout

- **WHEN** a model download does not complete within the download timeout
- **THEN** VoicePen shall cancel the download, leave the downloading state, keep the model retryable, and surface a timeout error.

#### Scenario: Shall treat bundled local ASR models as timestamp-capable and route timestamp requests through the

- **WHEN** this capability applies
- **THEN** VoicePen shall treat bundled local ASR models as timestamp-capable and route timestamp requests through the selected backend.

#### Scenario: Proxy settings exist in the local environment settings file

- **WHEN** proxy settings exist in the local environment settings file
- **THEN** VoicePen shall use them for model downloads.

#### Scenario: Diagnostics are copied

- **WHEN** diagnostics are copied
- **THEN** VoicePen shall report installed state, language support, timestamp support, backend/source, version, size, and artifact status.

### Requirement: User can select a local decoding profile

VoicePen SHALL expose one global local-decoding profile control in the
Recognition section of Model settings. The control SHALL provide the existing
standard greedy profile and an opt-in maximum-quality profile that uses
multi-candidate beam-search decoding. The selected profile SHALL apply to future
push-to-talk and Meeting transcription requests without changing the selected
model or downloading additional artifacts.

#### Scenario: No decoding profile has been selected

- **WHEN** VoicePen has no valid saved decoding profile
- **THEN** it uses the standard greedy profile to preserve existing recognition latency and behavior

#### Scenario: User selects maximum quality

- **WHEN** the user selects the maximum-quality decoding profile
- **THEN** future push-to-talk and Meeting transcription requests use beam-search decoding with the existing selected model, language, glossary, timestamp, and VAD options

#### Scenario: User selects standard decoding

- **WHEN** the user selects the standard decoding profile
- **THEN** future push-to-talk and Meeting transcription requests use the existing greedy decoding strategy

#### Scenario: Decoding profile changes during transcription

- **WHEN** the user changes the decoding profile while a transcription request is already prepared or decoding
- **THEN** the active request keeps its captured profile and the next prepared request uses the new selection

#### Scenario: Meeting VAD decoding retries without VAD

- **WHEN** a Meeting transcription attempt using the selected decoding profile fails in its VAD decode and retries without VAD
- **THEN** the retry uses the same captured decoding profile

### Requirement: Decoding diagnostics identify the selected profile

VoicePen SHALL identify the captured decoding profile in local transcription
diagnostics and timing results so latency and recognition behavior can be
compared without recording transcript or audio content in logs.

#### Scenario: Local transcription completes or fails

- **WHEN** a local transcription request starts and then completes or fails
- **THEN** its diagnostics identify whether standard greedy or maximum-quality beam-search decoding was used
