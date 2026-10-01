# Push-To-Talk Dictation Pipeline Specification

## Purpose

VoicePen must turn a held hotkey recording into inserted text without surprising the user or leaking work outside the local machine.

## Requirements

### Requirement: Push-To-Talk Dictation Pipeline

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen records while push-to-talk is active, skips recordings below the minimum duration, preprocesses audio, transcribes locally, normalizes text with the custom dictionary and global output rules, inserts non-empty final text, and shows overlay state during the flow. It does not provide continuous background dictation, cloud transcription, or rich text insertion.

#### Scenario: Valid push-to-talk press begins while VoicePen is ready

- **WHEN** a valid push-to-talk press begins while VoicePen is ready
- **THEN** VoicePen shall immediately show pre-capture recording feedback, then transition to confirmed recording feedback after capture start succeeds.

#### Scenario: Pre-capture recording feedback is visible

- **WHEN** pre-capture recording feedback is visible
- **THEN** VoicePen shall not count that time as captured audio and shall not save or transcribe audio until capture start succeeds.

#### Scenario: Push-to-talk is released before capture start finishes

- **WHEN** push-to-talk is released before capture start finishes
- **THEN** VoicePen shall finish the pending startup safely and stop through the normal short-recording path without transcribing pre-capture time.

#### Scenario: Recording support work does not starve UI updates

- **WHEN** push-to-talk recording starts or captures audio
- **THEN** microphone preparation, microphone boost, metering, model warmup, and ASR-related work shall not block or starve app-state updates or visible recording UI updates.

#### Scenario: Dictation runs

- **WHEN** dictation runs
- **THEN** PTT shall be modeled only with `DictationRuntimeState` values `idle`, `starting`, `recording`, `transcribing`; `AppState.recording` and `AppState.transcribing` are not used as dictation-state.

#### Scenario: Push-to-talk starts while a meeting is recording

- **WHEN** push-to-talk starts while a meeting is recording
- **THEN** dictation shall execute without canceling or pausing meeting lifecycle and shall keep meeting state unchanged.

#### Scenario: Push-to-talk starts while a meeting is recording or processing

- **WHEN** push-to-talk starts while a meeting is recording or processing
- **THEN** dictation shall use the same shared ASR actor/client path and share `RoutingTranscriptionClient` + `WhisperCppTranscriptionClient` with any existing meeting request.

#### Scenario: Is idle and microphone permission/settings allow capture preparation

- **WHEN** VoicePen is idle and microphone permission/settings allow capture preparation
- **THEN** VoicePen shall best-effort prepare microphone capture before the next push-to-talk press by creating input-only AUHAL capture state without starting output or affecting playback.

#### Scenario: Dictation starts and audio settings enable microphone boost

- **WHEN** dictation starts and audio settings enable microphone boost
- **THEN** VoicePen shall best-effort raise the current default input device level for the recording and restore it afterward without performing CoreAudio gain work on the main actor.

#### Scenario: Microphone level is not available yet

- **WHEN** microphone level is not available yet
- **THEN** the recording overlay shall stay visible with a stable fallback level until real input levels arrive.

#### Scenario: Recording overlay shows the microphone level indicator

- **WHEN** the recording overlay shows the microphone level indicator
- **THEN** the single white level bar shall animate vertically from a display-sampled cached collapsed-spectrum microphone level without routing every level sample through overlay state updates.

#### Scenario: Speech or sung vowels remain present, including sustained flat A/O-like tones

- **WHEN** speech or sung vowels remain present, including sustained flat A/O-like tones
- **THEN** the microphone level bar shall keep a stable visible height instead of decaying toward zero due to lack of spectral novelty; when input becomes silent, the bar shall release down.

#### Scenario: Recording duration is below the minimum

- **WHEN** recording duration is below the minimum
- **THEN** VoicePen shall stop without transcription or insertion.

#### Scenario: Recording duration is below the minimum 2

