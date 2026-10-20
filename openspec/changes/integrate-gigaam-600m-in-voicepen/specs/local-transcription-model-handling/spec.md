## ADDED Requirements

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

For the initial GigaAM integration, VoicePen SHALL expose automatic multilingual recognition and greedy CTC with text-only output. It SHALL show forced-language selection, beam-search decoding, decoder glossary prompting, transcript timecodes, and speaker-label assignment as unavailable for this model. These model-specific restrictions SHALL qualify the existing Whisper-oriented assumptions about language controls, timestamp support, and decoding profiles. Settings and tray-language actions SHALL agree on availability. VoicePen SHALL retain saved preferences for later use with Whisper, identify effective settings separately, and SHALL NOT forward unsupported options to the native backend or claim they were honored.

#### Scenario: Select GigaAM with saved Whisper preferences

- **WHEN** GigaAM becomes selected while a fixed language, maximum-quality decoding, timecodes, or diarization preference is saved
- **THEN** VoicePen preserves those preferences, presents the GigaAM effective automatic/greedy/text-only behavior and unavailable features, and submits no unsupported native options

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
- **THEN** the report identifies the exact model/package, Metal encoder, host CTC head, window policy, and effective greedy/automatic/text-only settings

#### Scenario: GigaAM Metal resources are unavailable

- **WHEN** the required Metal device or packaged resources cannot execute GigaAM
- **THEN** VoicePen surfaces a retryable backend error without a successful fallback transcript or ready state

## MODIFIED Requirements

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
