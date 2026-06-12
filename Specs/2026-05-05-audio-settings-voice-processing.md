---
id: SPEC-012
status: implemented
updated: 2026-06-11
tests:
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/App/AppPathsTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/Recording/DefaultAudioInputDeviceProviderTests.swift
  - VoicePenTests/Recording/DefaultInputGainControllerTests.swift
  - VoicePenTests/Recording/ActiveChannelMonoMixerTests.swift
  - VoicePenTests/Recording/CoreAudioMicrophoneCaptureTests.swift
---

# Audio Settings And Voice Processing

## Problem

VoicePen should make audio capture more reliable without asking users to
understand macOS audio routing or local transcription model behavior.

## Behavior

VoicePen keeps using the macOS default microphone and shows the current system
default microphone in Settings. It provides audio controls in the Settings
screen for dictation microphone boost, Meeting voice leveling, and saved
recordings. Push-to-talk dictation and Meeting microphone capture run on
low-level input-only AUHAL with idle preparation and must not change output
playback volume, mute, or routing state.

## Acceptance Criteria

- When VoicePen shows settings, it shall not include a dedicated Audio sidebar section.
- When VoicePen shows the Settings screen, it shall include a read-only status for the current macOS default microphone plus audio controls for dictation microphone boost, Meeting voice leveling, saved dictation recordings, saved Meeting recordings, saved-audio storage limit, and opening the saved recordings folder.
- When macOS exposes a current default microphone name, the Audio settings status shall display `Current microphone: System default (<device name>)`.
- When the current default microphone name cannot be read, the Audio settings status shall display `Current microphone: System default` without presenting an error state or unavailable wording.
- When the macOS default input device changes while VoicePen is running, the Audio settings status shall update to the new system default microphone.
- When no audio settings have been saved, VoicePen shall enable dictation microphone boost and Meeting voice leveling by default.
- When no saved-recordings settings have been saved, VoicePen shall keep saved dictation recordings and saved Meeting recordings disabled by default.
- Saved recordings shall be scheduled asynchronously for dictation and Meeting Mode, copied byte-for-byte, keep the source file extension, use readable date/time/source filenames, and be pruned oldest-first across dictation and Meeting saved audio when the configured total size cap is exceeded.
- Saved dictation recordings shall schedule one audio file per valid dictation attempt, using the transcription input file when preprocessing creates one and the original recording otherwise.
- Saved recording copy or pruning failures shall be logged asynchronously and shall not change dictation transcription, insertion, retry, or history behavior, or Meeting transcription, retry, recovery audio, or history behavior.
- Saved recordings shall be stored under Application Support, not temporary audio storage, and stale temporary-audio cleanup shall not remove them.
- When push-to-talk dictation starts and microphone boost is enabled, VoicePen shall attempt to set the current default input device's settable input volume to maximum before recording.
- When dictation recording ends, is canceled, fails to start, times out, or fails during processing, VoicePen shall attempt to restore the original input volume it changed.
- When the default input device does not expose settable input volume, VoicePen shall continue recording without surfacing a blocking error.
- Dictation and Meeting microphone capture shall use input-only AUHAL with output disabled and must not call `setVoiceProcessingEnabled` or `VoiceProcessingIO`.
- Dictation idle prepare and start shall use AUHAL input-only capture: `prepare()` shall create/configure/initialize capture units without starting, and `start()` must start capture.
- When the default input device exposes multiple input channels, VoicePen shall build dictation and Meeting microphone audio from channels with actual signal instead of diluting one microphone channel across silent hardware channels.
- VoicePen shall not apply microphone boost to Meeting Mode recordings.
- When Meeting voice leveling is enabled, VoicePen shall process each Meeting Mode audio chunk through system dynamics and peak limiting before local transcription.
- When Meeting voice leveling cannot be applied, VoicePen shall continue transcription with the un-leveled preprocessed audio and log a diagnostic note rather than failing the meeting.
- VoicePen shall not change or overwrite raw temporary audio or retained recovery audio when applying Meeting voice leveling.
- VoicePen shall delete temporary voice-leveled chunk files after transcription succeeds or fails.
- During Meeting recording, VoicePen shall not change, mute, duck, restore, or call CoreAudio output-volume or output-mute APIs for the user's speaker or other output device.
- VoicePen shall not add microphone source selection in this iteration.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Dictation boost | Push-to-talk starts with boost enabled | Default input gain is set to maximum while recording and restored afterward |
| Current microphone status | Default input is `Studio Mic` | Audio settings show `Current microphone: System default (Studio Mic)` |
| Unknown microphone name | Default input name cannot be read | Audio settings show `Current microphone: System default` |
| Unsupported input gain | Device has no settable input volume | Dictation still records normally |
| AUHAL prepare ordering | App is idle and capture is prepared | AUHAL input path is initialized without output starting or playback side effects |
| Multichannel interface | A USB interface exposes many input channels and speech is present on only one channel | Dictation and Meeting microphone capture preserve the speech channel instead of treating the recording as silence |
| Meeting leveling | Meeting chunk has uneven voice levels | Chunk is rendered through system dynamics and limiter before transcription |
| Leveling failure | Audio Unit effect creation fails | Meeting transcribes the ordinary preprocessed chunk and logs a diagnostic note |
| Saved recordings opt-in | User enables saved dictation or Meeting recordings | VoicePen schedules matching audio for local copy without changing transcription or history outcomes |
| Saved recordings limit | Saved audio exceeds the configured cap | Oldest saved audio files are removed until storage is within the cap |

## Test Mapping

- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers audio setting defaults and persistence.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers current microphone display text, default-input change updates, and listener cleanup with a fake provider.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers audio and saved-recordings controls living in the Settings screen, shared settings bindings, and live Meeting microphone capture wiring without system voice processing.
- Automated: `VoicePenTests/App/AppPathsTests.swift` covers saved audio paths and temporary cleanup boundaries.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift` covers saved-audio copy semantics, readable names, extension preservation, and pruning.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift` covers asynchronous scheduling, request forwarding, failure swallowing, and serialized saved-audio work.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers dictation microphone boost lifecycle and best-effort failures.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers Meeting voice leveling routing, fallback, and processed temporary file cleanup.
- Automated: `VoicePenTests/Recording/DefaultAudioInputDeviceProviderTests.swift` covers formatting of named and unnamed default input devices.
- Automated: `VoicePenTests/Recording/DefaultInputGainControllerTests.swift` covers input gain set/restore behavior with fake CoreAudio.
- Automated: `VoicePenTests/Recording/ActiveChannelMonoMixerTests.swift` covers preserving a speech channel from multichannel microphone input while ignoring inactive hardware channels.
- Automated: `VoicePenTests/Recording/CoreAudioMicrophoneCaptureTests.swift` covers AUHAL prepare/start/stop/teardown sequencing and failure mapping with injectable boundaries.
- Manual: enable dictation boost, record, and verify macOS input level rises during recording and restores afterward on supported devices.
- Manual: start a meeting recording while playing meeting audio through speakers or headphones and verify the audible output level does not drop when recording starts or restore when recording stops.
- Manual: record a meeting with uneven speakers and compare transcription quality with Meeting voice leveling on and off; verify that the system Audio Unit chain creates a processed temporary file on the local Mac.

## Notes

Use Apple system Audio Units for Meeting voice leveling. Use input-only AUHAL for dictation and Meeting microphone capture. Keep audio features best-effort: audio capture and transcription should continue if the system cannot expose input gain or render the voice-leveling chain.

## Open Questions

- None.
