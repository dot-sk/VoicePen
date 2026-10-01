# Audio Settings And Voice Processing Specification

## Purpose

VoicePen should make audio capture more reliable without asking users to
understand macOS audio routing or local transcription model behavior.

## Requirements

### Requirement: Audio Settings And Voice Processing

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen provides audio controls in the Settings screen for dictation microphone boost, Meeting voice leveling, and saved recordings. Push-to-talk dictation and Meeting microphone capture run on low-level input-only AUHAL with idle preparation and must not change output playback volume, mute, or routing state. VoicePen applies bundled local RNNoise suppression to microphone audio before transcription while leaving Meeting system audio unchanged.

#### Scenario: Shows settings

- **WHEN** VoicePen shows settings
- **THEN** it shall not include a dedicated Audio sidebar section.

#### Scenario: Shows the Settings screen

- **WHEN** VoicePen shows the Settings screen
- **THEN** it shall include audio controls for dictation microphone boost, Meeting voice leveling, saved dictation recordings, saved Meeting recordings, saved-audio storage limit, and opening the saved recordings folder.

#### Scenario: No audio settings have been saved

- **WHEN** no audio settings have been saved
- **THEN** VoicePen shall enable dictation microphone boost, and Meeting voice leveling by default.

#### Scenario: No saved-recordings settings have been saved

- **WHEN** no saved-recordings settings have been saved
- **THEN** VoicePen shall keep saved dictation recordings and saved Meeting recordings disabled by default.

#### Scenario: Saved recordings

- **WHEN** this capability applies
- **THEN** Saved recordings shall be scheduled asynchronously for dictation and Meeting Mode, copied byte-for-byte, keep the source file extension, use readable date/time/source filenames, and be pruned oldest-first across dictation and Meeting saved audio when the configured total size cap is exceeded.

#### Scenario: Saved dictation recordings

- **WHEN** this capability applies
- **THEN** Saved dictation recordings shall schedule one audio file per valid dictation attempt, using the transcription input file when preprocessing creates one and the original recording otherwise.

#### Scenario: Saved recording copy or pruning failures

- **WHEN** this capability applies
- **THEN** Saved recording copy or pruning failures shall be logged asynchronously and shall not change dictation transcription, insertion, retry, or history behavior, or Meeting transcription, retry, recovery audio, or history behavior.

#### Scenario: Saved recordings 2

- **WHEN** this capability applies
- **THEN** Saved recordings shall be stored under Application Support, not temporary audio storage, and stale temporary-audio cleanup shall not remove them.

#### Scenario: Dictation recording ends, is canceled, fails to start, times out, or fails during processing

- **WHEN** dictation recording ends, is canceled, fails to start, times out, or fails during processing
- **THEN** VoicePen shall attempt to restore the original input volume it changed.

#### Scenario: Dictation and Meeting microphone capture

- **WHEN** this capability applies
- **THEN** Dictation and Meeting microphone capture shall use input-only AUHAL with output disabled and must not call `setVoiceProcessingEnabled` or `VoiceProcessingIO`.

#### Scenario: Dictation idle prepare and start

- **WHEN** this capability applies
- **THEN** Dictation idle prepare and start shall use AUHAL input-only capture: `prepare()` shall create/configure/initialize capture units without starting, and `start()` must start capture.

#### Scenario: Selected input device exposes multiple input channels

- **WHEN** the selected input device exposes multiple input channels
- **THEN** VoicePen shall build dictation and Meeting microphone audio from channels with actual signal instead of diluting one microphone channel across silent hardware channels.

#### Scenario: Shall not apply microphone boost to Meeting Mode recordings

- **WHEN** this capability applies
- **THEN** VoicePen shall not apply microphone boost to Meeting Mode recordings.

#### Scenario: Shall apply bundled RNNoise suppression to push-to-talk microphone recordings before dictation preprocessing and to

- **WHEN** this capability applies
- **THEN** VoicePen shall apply bundled RNNoise suppression to push-to-talk microphone recordings before dictation preprocessing and to the Meeting microphone source before source mixing, while leaving Meeting system audio unchanged.

#### Scenario: RNNoise suppression

