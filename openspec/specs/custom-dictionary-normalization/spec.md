# Custom Dictionary Normalization Specification

## Purpose

Technical dictation often produces phonetically correct but textually wrong terms, especially for product names, technologies, and mixed-language vocabulary.

## Requirements

### Requirement: Custom Dictionary Normalization

VoicePen SHALL preserve the behavior contract for this capability.

Dictionary entries contain a canonical form and variants. VoicePen imports entries from CSV, stores them locally, builds glossary prompts for dictation and Meeting transcription, filters entries, and normalizes transcribed text with configured variants. CSV import requires every parsed entry to have a canonical form and at least one variant. It does not provide cloud dictionary sync, grammar rewriting, or semantic post-processing beyond configured term replacements.

#### Scenario: CSV input contains canonical,variants

- **WHEN** CSV input contains `canonical,variants`
- **THEN** VoicePen shall import canonical terms and split variants on semicolons.

#### Scenario: CSV input contains any parsed entry without at least one non-empty variant

- **WHEN** CSV input contains any parsed entry without at least one non-empty variant
- **THEN** VoicePen shall reject the entire import without changing the existing dictionary.

#### Scenario: Dictionary entries are edited

- **WHEN** dictionary entries are edited
- **THEN** VoicePen shall store, load, replace, and filter them locally.

#### Scenario: Seeds sample dictionary entries for a fresh local database

- **WHEN** VoicePen seeds sample dictionary entries for a fresh local database
- **THEN** it shall do so only once; if the user later deletes all dictionary entries, subsequent loads shall keep the dictionary empty.

#### Scenario: User clicks Add in the dictionary editor

- **WHEN** the user clicks Add in the dictionary editor
- **THEN** VoicePen shall open an empty editable term draft on the first click even if another term was selected.

#### Scenario: Prompt glossary is built

- **WHEN** a prompt glossary is built
- **THEN** VoicePen shall produce deterministic, language-aware output that respects configured limits.

#### Scenario: Valid dictation recording is transcribed

- **WHEN** a valid dictation recording is transcribed
- **THEN** VoicePen shall build and pass the glossary prompt regardless of recording duration.

#### Scenario: Meeting transcription or retry starts

- **WHEN** Meeting transcription or retry starts
- **THEN** VoicePen shall snapshot the current dictionary once and pass its language-aware glossary prompt to the complete-master local ASR request.

#### Scenario: Transcribed text contains configured variants

- **WHEN** transcribed text contains configured variants
- **THEN** VoicePen shall replace them with canonical terms while preserving unrelated text.

#### Scenario: Meeting transcription contains configured variants

- **WHEN** Meeting transcription contains configured variants
- **THEN** VoicePen shall normalize recognized content before saving while preserving transcript timecodes and speaker labels.

#### Scenario: Dictionary data is empty or invalid

- **WHEN** dictionary data is empty or invalid
- **THEN** VoicePen shall fail predictably without corrupting existing data.
