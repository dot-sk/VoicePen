# Local Transcription And Model Handling Specification

## Purpose

VoicePen needs usable offline transcription while model files are large, backend-specific, and installed only after user confirmation.

## Requirements

### Requirement: Local Transcription And Model Handling

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen loads a bundled model manifest, presents compatible local models with
plain-language selection names, selects a compatible local model, routes
transcription and downloads by backend, checks required artifacts, supports
proxy settings for model downloads, retires obsolete model selections and
app-managed downloads, and reports acceleration diagnostics. It does not
provide cloud fallback transcription, automatic downloads without confirmation,
or public model marketplace behavior.

#### Scenario: Saved selected model is missing or incompatible

- **WHEN** the saved selected model is missing or incompatible
- **THEN** VoicePen shall use and persist the recommended model.

#### Scenario: Shows local transcription model choices

- **WHEN** VoicePen shows local transcription model choices
- **THEN** it shall expose Whisper large-v3 turbo `q5_0` and `q8_0` as multilingual options with clear size and quality tradeoffs.

#### Scenario: Saved Q5_1 selection exists after upgrade

- **WHEN** VoicePen starts after an earlier version saved `q5_1` as the selected transcription model
- **THEN** it shall select and persist the recommended `q5_0` model for future push-to-talk and Meeting transcription.

#### Scenario: Downloaded Q5_1 model exists after upgrade

- **WHEN** VoicePen starts with an app-managed `q5_1` model directory
- **THEN** it shall remove that retired model directory without removing `q5_0`, `q8_0`, saved recordings, or other user data.

#### Scenario: Downloaded Q5_1 cleanup fails

- **WHEN** VoicePen cannot remove an app-managed `q5_1` model directory during startup
- **THEN** it shall keep `q5_0` selected, continue startup, log the cleanup failure, and retry cleanup on a later launch.

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
- **THEN** VoicePen shall require the validated selected weights for readiness without requiring, validating, compiling, or loading a Core ML ASR companion.

#### Scenario: Whisper.cpp runs on Apple Silicon

- **WHEN** Whisper.cpp runs on Apple Silicon
- **THEN** both ASR encoder and decoder shall use Metal, including when legacy Core ML encoder files remain installed, with packaged kernels discoverable from app and SwiftPM runtime bundles.

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
- **THEN** VoicePen shall report installed state, language support, timestamp support, backend/source, version, size, required artifact status, and actual ASR encoder/decoder acceleration without treating a legacy Core ML companion as required or inferring execution from compiled-in features.

### Requirement: User can select a local decoding profile

VoicePen SHALL expose one global local-decoding profile control in the
Recognition section of Model settings. For a model supporting configurable
decoding, the control SHALL provide the existing standard greedy profile and an
opt-in maximum-quality profile that uses multi-candidate beam-search decoding.
The selected preference SHALL apply to future push-to-talk and Meeting requests
when supported, without changing the selected model or downloading additional
artifacts. For GigaAM, the control SHALL show effective greedy CTC as fixed and
retain the saved preference for models that support it.

#### Scenario: No decoding profile has been selected

- **WHEN** VoicePen has no valid saved decoding profile
- **THEN** it uses the standard greedy profile to preserve existing recognition latency and behavior

#### Scenario: User selects maximum quality

- **WHEN** the user selects the maximum-quality decoding profile for a model supporting beam search
- **THEN** future push-to-talk and Meeting transcription requests use beam-search decoding with the existing selected model, language, glossary, timestamp, and VAD options

#### Scenario: User selects standard decoding

- **WHEN** the user selects the standard decoding profile for a model supporting configurable decoding
- **THEN** future push-to-talk and Meeting transcription requests use the existing greedy decoding strategy

#### Scenario: Decoding profile changes during transcription

- **WHEN** the user changes the decoding profile while a transcription request is already prepared or decoding
- **THEN** the active request keeps its captured effective profile and the next prepared request resolves the new selection against its model capabilities

#### Scenario: Meeting VAD decoding retries without VAD

- **WHEN** a Meeting transcription attempt using a model with VAD decoding fails in its VAD decode and retries without VAD
- **THEN** the retry uses the same captured effective decoding profile

### Requirement: Decoding diagnostics identify the selected profile

VoicePen SHALL identify the captured effective local decoding profile in
transcription diagnostics and timing results so latency and recognition behavior
can be compared without recording transcript or audio content in logs. When
model capabilities constrain a saved preference, diagnostics SHALL distinguish
the saved preference from the effective decoding mode.

#### Scenario: Local transcription completes or fails

- **WHEN** a local transcription request starts and then completes or fails
- **THEN** its diagnostics identify the effective decoding mode and any saved profile preference that could not apply to the captured model

