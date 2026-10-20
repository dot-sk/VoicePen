## Purpose

Preserve capture audio in saved recordings so users can inspect the signal before VoicePen software filtering and compare later processing results.

## ADDED Requirements

### Requirement: Saved dictation contains the capture input

When the dictation saved-recordings toggle is enabled, VoicePen SHALL archive exactly one 16 kHz mono captured file per stopped attempt that meets the minimum duration, before RNNoise, voice processing, and silence trimming. It SHALL keep the current microphone capture and input-gain behavior.

#### Scenario: Valid dictation produces processed transcription audio
- **WHEN** a valid dictation produces a derived transcription file
- **THEN** its saved recording contains the captured source file and no derived transcription file.

#### Scenario: Valid dictation cannot be transcribed
- **WHEN** preprocessing, model preparation, or transcription fails after a valid capture
- **THEN** the captured source is still scheduled for saving once.

#### Scenario: Dictation is too short or capture is canceled
- **WHEN** capture yields no recording or a recording below the minimum duration
- **THEN** VoicePen does not schedule saved audio.

### Requirement: Saved meeting contains one unprocessed mix

When the meeting saved-recordings toggle is enabled, VoicePen SHALL save one 16 kHz mono file mixing the captured microphone and system-audio sources, where available, on the meeting timeline. The saved mix SHALL use captured samples before VoicePen noise suppression, per-source leveling, peak scaling, voice processing, and silence trimming. The separately processed transcription input SHALL not be archived.

#### Scenario: Meeting has overlapping and offset sources
- **WHEN** a stopped meeting has microphone and system-audio source chunks
- **THEN** one saved file preserves each source at its captured timeline offset, summing overlapping samples without VoicePen processing effects and limiting only samples that exceed the output format's range.

#### Scenario: One captured source is silent
- **WHEN** either the microphone or system-audio capture contains silence while the other contains sound
- **THEN** the saved mix preserves the active source's level without attenuation from the silent source.

#### Scenario: Meeting processing fails or is canceled after stop
- **WHEN** processing fails or is canceled after capture has stopped
- **THEN** enabled mixing and archiving complete independently of transcription before source cleanup.

#### Scenario: Active meeting capture is canceled
- **WHEN** active capture is canceled without a stopped recording
- **THEN** VoicePen does not create a saved meeting archive.

#### Scenario: Meeting is reprocessed
- **WHEN** retained recovery audio is used to retry processing
- **THEN** VoicePen does not create a duplicate saved meeting mix.

### Requirement: Saved audio publication and retention are complete

VoicePen SHALL publish the complete saved meeting file only after mixing and copying succeed. It SHALL finish the scheduled mix and copy before deleting temporary source files. The existing storage limit SHALL count saved meeting files and dictation files together. Older saved recordings SHALL remain in their existing format until ordinary limit pruning removes them.

#### Scenario: Copy is in progress when processing ends
- **WHEN** meeting processing finishes before source copying
- **THEN** temporary source files remain available until mixing and copying finish, and the complete saved file becomes visible.

#### Scenario: A source cannot be mixed
- **WHEN** any meeting source cannot be mixed into a readable saved file
- **THEN** VoicePen publishes no partial saved file and processing continues.

#### Scenario: Storage limit is exceeded
- **WHEN** archives exceed the configured limit
- **THEN** VoicePen removes oldest saved files until within the limit while retaining newer files when possible.
