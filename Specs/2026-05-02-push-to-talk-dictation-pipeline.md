---
id: SPEC-001
status: implemented
updated: 2026-06-09
tests:
  - VoicePenTests/Hotkey/HotkeyPreferenceTests.swift
  - VoicePenTests/Insertion/TextInsertionClientTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/Recording/LiveRecordingMeterTests.swift
  - VoicePenTests/Recording/VoiceBandAnalyzerTests.swift
  - VoicePenTests/Transcription/TranscriptionPostFilterTests.swift
  - VoicePenTests/TextOutput/TextOutputNormalizerTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Push-To-Talk Dictation Pipeline

## Problem

VoicePen must turn a held hotkey recording into inserted text without surprising the user or leaking work outside the local machine.

## Behavior

VoicePen records while push-to-talk is active, skips recordings below the minimum duration, preprocesses audio, transcribes locally, normalizes text with the custom dictionary and global output rules, inserts non-empty final text, and shows overlay state during the flow. It does not provide continuous background dictation, cloud transcription, or rich text insertion.

## Acceptance Criteria

- When a valid push-to-talk press begins while VoicePen is ready, VoicePen shall immediately show pre-capture recording feedback, then transition to confirmed recording feedback after capture start succeeds.
- When pre-capture recording feedback is visible, VoicePen shall not count that time as captured audio and shall not save or transcribe audio until capture start succeeds.
- When push-to-talk is released before capture start finishes, VoicePen shall finish the pending startup safely and stop through the normal short-recording path without transcribing pre-capture time.
- When push-to-talk recording starts or captures audio, microphone preparation, microphone boost, metering, model warmup, and ASR-related work shall not block or starve app-state updates or visible recording UI updates.
- When VoicePen is idle and microphone permission/settings allow capture preparation, VoicePen shall best-effort prepare microphone capture before the next push-to-talk press.
- When dictation starts and audio settings enable microphone boost, VoicePen shall best-effort raise the current default input device level for the recording and restore it afterward without performing CoreAudio gain work on the main actor.
- When microphone level is not available yet, the recording overlay shall stay visible with a stable fallback level until real input levels arrive.
- When the recording overlay shows the microphone level indicator, the white level bar shall animate vertically from a display-sampled cached voice-band microphone level without routing every level sample through overlay state updates.
- When recording duration is below the minimum, VoicePen shall stop without transcription or insertion.
- When recording duration is below the minimum, VoicePen shall not save a local audio recording even if saved dictation recordings are enabled.
- When saved dictation recordings are enabled and recording duration meets the minimum, VoicePen shall schedule one best-effort asynchronous audio copy for the dictation attempt to the user's saved recordings folder.
- When audio preprocessing produces a transcription input file, VoicePen shall schedule saving that transcription input; when preprocessing reports no speech or fails before producing an input file, VoicePen shall schedule saving the original recording once.
- When saved dictation audio copying or pruning is scheduled, VoicePen shall continue transcription, normalization, insertion, and result handling without waiting for that saved-audio work to finish.
- When saving dictation audio fails, VoicePen shall log the failure asynchronously and continue the dictation workflow without changing transcription, insertion, retry, or history behavior.
- When audio is silent or transcription returns an empty result, VoicePen shall not insert text or create a history recording.
- When local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Субтитры создавал ...", "Добавил субтитры ...", or "Продолжение следует...", VoicePen shall remove those lines before normalization, insertion, or history storage.
- When recording is valid, VoicePen shall preprocess audio before transcription, pass the resolved language and glossary prompt for every valid recording duration, normalize raw text, insert non-empty final text, and record timing data.
- When final text is prepared for output, VoicePen shall always replace `ё` with `е`, `Ё` with `Е`, long dashes with `–`, and typographic quotes with plain quotes before insertion or history storage.
- When VoicePen inserts final text through the pasteboard, it shall capture the current pasteboard immediately before writing VoicePen text and restore all previous pasteboard items and data types after the configured restore delay; if the pasteboard was empty, it shall become empty again.
- When insertion succeeds, VoicePen shall hide the processing overlay without showing a success notification.
- When transcription fails, VoicePen shall propagate the error and never insert partial text.
- When dictation processing does not complete within 30 seconds, VoicePen shall cancel processing, leave the transcribing state, surface a timeout error, and allow a later recording attempt.
- When the user records or changes a custom push-to-talk shortcut, VoicePen shall install that shortcut without requiring an app restart or another hotkey preference change.
- When the custom push-to-talk shortcut recorder is visible, VoicePen shall show a short secondary note that macOS or app menus can reserve some shortcuts.
- When push-to-talk is pressed, VoicePen shall start pre-capture feedback immediately without a configurable hold-duration gate.
- When the custom shortcut preference is selected before a shortcut has been recorded, VoicePen shall surface that the shortcut is missing without entering a persistent fatal error state.
- When VoicePen shows its menu bar extra menu, it shall group related commands with separators, hide dictation or text actions that are not available in the current state, omit idle status text, include the configured push-to-talk hotkey hint on visible dictation commands, and label latest-text actions as dictation actions so they are not confused with Meeting Mode transcripts.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Short recording | 0.2s recording | No transcription and no insertion |
| Saved dictation audio disabled | Default settings | No raw or processed audio is copied to saved recordings |
| Saved dictation audio enabled | Valid push-to-talk recording | One dictation audio file is scheduled for local copy with a readable audio filename |
| Saved dictation audio failure | Saved recordings folder cannot be written | Dictation still transcribes and inserts normally |
| Recording startup | Press push-to-talk while ready | Recording feedback appears immediately, before capture startup finishes |
| Recording overlay | Active recording with changing input level | The microphone level bar changes height from voice-band levels while staying horizontally anchored |
| Silent recording | Valid duration with no speech | No insertion and no history recording |
| Artifact-only transcription | Whisper returns only `Субтитры создавал DimaTorzok` | No insertion and no history recording |
| Artifact line with useful text | Whisper returns subtitle credit, useful dictated text, and `Продолжение следует...` | Inserts and stores only the useful dictated text |
| Normal recording | "создай типы на тайп скрипт" | Inserts "создай типы на TypeScript" |
| Global output normalization | `Ёжик сказал: «пойдём» — готово` | `Ежик сказал: "пойдем" – готово` |
| Clipboard restoration | Pasteboard contains text, files, or rich data before insertion | VoicePen temporarily pastes dictation text and then restores the previous pasteboard contents |
| Transcription error | Transcriber throws | Error propagates and nothing is inserted |
| Hung transcription | Transcriber or processing backend does not return | VoicePen exits transcribing and surfaces a timeout error |
| Custom shortcut recorded | User selects custom shortcut and records Ctrl-E | Pressing Ctrl-E starts push-to-talk without restarting VoicePen |
| Reserved shortcut | User opens the custom shortcut recorder | A short secondary note explains that some shortcuts may be reserved by macOS or app menus |
| Empty custom shortcut | User selects custom shortcut before recording one | VoicePen reports that the shortcut is missing and becomes active once a shortcut is recorded |
| Menu bar extra while idle with no text | Open VoicePen menu bar extra | Shows the available dictation action with its hotkey hint, app/config actions, and quit without idle status text or disabled text actions |
| Menu bar extra after dictation | Dictation produced text and the menu is open | Latest-text actions are labeled as dictation actions, not generic transcription actions |

