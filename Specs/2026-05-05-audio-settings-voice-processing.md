---
id: SPEC-012
status: implemented
updated: 2026-07-24
tests:
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/App/AppPathsTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/Meetings/MeetingRecordingStateTests.swift
  - VoicePenTests/AudioProcessing/RNNoiseAudioDenoiserTests.swift
  - VoicePenTests/AudioProcessing/PCMStreamConverterTests.swift
  - VoicePenTests/Recording/DefaultAudioInputDeviceProviderTests.swift
  - VoicePenTests/Recording/DefaultInputGainControllerTests.swift
  - VoicePenTests/Recording/ActiveChannelMonoMixerTests.swift
  - VoicePenTests/Recording/CoreAudioMicrophoneCaptureTests.swift
  - VoicePenTests/Recording/LiveAudioRecordingClientTests.swift
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
- VoicePen shall not expose or apply configurable speech-speed preprocessing for dictation or Meeting transcription.
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
- Raw Meeting microphone capture shall preserve the selected active input-channel sample level through mono conversion and shall not apply software gain or automatic gain control.
- VoicePen shall apply bundled RNNoise suppression to push-to-talk microphone recordings before dictation preprocessing and to the Meeting microphone source before source mixing, while leaving Meeting system audio unchanged.
- RNNoise suppression shall preserve the microphone timeline and shall not use Voice Activity Detection to remove microphone samples that were not classified as speech.
- Meeting microphone RNNoise suppression shall not overwrite raw captured microphone or retained recovery audio, and processing failures shall fall back to the original microphone samples.
- Push-to-talk preprocessing shall remove superseded denoised and trimmed temporary files while preserving the original recording and final transcription input.
- Dictation and Meeting capture shall reuse one stateful PCM converter per stream so sequential buffers preserve resampler state, conversion requests can consume all supplied input frames, and the final converted tail is retained.
- Meeting microphone and system-audio callbacks shall preserve buffer order on their existing serial callback queues; Meeting file writes shall use the system asynchronous audio-file writer without a second application-owned realtime queue.
- Normal Meeting stop shall stop the Core Audio source, wait for callback work already submitted to its source queue, then close the writer so the final accepted buffer is flushed; write or close failures shall mark the affected source failed and remove invalid output.
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
| Noisy microphone | The microphone contains steady background noise while the user or system speakers talk | RNNoise reduces microphone noise without removing local speech, raw microphone audio remains available for recovery, and system audio stays unchanged |
| Denoising failure | RNNoise model loading or processing fails | VoicePen continues dictation or Meeting processing with the original microphone samples |
| Superseded preprocessing file | Denoising is followed by trimming | The denoised artifact is removed and the trimmed transcription input remains available |
| Meeting callback drain | Stop follows the final microphone or system-audio callback | The source queue drains before the file writer closes, and the final buffer remains in the recording |
| Streamed sample-rate conversion | Native-rate audio arrives across many callback buffers | The output duration and waveform match conversion of the same input as one stream, including the final tail |
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
- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers ordered asynchronous Meeting file writes, immediate-finish tail flushing, cancellation cleanup, and injected write/close failures.
- Automated: `VoicePenTests/AudioProcessing/PCMStreamConverterTests.swift` covers one-shot and streamed conversion equivalence, large input buffers spanning converter requests, and active-channel preservation.
- Automated: `VoicePenTests/Recording/DefaultAudioInputDeviceProviderTests.swift` covers formatting of named and unnamed default input devices.
- Automated: `VoicePenTests/Recording/DefaultInputGainControllerTests.swift` covers input gain set/restore behavior with fake CoreAudio.
- Automated: `VoicePenTests/Recording/ActiveChannelMonoMixerTests.swift` covers preserving mono sample levels and a speech channel from multichannel microphone input while ignoring inactive hardware channels.
- Automated: `VoicePenTests/AudioProcessing/RNNoiseAudioDenoiserTests.swift` covers RNNoise frame processing, sample-rate conversion, duration preservation, tail handling, bundled model loading, dictation preprocessing, dictation fallback to original samples, and cleanup of superseded preprocessing artifacts.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers applying RNNoise only to recorded Meeting microphone samples, leaving system audio unchanged, and preserving original samples when denoising fails.
- Automated: `VoicePenTests/Recording/CoreAudioMicrophoneCaptureTests.swift` covers AUHAL prepare/start/stop/teardown sequencing, failure mapping, and stop waiting for callback work already submitted to the capture queue.
- Automated: `VoicePenTests/Recording/LiveAudioRecordingClientTests.swift` covers the dictation recording format, active-channel preservation, and retaining the final converted buffer on stop.

## Notes

Use Apple system Audio Units for Meeting voice leveling and bundled RNNoise for recorded microphone noise suppression. Use input-only AUHAL for dictation and Meeting microphone capture. Meeting capture writes through `ExtAudioFileWriteAsync` on the serial source callback path and relies on its internal asynchronous ring rather than an additional application queue. Keep audio features best-effort: audio capture and transcription should continue if the system cannot expose input gain, run RNNoise, or render the voice-leveling chain.

## Open Questions

- None.
