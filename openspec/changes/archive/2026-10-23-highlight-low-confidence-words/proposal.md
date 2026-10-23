## Why

Saved dictation text gives no indication of words the recognizer was unsure about. Marking those words can focus review without rewriting the recognized text or running another model.

## What Changes

- Carry available native token confidence through dictation and store review hints with the saved text.
- Highlight uncertain words in Sessions detail and provide a textual explanation; ordinary words stay visually unchanged.
- Preserve plain text copying and insertion. Older sessions and recognizers without usable confidence remain readable without fabricated estimates.
- Support Whisper native decoder probabilities and complete native GigaAM CTC score retention plus its Swift adapter. Use separately reviewed backend policies without extra inference.

## Capabilities

### New Capabilities

- `dictation-word-confidence`: optional word review hints in saved dictations, persistence, and missing-data behavior.

### Modified Capabilities

None.

## Impact

Transcription result metadata and routing, native Whisper result extraction, dictation text mapping, history persistence and payload lifecycle, Sessions text rendering, automated tests. The native GigaAM package advances to a distinct locally verified candidate using the same weights. No meeting highlighting, punctuation restoration, rich-text insertion, additional model, or model-selection change.