- **WHEN** recording duration is below the minimum
- **THEN** VoicePen shall not save a local audio recording even if saved dictation recordings are enabled.

#### Scenario: Push-to-talk recording meets the minimum duration

- **WHEN** a push-to-talk recording meets the minimum duration
- **THEN** VoicePen shall apply bundled RNNoise suppression to the recorded microphone audio before silence trimming, saved transcription-input audio, and local transcription.

#### Scenario: Push-to-talk RNNoise suppression

- **WHEN** this capability applies
- **THEN** Push-to-talk RNNoise suppression shall preserve the recording timeline and speech samples instead of using Voice Activity Detection to remove unclassified microphone intervals.

#### Scenario: Push-to-talk RNNoise suppression cannot run

- **WHEN** push-to-talk RNNoise suppression cannot run
- **THEN** VoicePen shall continue preprocessing and transcription with the original recorded samples and log a diagnostic note.

#### Scenario: Push-to-talk preprocessing successfully denoises and trims a recording

- **WHEN** push-to-talk preprocessing successfully denoises and trims a recording
- **THEN** VoicePen shall preserve the original recording and create no more than one derived transcription-input file.

#### Scenario: Push-to-talk preprocessing succeeds

- **WHEN** push-to-talk preprocessing succeeds
- **THEN** VoicePen shall log diagnostics that distinguish audio read, RNNoise input conversion, RNNoise frame processing, RNNoise output conversion, silence analysis, and final audio write durations.

#### Scenario: Saved dictation recordings are enabled and recording duration meets the minimum

- **WHEN** saved dictation recordings are enabled and recording duration meets the minimum
- **THEN** VoicePen shall schedule one best-effort asynchronous audio copy for the dictation attempt to the user's saved recordings folder.

#### Scenario: Audio preprocessing produces a transcription input file

- **WHEN** audio preprocessing produces a transcription input file
- **THEN** VoicePen shall schedule saving that transcription input; when preprocessing reports no speech or fails before producing an input file, VoicePen shall schedule saving the original recording once.

#### Scenario: Saved dictation audio copy succeeds for a dictation that creates a history entry

- **WHEN** a saved dictation audio copy succeeds for a dictation that creates a history entry
- **THEN** VoicePen shall associate the archived audio file with that history entry.

#### Scenario: Saved dictation audio copying or pruning is scheduled

- **WHEN** saved dictation audio copying or pruning is scheduled
- **THEN** VoicePen shall continue transcription, normalization, insertion, and result handling without waiting for that saved-audio work to finish.

#### Scenario: Saving dictation audio fails

- **WHEN** saving dictation audio fails
- **THEN** VoicePen shall log the failure asynchronously and continue the dictation workflow without changing transcription, insertion, retry, or history behavior.

#### Scenario: Audio is silent or transcription returns an empty result

- **WHEN** audio is silent or transcription returns an empty result
- **THEN** VoicePen shall not insert text or create a history recording.

#### Scenario: Local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал

- **WHEN** local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Субтитры создавал ...", "Добавил субтитры ...", or "Продолжение следует..."
- **THEN** VoicePen shall remove those lines before normalization, insertion, or history storage.

#### Scenario: Recording is valid

- **WHEN** recording is valid
- **THEN** VoicePen shall preprocess audio before transcription, pass the resolved language and glossary prompt for every valid recording duration, normalize raw text, insert non-empty final text, and record timing data.

#### Scenario: Final text is prepared for output

- **WHEN** final text is prepared for output
- **THEN** VoicePen shall always replace `ё` with `е`, `Ё` with `Е`, long dashes with `–`, and typographic quotes with plain quotes before insertion or history storage.

#### Scenario: Inserts final text through the pasteboard

- **WHEN** VoicePen inserts final text through the pasteboard
- **THEN** it shall capture the current pasteboard immediately before writing VoicePen text and restore all previous pasteboard items and data types after the configured restore delay; if the pasteboard was empty, it shall become empty again.

