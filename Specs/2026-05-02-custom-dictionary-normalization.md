---
id: SPEC-003
status: implemented
updated: 2026-05-02
tests:
  - VoicePenTests/Dictionary/DictionaryCSVImporterTests.swift
  - VoicePenTests/Dictionary/DictionaryStoreTests.swift
  - VoicePenTests/Dictionary/PromptGlossaryBuilderTests.swift
  - VoicePenTests/Dictionary/TermNormalizerTests.swift
  - VoicePenTests/Dictionary/DictionaryEntryFilterTests.swift
---

# Custom Dictionary Normalization

## Problem

Technical dictation often produces phonetically correct but textually wrong terms, especially for product names, technologies, and mixed-language vocabulary.

## Behavior

Dictionary entries contain a canonical form and variants. VoicePen imports entries from CSV, stores them locally, builds glossary prompts for longer recordings, filters entries, and normalizes transcribed text with configured variants. CSV import requires every parsed entry to have a canonical form and at least one variant. It does not provide cloud dictionary sync, grammar rewriting, or semantic post-processing beyond configured term replacements.

## Acceptance Criteria

- When CSV input contains `canonical,variants`, VoicePen shall import canonical terms and split variants on semicolons.
- When CSV input contains any parsed entry without at least one non-empty variant, VoicePen shall reject the entire import without changing the existing dictionary.
- When dictionary entries are edited, VoicePen shall store, load, replace, and filter them locally.
- When the user clicks Add in the dictionary editor, VoicePen shall open an empty editable term draft on the first click even if another term was selected.
- When a prompt glossary is built, VoicePen shall produce deterministic, language-aware output that respects configured limits.
- When transcribed text contains configured variants, VoicePen shall replace them with canonical terms while preserving unrelated text.
- When dictionary data is empty or invalid, VoicePen shall fail predictably without corrupting existing data.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| CSV variants | `TypeScript,"тайп скрипт; type script"` | One canonical entry with two variants |
| Canonical only | `TypeScript` | Import is rejected and existing dictionary remains unchanged |
| Normalization | `создай типы на тайп скрипт` | `создай типы на TypeScript` |
| Word boundary | Variant inside a longer word | Text is not replaced inside unrelated words |
| Glossary limit | More entries than limit | Deterministic limited glossary |

## Test Mapping

- Automated: `VoicePenTests/Dictionary/DictionaryCSVImporterTests.swift` covers CSV parsing.
- Automated: `VoicePenTests/Dictionary/DictionaryStoreTests.swift` covers local storage behavior.
- Automated: CSV import tests cover rejection of canonical-only or partially valid imports without dictionary corruption.
- Automated: `VoicePenTests/Dictionary/PromptGlossaryBuilderTests.swift` covers glossary ordering, language, and limits.
- Automated: `VoicePenTests/Dictionary/TermNormalizerTests.swift` and `VoicePenTests/Dictionary/DictionaryEntryFilterTests.swift` cover replacement and filtering behavior.
- Manual: with an existing dictionary term selected, click Add once and verify the editor immediately shows an empty draft instead of the previously selected term.
- Manual: import a small CSV in the app and verify a configured spoken variant is inserted as the canonical term.

## Notes

Prefer deterministic sorting and explicit limits because glossary text is part of the transcription prompt. Avoid broad fuzzy matching unless a future spec defines it.

## Open Questions

- None.