### Requirement: Existing Whisper weights migrate without another download

VoicePen SHALL reuse valid existing Whisper weights and completion state when switching to Metal-only ASR. Legacy Core ML ASR companions SHALL not affect readiness or execution. Unrelated model files and separate Meeting diarization assets SHALL remain intact.

#### Scenario: Valid Whisper weights exist without an encoder companion

- **WHEN** VoicePen starts with valid installed Whisper weights and no Core ML encoder
- **THEN** the selected model is installed and can prepare Metal ASR without another download or a change to the saved model selection

#### Scenario: Legacy encoder files remain beside the weights

- **WHEN** valid Whisper weights and legacy Core ML encoder files are both present
- **THEN** VoicePen uses the same weights through Metal ASR and leaves those legacy files and diarization assets untouched

#### Scenario: Whisper installation is new or incomplete

- **WHEN** the user installs Whisper or resumes an interrupted installation
- **THEN** the required download set contains the selected weights only, preserves verified-artifact reuse, and marks readiness only after required validation completes

### Requirement: Metal ASR availability is explicit

VoicePen SHALL surface Metal initialization failures rather than silently execute Whisper ASR on CPU or report the model ready without the required acceleration.

#### Scenario: Metal ASR cannot initialize

- **WHEN** the selected model's Metal encoder or decoder cannot initialize because the GPU or packaged kernels are unavailable
- **THEN** VoicePen reports an actionable initialization error and allows retry through the existing model-loading path without claiming successful CPU ASR as Metal execution

### Requirement: GigaAM effective timing capability is distinct from native timestamp output

VoicePen SHALL allow Meeting timecodes and speaker labeling with GigaAM when its accepted native package provides aligned token positions, while continuing to report that the native backend has no direct segment or word timestamp output. Unsupported GigaAM decoding controls SHALL remain unavailable.

#### Scenario: GigaAM selected with saved Meeting timing preferences

- **WHEN** GigaAM is selected and Meeting timecodes or diarization are enabled
- **THEN** those preferences are effective for new Meeting recognition requests without enabling forced language, decoder prompting, beam search, or VAD

#### Scenario: GigaAM dictation without timing request

- **WHEN** push-to-talk dictation uses GigaAM without a timing request
- **THEN** it returns the same recognized text without additional alignment processing or speaker analysis

### Requirement: Bundled Whisper runtime upgrades preserve installed transcription features

VoicePen SHALL reuse valid installed supported Whisper weights and completion state across a bundled runtime upgrade. Transcription SHALL preserve Metal encoder and decoder execution, optional timestamps, and usable word confidence evidence. Execution diagnostics SHALL identify the bundled runtime version.

#### Scenario: Existing quantized model is used after a runtime upgrade

- **WHEN** a user with valid installed supported Q5 or Q8 Whisper weights transcribes after a bundled runtime upgrade, including an installation with legacy Core ML companions
- **THEN** VoicePen uses those weights with Metal encoder and decoder, returns transcription and confidence evidence, and reports the updated runtime identity without requiring another download

#### Scenario: Timestamped transcription uses the upgraded runtime

- **WHEN** a transcription request asks for timestamps using the upgraded bundled Whisper runtime
- **THEN** VoicePen returns timestamped segments and word confidence evidence from that runtime

#### Scenario: Other local ASR backend remains available

- **WHEN** Whisper and GigaAM are loaded in the same process after a Whisper runtime upgrade
- **THEN** both backends can transcribe with their own packaged runtime and confidence evidence

### Requirement: GigaAM reads the complete prepared audio input

GigaAM SHALL receive every sample in the prepared recording, including a final
short file-read buffer. File decoding SHALL continue until the declared input
frames have been read or an explicit read error is reported. The adapter SHALL
report the actual number of submitted samples and SHALL NOT treat a short
individual file read as the end of a complete recording.

#### Scenario: Prepared audio requires several partial reads

- **WHEN** the file reader returns fewer frames than requested while prepared audio remains
- **THEN** VoicePen continues reading and submits the complete ordered input once, including its final samples, without padding or another preprocessing pass

### Requirement: GigaAM is an optional selectable local model

VoicePen SHALL offer the accepted GigaAM Multilingual 600M F16 model in the existing local-model selector on supported Apple Silicon systems. Selection SHALL use the shared persistent settings path. Adding GigaAM SHALL preserve valid existing selections, the recommended Whisper model, and installed Whisper artifacts. Missing GigaAM weights SHALL remain a missing-model state, not an incompatible selection or a reason to download automatically.

#### Scenario: Select GigaAM in Model settings

