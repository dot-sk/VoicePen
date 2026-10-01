## Why

VoicePen always records from the current macOS default microphone. Users with several microphones or audio interfaces need to choose the intended input without changing the system-wide default before each dictation or meeting.

## What Changes

- Add a microphone picker to the existing Audio settings section.
- Offer `System default` alongside the currently available Core Audio input devices.
- Persist a selected device by its stable Core Audio UID and use it for both push-to-talk dictation and Meeting microphone capture.
- Keep `System default` as the default for existing and new installations.
- Refresh the picker when audio devices are connected, disconnected, or renamed.
- Keep an unavailable saved device selected and report it as unavailable instead of silently recording from another microphone.
- Apply dictation input-gain boost to the microphone that dictation will capture.

## Capabilities

### New Capabilities

- `audio-input-selection`: Covers input-device discovery, selection, persistence, availability changes, and routing selected microphone capture.

### Modified Capabilities

- None.

## Impact

- Audio settings UI and the shared settings controller path.
- SQLite-backed app settings.
- Core Audio input-device discovery, observation, and AUHAL device selection.
- Dictation recording, dictation input-gain boost, and Meeting microphone capture.
- Unit tests for settings persistence, device discovery, controller state, capture routing, and gain routing.
- The `audio-input-selection` delta spec must cover persistence compatibility,
  settings behavior, capture routing, device availability, and gain routing
  before production code changes.
