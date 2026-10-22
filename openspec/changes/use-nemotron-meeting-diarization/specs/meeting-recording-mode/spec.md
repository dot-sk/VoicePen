## ADDED Requirements

### Requirement: Meeting diarization uses Nemotron offline

VoicePen SHALL use Nemotron-3 offline through a pinned native Core ML runtime as its sole meeting diarization backend. This supersedes the SpeakerKit backend, GitHub-archive installation and automatic diarization warmup clauses in Meeting Recording Mode. The existing full-timeline input, transcript assignment, turn postprocessing and graceful failure contracts remain in force. VoicePen SHALL NOT force a supplied participant count or introduce new voice-merging heuristics in this migration.

#### Scenario: Fresh and legacy backend preferences

- **WHEN** settings are created or loaded with a current, legacy SpeakerKit, pyannote, sortformer or invalid backend value
- **THEN** subsequent processing uses the sole Nemotron offline backend without a backend selector
- **AND** existing saved meeting text and speaker counts remain unchanged until an explicit retry

#### Scenario: Verified model installation through the configured proxy

- **WHEN** a user downloads the diarization model
- **THEN** VoicePen downloads an immutable, bundled list of compiled Nemotron offline files through its configured model-download proxy, verifying each size and SHA-256
- **AND** only the complete verified installation replaces the managed diarization directory, including any obsolete SpeakerKit artifacts

#### Scenario: Download failure or cancellation

- **WHEN** an artifact fails verification or a download is canceled
- **THEN** no new completion marker is published and the previous installation is preserved
- **AND** a retry can complete a verified installation

#### Scenario: Existing SpeakerKit installation

- **WHEN** only old SpeakerKit artifacts are installed
- **THEN** VoicePen reports Nemotron as not installed and offers the existing model-download workflow
- **AND** no analysis silently falls back to SpeakerKit

#### Scenario: Local inference across a long meeting

- **WHEN** a successfully installed model analyzes successive portions of one full 16 kHz mono meeting timeline
- **THEN** inference performs no network downloads and carries the same recording's speaker state between portions
- **AND** speaker state is reset before a different recording, timeline coordinates are preserved, and the recording tail is retained

#### Scenario: Cancellation, reset and retry during inference

- **WHEN** inference is canceled or its runtime is reset
- **THEN** processing stops at an inference boundary, releases request-owned state and permits a later analysis without reusing speaker history from the interrupted recording

#### Scenario: Missing or corrupt installed files

- **WHEN** required files or the current completion marker are missing, or native model loading fails
- **THEN** VoicePen surfaces the existing not-installed or model-load failure state and retains the recognized transcript if diarization cannot complete

#### Scenario: VoicePen distribution

- **WHEN** the application is built for distribution
- **THEN** it uses the FluidAudio Nemotron implementation without linking SpeakerKit, WhisperKit or ArgmaxCore, without Python/PyTorch, and without FluidAudio's optional native text-normalization engine

#### Scenario: Installed diarization model remains unloaded while idle

- **WHEN** VoicePen starts, diarization is enabled, or a diarization model download completes
- **THEN** installed-file status remains available without automatically loading the diarization runtime
- **AND** the runtime is loaded on demand for analysis, while the next analysis can reload the local model

#### Scenario: Analysis finishes, fails or is canceled

- **WHEN** the final active diarization operation completes successfully, fails or is canceled
- **THEN** VoicePen immediately releases its retained diarization runtime and model references without an idle retention timer
- **AND** explicit diagnostic warmup also releases its runtime after validation

#### Scenario: Concurrent operations share the loaded runtime safely

- **WHEN** one diarization operation finishes while another is still loading or processing
- **THEN** completion of the first operation does not unload or invalidate the second operation's runtime
- **AND** the runtime is released after the last active operation completes
