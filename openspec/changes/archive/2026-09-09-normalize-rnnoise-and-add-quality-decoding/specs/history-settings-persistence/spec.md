## ADDED Requirements

### Requirement: Local decoding profile persists safely

VoicePen SHALL store the selected local decoding profile in the existing local
SQLite settings store and publish changes through the shared settings path. A
missing or invalid stored value SHALL normalize to the standard greedy profile.

#### Scenario: User changes the decoding profile

- **WHEN** the user selects a supported local decoding profile
- **THEN** VoicePen persists and publishes the selection immediately without requiring an app restart

#### Scenario: VoicePen restarts after profile selection

- **WHEN** VoicePen loads a valid saved local decoding profile
- **THEN** it restores that profile for future local transcription requests

#### Scenario: Stored decoding profile is missing or invalid

- **WHEN** VoicePen loads no decoding profile or an unsupported stored value
- **THEN** it uses the standard greedy profile without blocking settings or transcription
