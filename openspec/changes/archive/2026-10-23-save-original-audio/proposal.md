## Why

Saved recordings currently contain audio after VoicePen processing. That loses the source signal needed to compare transcription and audio processing changes.

## What Changes

- Save a valid dictation's captured 16 kHz mono audio before VoicePen filters, including failed transcription attempts.
- Save one meeting file mixed from captured sources on their shared timeline before VoicePen noise suppression, source leveling, peak scaling, voice processing, and silence trimming.
- Finish mixing and copying before temporary capture files are removed.
- Keep the existing opt-in toggles and storage limit. Leave older archives untouched.

## Capabilities

### New Capabilities

- `saved-original-audio`: Defines the contents, lifecycle, and retention of saved capture audio.

### Modified Capabilities

None. Existing audio and history capabilities keep their other behavior. Superseded archive clauses in their main specs are reconciled alongside the new capability.

## Impact

DictationPipeline, MeetingPipeline, SavedAudioArchive, saved-recording settings copy, and focused Swift tests. No database migration or new dependency.