- **WHEN** a user selects GigaAM Multilingual 600M F16 from the existing model selector
- **THEN** VoicePen persists that selection, shows its actual model details and installation state, and uses it for future prepared transcription requests

#### Scenario: Restart with a valid GigaAM selection

- **WHEN** VoicePen restarts with a valid saved GigaAM selection whose weights are missing
- **THEN** it retains that selection, reports the model as missing, and requires confirmed installation before dictation can start

#### Scenario: Upgrade with an existing Whisper selection

- **WHEN** an existing user starts the version that adds GigaAM
- **THEN** the valid Whisper selection, recommended model, and installed Whisper files remain unchanged

### Requirement: GigaAM installation uses verified model delivery

GigaAM SHALL use the existing confirmed local-model download lifecycle, proxy configuration, progress, cancellation, timeout, and retry behavior. The distributable manifest SHALL identify the accepted immutable model-assets release URL, exact size, and SHA-256. Installation SHALL become ready only after verification and atomic completion. Partial, canceled, or corrupt downloads SHALL remain retryable without deleting other models. Deleting GigaAM SHALL release its idle native resources and remove only its app-managed files; deletion SHALL be unavailable while those files are in use.

#### Scenario: Install the selected GigaAM model

- **WHEN** a user confirms downloading the selected GigaAM model
- **THEN** VoicePen downloads through configured proxies, reports progress, validates the immutable artifact, and marks only the completed installation as available for loading

#### Scenario: GigaAM download fails verification or is interrupted

- **WHEN** the download is canceled, times out, fails, or has the wrong size or digest
- **THEN** VoicePen leaves no ready partial installation, surfaces the appropriate outcome, and permits retry without changing another model's installation

#### Scenario: Delete GigaAM safely

- **WHEN** the user requests removal of GigaAM files
- **THEN** VoicePen prevents removal during active use or installation, releases an idle loaded GigaAM context before deletion, and leaves the selected model missing without removing Whisper or history

#### Scenario: Prepare and publish immutable GigaAM assets

- **WHEN** the GigaAM model assets are prepared for a separately authorized publication
- **THEN** the review plan identifies the exact model and license/provenance archive bytes, hashes and new release coordinates, and the publisher refuses to replace an existing release or its assets

#### Scenario: Published GigaAM assets fail readback

- **WHEN** either public asset cannot be downloaded with its declared size and digest
- **THEN** publication tooling does not emit a verified downloadable model entry or activate the bundled manifest, and readback can be retried without replacing published assets

### Requirement: GigaAM controls describe effective recognition capabilities

VoicePen SHALL expose automatic multilingual recognition and greedy CTC for GigaAM. Forced-language selection, beam-search decoding, decoder glossary prompting and VAD SHALL remain unavailable. Meeting timecodes and speaker labeling SHALL use the effective timing capability when aligned token positions are available. Settings and tray-language actions SHALL agree on availability. VoicePen SHALL retain saved preferences for supported models and identify effective settings separately without forwarding unsupported native options.

#### Scenario: Select GigaAM with saved Whisper preferences

- **WHEN** GigaAM becomes selected while a fixed language, maximum-quality decoding, timecodes, or diarization preference is saved
- **THEN** VoicePen preserves those preferences, uses automatic multilingual greedy CTC, applies supported Meeting timing preferences, and submits no unsupported native options

#### Scenario: Return to Whisper

- **WHEN** the user switches from GigaAM back to an installed Whisper model
- **THEN** the saved language, decoding profile, timecodes, and diarization preferences become effective again through their existing shared settings path

#### Scenario: Bundled model metadata disagrees with the runtime

- **WHEN** the GigaAM model identity, required capabilities, or package compatibility does not match the accepted installation
- **THEN** VoicePen reports an incompatible model or backend and does not mark the model ready or substitute another recognizer

### Requirement: GigaAM diagnostics identify actual local execution

GigaAM diagnostics SHALL identify the model and package versions, installation status, effective recognition settings, window policy, and actual stage placement. Required Metal failure SHALL surface as an error without CPU-encoder, Whisper, or cloud fallback. Routine logs SHALL contain no transcript or audio content.

#### Scenario: Copy diagnostics after GigaAM recognition

- **WHEN** the user copies model diagnostics after GigaAM runs
- **THEN** the report identifies the exact model/package, Metal encoder, host CTC head, window policy, and effective greedy/automatic settings and timing capability

#### Scenario: GigaAM Metal resources are unavailable

- **WHEN** the required Metal device or packaged resources cannot execute GigaAM
- **THEN** VoicePen surfaces a retryable backend error without a successful fallback transcript or ready state
