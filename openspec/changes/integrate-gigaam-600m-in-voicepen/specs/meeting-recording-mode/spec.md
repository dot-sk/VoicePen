## ADDED Requirements

### Requirement: Meetings use the selected recognizer with supported features

Meeting processing and retry SHALL capture the current model and effective options once and submit the complete mastered recording through the shared application recognizer routing service. The existing Whisper-specific shared-client contract SHALL apply to Whisper requests; GigaAM SHALL share its own serialized backend service with dictation. GigaAM internal windows SHALL remain runtime-owned, without application text-chunk merging or silent duration truncation.

For initial GigaAM text-only support, the general timestamp request and diarization behavior SHALL apply only when the selected model provides the required timing capability. VoicePen SHALL show timecodes and speaker labels as unavailable for GigaAM, retain their saved preferences, suppress unsupported native timing and VAD options, and skip speaker analysis requiring transcript timestamps. It SHALL still process and save plain Meeting text with actual model/app metadata, preserve recovery/retry behavior, and never auto-paste Meeting output. It SHALL NOT invent timing from runtime window boundaries.

#### Scenario: Process a complete Meeting with GigaAM

- **WHEN** an installed GigaAM model is selected for a Meeting processing run
- **THEN** one complete-master local request produces saved plain text with GigaAM/app metadata, without app-owned ASR chunks, synthetic timecodes, or automatic insertion

#### Scenario: GigaAM is selected with Meeting timing preferences enabled

- **WHEN** saved Meeting timecodes or diarization preferences are enabled while GigaAM is selected
- **THEN** VoicePen presents their unavailability, preserves the preferences, and completes text-only recognition without requesting unsupported timing/VAD or running timestamp-dependent speaker assignment

#### Scenario: Retry a Meeting after selecting another recognizer

- **WHEN** the user retries recoverable Meeting audio after changing between Whisper and GigaAM
- **THEN** the retry captures the newly selected model and its effective capabilities, updates result metadata for that run, and preserves recovery audio and history rules

#### Scenario: Cancel GigaAM Meeting processing while dictation is waiting

- **WHEN** the user cancels a GigaAM Meeting request while dictation is queued on that backend
- **THEN** only the canceled request aborts, recovery audio remains retryable, no late Meeting success is saved, and the queued dictation can proceed after native execution is released