## Test Mapping

- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers async recording start/stop ordering, immediate pre-capture recording feedback, confirmed recording feedback after successful capture start, short recording skip, preprocessing, glossary/language routing for short and long valid recordings, normalization, global output cleanup, insertion, silent audio, empty transcription, error propagation, and saved dictation audio scheduling.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift` covers byte-for-byte saved audio copies, readable filenames, extension preservation, and storage pruning.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift` covers asynchronous saved-audio scheduling, request forwarding, non-fatal archive failures, and serialized copy/pruning work.
- Automated: `VoicePenTests/Insertion/TextInsertionClientTests.swift` covers temporary pasteboard replacement and restoration of previous plain text, empty pasteboards, and multi-item or multi-type pasteboard contents.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers awaited best-effort microphone boost start and restore around dictation recordings.
- Automated: `VoicePenTests/Recording/VoiceBandAnalyzerTests.swift` covers FFT voice-band level calculation used by live dictation metering.
- Automated: `VoicePenTests/Recording/LiveRecordingMeterTests.swift` covers fresh-buffer live metering with asynchronously analyzed, smoothed rolling FFT voice-band levels and cheap cached level reads.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers canceling pending model warmup when push-to-talk starts without scheduling a replacement warmup.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` and `VoicePenTests/Transcription/TranscriptionPostFilterTests.swift` cover known subtitle/outro artifact cleanup before insertion.
- Automated: `VoicePenTests/TextOutput/TextOutputNormalizerTests.swift` covers global output character replacements.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers reinstalling the push-to-talk hotkey when a custom shortcut is recorded after the custom preference is selected and dictation timeout recovery when processing hangs.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu bar extra command grouping, hiding unavailable menu actions, omitting idle status text, showing push-to-talk hotkey hints, showing the custom shortcut limitation note in the Settings screen, omitting the removed hold-duration control from Settings, and labeling latest-text actions as dictation actions.
- Manual: verify the menu bar app records while the configured hotkey is held and pastes final text into the active app when Accessibility permission is granted.
- Manual: hold the configured push-to-talk hotkey and verify the white microphone level bar changes height without moving left or right inside the red capsule.
- Manual: select the custom push-to-talk shortcut, record Ctrl-E, press Ctrl-E, and verify recording feedback appears immediately without restarting VoicePen.

## Notes

Keep orchestration in `DictationPipeline` and user-facing app state coordination in `AppController`. Prefer fakes from `VoicePenTests/TestDoubles` for pipeline tests.

## Open Questions

- None.
