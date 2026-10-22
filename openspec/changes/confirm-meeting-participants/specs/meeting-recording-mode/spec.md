## ADDED Requirements

### Requirement: Meeting participant labels require participation evidence

VoicePen SHALL distinguish detected voices from confirmed participants before transcript speaker assignment and saved speaker counting. Confirmation SHALL consider accumulated usable speech and independent contributions rather than promoting a voice solely because one short region has a new identity. Unconfirmed speech SHALL retain its recognized text without a participant label or reassignment to another participant.

#### Scenario: Isolated background interjection

- **WHEN** an otherwise established conversation contains an additional voice supported only by a brief background event
- **THEN** that voice does not create a participant label or increase the saved participant count
- **AND** recognized text from that event remains available without a speaker attribution

#### Scenario: Fragmented background event

- **WHEN** the diarizer splits one brief background event into several adjacent turns with the same identity
- **THEN** those fragments do not independently satisfy the repeated-contribution criterion

#### Scenario: Repeated substantive participation

- **WHEN** a distinct voice contributes sufficient usable speech in independent conversational turns
- **THEN** VoicePen retains it as a participant even if other participants speak much more
- **AND** it is not removed solely because its share of total meeting duration is small

#### Scenario: Short single-speaker recording

- **WHEN** a short recording has one usable speaking voice without competing speaker identities
- **THEN** VoicePen retains its speaker attribution without requiring repeated exchanges

#### Scenario: No candidate qualifies

- **WHEN** diarization returns multiple uncertain voices and none meets the confirmation policy
- **THEN** VoicePen preserves the transcript without inventing participants
- **AND** saves no detected participant count rather than a fabricated count

#### Scenario: Labels and count use the same confirmed identities

- **WHEN** a newly processed meeting is saved after participant confirmation
- **THEN** its saved count and assigned speaker labels refer to the same confirmed participant set
- **AND** a raw backend speaker roster does not restore rejected candidates

#### Scenario: Existing saved meeting is not reprocessed

- **WHEN** an existing meeting is read without an explicit processing retry
- **THEN** its saved transcript and speaker count remain unchanged
