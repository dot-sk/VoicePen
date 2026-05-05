---
id: SPEC-012
status: implemented
updated: 2026-05-05
tests:
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/Recording/DefaultInputGainControllerTests.swift
---

# Audio Settings And Voice Processing

## Problem

VoicePen should make audio capture more reliable without asking users to
understand macOS audio routing or local transcription model behavior.

## Behavior

VoicePen keeps using the macOS default microphone. It provides audio controls in
Config settings with two independent best-effort controls: boosting default
microphone input level during push-to-talk dictation, and applying system voice
leveling to Meeting Mode audio before local transcription.

## Acceptance Criteria

- When VoicePen shows settings, it shall not include a dedicated Audio sidebar section.
- When VoicePen shows Config settings, it shall include audio controls for dictation microphone boost and Meeting voice leveling.
- When no audio settings have been saved, VoicePen shall enable dictation microphone boost and Meeting voice leveling by default.
- When push-to-talk dictation starts and microphone boost is enabled, VoicePen shall attempt to set the current default input device's settable input volume to maximum before recording.
- When dictation recording ends, is canceled, fails to start, times out, or fails during processing, VoicePen shall attempt to restore the original input volume it changed.
- When the default input device does not expose settable input volume, VoicePen shall continue recording without surfacing a blocking error.
- VoicePen shall not apply microphone boost to Meeting Mode recordings.
- When Meeting voice leveling is enabled, VoicePen shall process each Meeting Mode audio chunk through system dynamics and peak limiting before local transcription.
- When Meeting voice leveling cannot be applied, VoicePen shall continue transcription with the un-leveled preprocessed audio and log a diagnostic note rather than failing the meeting.
- VoicePen shall not change or overwrite raw temporary audio or retained recovery audio when applying Meeting voice leveling.
- VoicePen shall delete temporary voice-leveled chunk files after transcription succeeds or fails.
- VoicePen shall not add microphone source selection in this iteration.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Dictation boost | Push-to-talk starts with boost enabled | Default input gain is set to maximum while recording and restored afterward |
| Unsupported input gain | Device has no settable input volume | Dictation still records normally |
| Meeting leveling | Meeting chunk has uneven voice levels | Chunk is rendered through system dynamics and limiter before transcription |
| Leveling failure | Audio Unit effect creation fails | Meeting transcribes the ordinary preprocessed chunk and logs a diagnostic note |

## Test Mapping

- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers audio setting defaults and persistence.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers audio controls living in Config settings and shared settings bindings.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers dictation microphone boost lifecycle and best-effort failures.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers Meeting voice leveling routing, fallback, and processed temporary file cleanup.
- Automated: `VoicePenTests/Recording/DefaultInputGainControllerTests.swift` covers input gain set/restore behavior with fake CoreAudio.
- Manual: enable dictation boost, record, and verify macOS input level rises during recording and restores afterward on supported devices.
- Manual: record a meeting with uneven speakers and compare transcription quality with Meeting voice leveling on and off; verify that the system Audio Unit chain creates a processed temporary file on the local Mac.

## Notes

Use Apple system Audio Units for Meeting voice leveling. Keep both audio
features best-effort: audio capture and transcription should continue if the
system cannot expose input gain or render the voice-leveling chain.

## Open Questions

- None.
