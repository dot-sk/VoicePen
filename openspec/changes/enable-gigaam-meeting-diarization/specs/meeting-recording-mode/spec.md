## ADDED Requirements

### Requirement: GigaAM Meeting recordings support timing-based speaker labeling

When Meeting timing or speaker labeling is enabled, VoicePen SHALL derive usable word positions from the selected GigaAM recognition result and use the existing local Meeting speaker analysis to produce timecodes or speaker-labeled text. It SHALL NOT run a second recognizer or infer speech timing from fixed processing-window boundaries. This supersedes the initial text-only GigaAM Meeting limitation.

#### Scenario: GigaAM Meeting with two detected speakers

- **WHEN** GigaAM supplies valid aligned words for a Meeting and the local diarizer identifies two speakers
- **THEN** VoicePen saves the transcript with both speaker labels and a speaker count of two

#### Scenario: GigaAM Meeting requests timecodes without speaker labels

- **WHEN** a GigaAM Meeting has transcript timecodes enabled and diarization disabled
- **THEN** VoicePen formats the recognized speech with timecodes without running speaker analysis

#### Scenario: Aligned word timing is unavailable

- **WHEN** GigaAM returns text but no valid word alignment
- **THEN** VoicePen retains the recognized text and does not invent speaker labels or timestamps

#### Scenario: Retry a saved GigaAM Meeting

- **WHEN** a previously text-only GigaAM Meeting still has retained recovery audio and is retried with speaker labeling enabled
- **THEN** VoicePen can regenerate the transcript and speaker count from that audio without changing unrelated history entries
