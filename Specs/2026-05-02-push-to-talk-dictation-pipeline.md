---
id: SPEC-001
status: implemented
updated: 2026-05-03
tests:
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
---

# Push-To-Talk Dictation Pipeline

## Problem

VoicePen must turn a held hotkey recording into inserted text without surprising the user or leaking work outside the local machine.

## Behavior

VoicePen records while push-to-talk is active, skips recordings below the minimum duration, preprocesses audio, transcribes locally, normalizes text with the custom dictionary, inserts non-empty final text, and shows overlay state during the flow. It does not provide continuous background dictation, cloud transcription, or rich text insertion.

## Acceptance Criteria

- When dictation starts, VoicePen shall start recording and show the recording overlay.
- When recording duration is below the minimum, VoicePen shall stop without transcription or insertion.
- When audio is silent or transcription returns an empty result, VoicePen shall not insert text or create a history recording.
- When recording is valid, VoicePen shall preprocess audio before transcription, pass the resolved language and glossary prompt, normalize raw text, insert non-empty final text, and record timing data.
- When transcription fails, VoicePen shall propagate the error and never insert partial text.
- When the user records or changes a custom push-to-talk shortcut, VoicePen shall install that shortcut without requiring an app restart or another hotkey preference change.
- When the custom shortcut preference is selected before a shortcut has been recorded, VoicePen shall surface that the shortcut is missing without entering a persistent fatal error state.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Short recording | 0.2s recording | No transcription and no insertion |
| Silent recording | Valid duration with no speech | No insertion and no history recording |
| Normal recording | "создай типы на тайп скрипт" | Inserts "создай типы на TypeScript" |
| Transcription error | Transcriber throws | Error propagates and nothing is inserted |
| Custom shortcut recorded | User selects custom shortcut and records Ctrl-E | Holding Ctrl-E starts push-to-talk without restarting VoicePen |
| Empty custom shortcut | User selects custom shortcut before recording one | VoicePen reports that the shortcut is missing and becomes active once a shortcut is recorded |

## Test Mapping

- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers recording start, short recording skip, preprocessing, glossary/language routing, normalization, insertion, silent audio, empty transcription, and error propagation.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers reinstalling the push-to-talk hotkey when a custom shortcut is recorded after the custom preference is selected.
- Manual: verify the menu bar app records while the configured hotkey is held and pastes final text into the active app when Accessibility permission is granted.
- Manual: select the custom push-to-talk shortcut, record Ctrl-E, hold Ctrl-E for the configured hold duration, and verify recording starts without restarting VoicePen.

## Notes

Keep orchestration in `DictationPipeline` and user-facing app state coordination in `AppController`. Prefer fakes from `VoicePenTests/TestDoubles` for pipeline tests.

## Open Questions

- None.