- **WHEN** this capability applies
- **THEN** RNNoise suppression shall preserve the microphone timeline and shall not use Voice Activity Detection to remove microphone samples that were not classified as speech.

#### Scenario: Meeting microphone RNNoise suppression

- **WHEN** this capability applies
- **THEN** Meeting microphone RNNoise suppression shall not overwrite raw captured microphone or retained recovery audio, and processing failures shall fall back to the original microphone samples.

#### Scenario: Dictation and Meeting capture

- **WHEN** this capability applies
- **THEN** Dictation and Meeting capture shall reuse one stateful PCM converter per source stream so consecutive callbacks do not discard resampler state or samples.

#### Scenario: Meeting microphone and system-audio callbacks

- **WHEN** this capability applies
- **THEN** Meeting microphone and system-audio callbacks shall preserve buffer order and write through the system asynchronous audio-file writer without synchronous file I/O in the realtime callback.

#### Scenario: Meeting source shutdown

- **WHEN** this capability applies
- **THEN** Meeting source shutdown shall drain accepted callback work, close the writer so pending audio is flushed, and reject a finalized source that is materially shorter than its capture timeline.

#### Scenario: Meeting mastering

- **WHEN** this capability applies
- **THEN** Meeting mastering shall normalize microphone and system speech levels independently, preserve timeline offsets, reserve mix headroom, avoid hard clipping, and keep one gain across internal processing blocks.

#### Scenario: Meeting voice leveling is enabled

- **WHEN** Meeting voice leveling is enabled
- **THEN** VoicePen shall process the complete Meeting master through system dynamics and peak limiting before local transcription.

#### Scenario: Meeting voice leveling cannot be applied

- **WHEN** Meeting voice leveling cannot be applied
- **THEN** VoicePen shall continue transcription with the un-leveled master and log a diagnostic note rather than failing the meeting.

#### Scenario: Shall not change or overwrite raw temporary audio or retained recovery audio when applying

- **WHEN** this capability applies
- **THEN** VoicePen shall not change or overwrite raw temporary audio or retained recovery audio when applying Meeting voice leveling.

#### Scenario: Shall delete temporary voice-leveled master files after transcription succeeds or fails

- **WHEN** this capability applies
- **THEN** VoicePen shall delete temporary voice-leveled master files after transcription succeeds or fails.

#### Scenario: During Meeting recording, VoicePen

- **WHEN** this capability applies
- **THEN** During Meeting recording, VoicePen shall not change, mute, duck, restore, or call CoreAudio output-volume or output-mute APIs for the user's speaker or other output device.

### Requirement: RNNoise output stays within the supported audio range

VoicePen SHALL validate successful RNNoise microphone output before using it for
silence analysis, saved transcription-input audio, Meeting mastering, or local
transcription. When the output exceeds the supported full-scale range, VoicePen
SHALL uniformly attenuate the complete processed signal to leave headroom,
preserve relative sample amplitudes and sample count, and avoid hard clipping.
VoicePen MUST NOT amplify output that is already within the supported range.

#### Scenario: RNNoise output exceeds full scale

- **WHEN** successful RNNoise processing produces one or more finite samples outside the supported full-scale range
- **THEN** VoicePen uniformly attenuates the complete processed signal before downstream use so every sample is finite and within the supported range

#### Scenario: RNNoise output is already within full scale

- **WHEN** successful RNNoise processing produces only finite samples within the supported full-scale range
- **THEN** VoicePen passes the processed signal onward without changing its amplitude

#### Scenario: RNNoise output cannot be safely conditioned

- **WHEN** RNNoise output contains a non-finite sample or cannot be conditioned into the supported range
- **THEN** VoicePen treats noise suppression as failed, logs a diagnostic, and continues through the existing original-microphone fallback

#### Scenario: Meeting microphone noise suppression succeeds

- **WHEN** VoicePen applies RNNoise to a Meeting microphone source
- **THEN** it conditions only the processed microphone signal while leaving Meeting system audio, raw microphone capture, and retained recovery audio unchanged

#### Scenario: VoicePen conditions RNNoise output

- **WHEN** VoicePen accepts or attenuates successful RNNoise output
- **THEN** diagnostics identify the input peak, output peak, and whether attenuation was applied without logging audio content
