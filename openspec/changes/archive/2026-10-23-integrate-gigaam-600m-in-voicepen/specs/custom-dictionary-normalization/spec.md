## ADDED Requirements

### Requirement: Dictionary prompting respects recognizer capabilities

Dictation and Meetings SHALL preserve their existing dictionary snapshots and deterministic post-recognition replacement rules for GigaAM. The general glossary-prompt contract SHALL be conditional at the native decoder boundary: only a recognizer supporting prompting SHALL receive a decoder glossary prompt. GigaAM SHALL use dictionary replacements after recognition without receiving an unsupported native prompt or claiming contextual vocabulary biasing.

#### Scenario: GigaAM recognizes a configured dictionary variant

- **WHEN** GigaAM dictation or Meeting recognition returns a configured variant
- **THEN** VoicePen applies the existing local canonical replacement before insertion or saving and sends no glossary prompt to the GigaAM native decoder

#### Scenario: Switch to Whisper with the same dictionary

- **WHEN** the same dictionary is used for a later Whisper request
- **THEN** its supported glossary prompting and existing post-recognition normalization both remain available
