## ADDED Requirements

### Requirement: Nemotron English is an optional local recognizer

VoicePen SHALL offer Nemotron Speech English 0.6B in the existing persistent model selector. It SHALL preserve existing valid selections, the recommended Whisper model and other installed models. Nemotron SHALL use fixed English greedy RNNT recognition without decoder glossary prompting, configurable decoding, VAD or timestamp output. Saved preferences for other models SHALL remain intact. This model-specific capability contract supersedes the general bundled timestamp-capability clause for Nemotron.

#### Scenario: Select Nemotron with saved multilingual preferences

- **WHEN** the user selects Nemotron while another recognition language or decoding profile is saved
- **THEN** the model selection persists and future requests use English greedy RNNT while settings, tray actions and diagnostics show the effective capabilities without overwriting saved preferences

#### Scenario: Restart or switch away from Nemotron

- **WHEN** VoicePen restarts with a missing Nemotron installation or the user selects another recognizer
- **THEN** the missing Nemotron selection is retained until installation or the other recognizer's saved preferences become effective respectively

### Requirement: Nemotron installation uses verified immutable upstream files

Nemotron SHALL use the existing confirmed, proxy-aware model download, progress, cancellation, timeout and retry lifecycle. As a model-specific exception to GitHub-only ASR delivery, its files SHALL come from a bundled immutable upstream Hugging Face revision with exact sizes and SHA-256 digests. Readiness SHALL require the complete revision-compatible installation. Failed, canceled or corrupt downloads SHALL remain retryable. Deletion SHALL release idle model resources, reject active use and remove only that model's managed installation.

#### Scenario: Install Nemotron

- **WHEN** the user confirms installing Nemotron
- **THEN** VoicePen verifies every required file and records the completed installation identity before reporting readiness

#### Scenario: Installation is partial or incompatible

- **WHEN** required files are missing, the installation identity differs, or a download fails verification or is canceled
- **THEN** VoicePen reports the model as missing or incompatible, permits retry and preserves other models

#### Scenario: Delete Nemotron

- **WHEN** deletion is requested while the model is idle or has an active prepared request
- **THEN** idle resources and managed files can be released, while active use prevents deletion
