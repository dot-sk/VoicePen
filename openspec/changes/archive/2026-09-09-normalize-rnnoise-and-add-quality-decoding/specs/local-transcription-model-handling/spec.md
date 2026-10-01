## ADDED Requirements

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