#### Scenario: Insertion succeeds

- **WHEN** insertion succeeds
- **THEN** VoicePen shall hide the processing overlay without showing a success notification.

#### Scenario: Transcription fails

- **WHEN** transcription fails
- **THEN** VoicePen shall propagate the error and never insert partial text.

#### Scenario: User records or changes a custom push-to-talk shortcut

- **WHEN** the user records or changes a custom push-to-talk shortcut
- **THEN** VoicePen shall install that shortcut without requiring an app restart or another hotkey preference change.

#### Scenario: Custom push-to-talk shortcut recorder is visible

- **WHEN** the custom push-to-talk shortcut recorder is visible
- **THEN** VoicePen shall show a short secondary note that macOS or app menus can reserve some shortcuts.

#### Scenario: Push-to-talk is pressed

- **WHEN** push-to-talk is pressed
- **THEN** VoicePen shall start pre-capture feedback immediately without a configurable hold-duration gate.

#### Scenario: A meeting is recording

- **WHEN** the a meeting is recording
- **THEN** VoicePen shall not raise default input gain for push-to-talk.

#### Scenario: Push-to-talk is active during meeting recording or processing

- **WHEN** push-to-talk is active during meeting recording or processing
- **THEN** pushed audio may remain in the shared default-input path and may be included in meeting audio; V1 does not apply a manual suppression filter.

#### Scenario: Dictation returns an error or timeout during active meeting capture or processing

- **WHEN** dictation returns an error or timeout during active meeting capture or processing
- **THEN** meeting state and lifecycle timers shall remain active.

#### Scenario: Custom shortcut preference is selected before a shortcut has been recorded

- **WHEN** the custom shortcut preference is selected before a shortcut has been recorded
- **THEN** VoicePen shall surface that the shortcut is missing without entering a persistent fatal error state.

#### Scenario: Manual double-capture guard for default-input PTT remains disabled in V1; meeting and dictation share

- **WHEN** this capability applies
- **THEN** Manual double-capture guard for default-input PTT remains disabled in V1; meeting and dictation share the default input capture path when HAL supports concurrent input opens.

#### Scenario: Shows its menu bar extra menu

- **WHEN** VoicePen shows its menu bar extra menu
- **THEN** it shall group related commands with separators, hide dictation or text actions that are not available in the current state, omit idle status text, include the configured push-to-talk hotkey hint on visible dictation commands, and label latest-text actions as dictation actions so they are not confused with Meeting Mode transcripts.

#### Scenario: Dictation runtime state changes between idle, starting, recording, and transcribing

- **WHEN** dictation runtime state changes between idle, starting, recording, and transcribing
- **THEN** the menu bar status icon shall refresh without waiting for the tray menu to open.

### Requirement: Dictation uses bounded denoised transcription audio

When RNNoise succeeds for a valid push-to-talk recording, VoicePen SHALL use the
same conditioned, finite, full-scale-bounded signal for silence analysis, the
derived transcription-input file, saved dictation audio, and local
transcription.

#### Scenario: Dictation RNNoise output requires attenuation

- **WHEN** RNNoise succeeds for a valid dictation recording and its output exceeds the supported full-scale range
- **THEN** VoicePen transcribes and, when enabled, saves one derived audio file containing the uniformly attenuated signal

#### Scenario: Dictation RNNoise output is already safe

- **WHEN** RNNoise succeeds for a valid dictation recording and its output is already finite and within the supported full-scale range
- **THEN** VoicePen preserves that signal's amplitude while continuing the existing silence-trimming, saving, and transcription flow

#### Scenario: Dictation RNNoise output is invalid

- **WHEN** RNNoise returns output that cannot be safely conditioned
- **THEN** VoicePen uses the existing original-recording fallback and does not save or transcribe the invalid processed signal
