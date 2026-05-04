---
id: SPEC-001
status: implemented
updated: 2026-05-04
tests:
  - VoicePenTests/Hotkey/HotkeyPreferenceTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
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

- When dictation starts, VoicePen shall start recording and show the recording overlay.
- When the recording overlay shows the microphone level indicator, the white level bar shall animate vertically without horizontal jitter.
- When recording duration is below the minimum, VoicePen shall stop without transcription or insertion.
- When audio is silent or transcription returns an empty result, VoicePen shall not insert text or create a history recording.
- When recording is valid, VoicePen shall preprocess audio before transcription, pass the resolved language and glossary prompt, normalize raw text, insert non-empty final text, and record timing data.
- When final text is prepared for output, VoicePen shall always replace `ё` with `е`, `Ё` with `Е`, long dashes with `–`, and typographic quotes with plain quotes before insertion or history storage.
- When insertion succeeds, VoicePen shall hide the processing overlay without showing a success notification.
- When transcription fails, VoicePen shall propagate the error and never insert partial text.
- When the user records or changes a custom push-to-talk shortcut, VoicePen shall install that shortcut without requiring an app restart or another hotkey preference change.
- When the custom shortcut preference is selected before a shortcut has been recorded, VoicePen shall surface that the shortcut is missing without entering a persistent fatal error state.
- When VoicePen shows its menu bar extra menu, it shall group related commands with separators, hide dictation or text actions that are not available in the current state, omit idle status text, and include the configured push-to-talk hotkey hint on visible dictation commands.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Short recording | 0.2s recording | No transcription and no insertion |
| Recording overlay | Active recording with changing input level | The microphone level bar changes height while staying horizontally anchored |
| Silent recording | Valid duration with no speech | No insertion and no history recording |
| Normal recording | "создай типы на тайп скрипт" | Inserts "создай типы на TypeScript" |
| Global output normalization | `Ёжик сказал: «пойдём» — готово` | `Ежик сказал: "пойдем" – готово` |
| Transcription error | Transcriber throws | Error propagates and nothing is inserted |
| Custom shortcut recorded | User selects custom shortcut and records Ctrl-E | Holding Ctrl-E starts push-to-talk without restarting VoicePen |
| Empty custom shortcut | User selects custom shortcut before recording one | VoicePen reports that the shortcut is missing and becomes active once a shortcut is recorded |
| Menu bar extra while idle with no text | Open VoicePen menu bar extra | Shows the available dictation action with its hotkey hint, app/config actions, and quit without idle status text or disabled text actions |

## Test Mapping

- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers recording start, short recording skip, preprocessing, glossary/language routing, normalization, global output cleanup, insertion, silent audio, empty transcription, and error propagation.
- Automated: `VoicePenTests/TextOutput/TextOutputNormalizerTests.swift` covers global output character replacements.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers reinstalling the push-to-talk hotkey when a custom shortcut is recorded after the custom preference is selected.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu bar extra command grouping, hiding unavailable menu actions, omitting idle status text, and showing push-to-talk hotkey hints.
- Manual: verify the menu bar app records while the configured hotkey is held and pastes final text into the active app when Accessibility permission is granted.
- Manual: hold the configured push-to-talk hotkey and verify the white microphone level bar changes height without moving left or right inside the red capsule.
- Manual: select the custom push-to-talk shortcut, record Ctrl-E, hold Ctrl-E for the configured hold duration, and verify recording starts without restarting VoicePen.

## Notes

Keep orchestration in `DictationPipeline` and user-facing app state coordination in `AppController`. Prefer fakes from `VoicePenTests/TestDoubles` for pipeline tests.

## Open Questions

- None.
