---
id: SPEC-001
status: implemented
updated: 2026-05-02
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

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Short recording | 0.2s recording | No transcription and no insertion |
| Silent recording | Valid duration with no speech | No insertion and no history recording |
| Normal recording | "создай типы на тайп скрипт" | Inserts "создай типы на TypeScript" |
| Transcription error | Transcriber throws | Error propagates and nothing is inserted |

## Test Mapping

- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers recording start, short recording skip, preprocessing, glossary/language routing, normalization, insertion, silent audio, empty transcription, and error propagation.
- Manual: verify the menu bar app records while the configured hotkey is held and pastes final text into the active app when Accessibility permission is granted.

## Notes

Keep orchestration in `DictationPipeline` and user-facing app state coordination in `AppController`. Prefer fakes from `VoicePenTests/TestDoubles` for pipeline tests.

## Open Questions

- None.
