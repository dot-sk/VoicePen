---
id: SPEC-005
status: implemented
updated: 2026-05-02
tests:
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/History/VoiceHistoryStoreTests.swift
  - VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift
  - VoicePenTests/Dictionary/DictionaryCSVImporterTests.swift
  - VoicePenTests/Dictionary/DictionaryStoreTests.swift
  - VoicePenTests/Dictionary/DictionaryWordDiffTests.swift
  - VoicePenTests/Dictionary/DictionaryMergerTests.swift
  - VoicePenTests/Dictionary/DictionaryReviewPromptBuilderTests.swift
  - VoicePenTests/Dictionary/DictionaryImportPreviewBuilderTests.swift
---

# GPT-Assisted Dictionary Review

## Problem

VoicePen users who dictate technical or product work text need an easy way to improve their custom dictionary from real transcription history. The app should help package useful local context for external review without adding cloud integrations, local model analysis, or automatic dictionary mutation.

## Behavior

VoicePen records which transcription model produced each saved history entry for local app behavior. VoicePen then lets the user copy a ready-to-send dictionary review prompt containing a configurable bounded set of recent transcription history and current dictionary entries. The user can choose from prompt presets for different review goals. The prompt asks an external assistant to return CSV in VoicePen's existing dictionary import format. The user can then copy that CSV response or save it to a file, preview its impact on past transcriptions, and import it through the same dictionary import flow.

VoicePen does not analyze suspicious words locally, call external AI services, auto-generate dictionary entries, or update the dictionary without an explicit user import action.

## Acceptance Criteria

- When the user requests a dictionary review prompt, VoicePen shall let the user choose a prompt preset and copy a prompt that explains the dictionary format and asks for CSV-only output.
- When VoicePen shows dictionary review controls, it shall present them in a standalone dictionary-level area above the dictionary editor rather than inside the selected term editor.
- When the user chooses the default dictionary improvement preset, VoicePen shall ask the external assistant to infer useful dictionary entries from recurring or obvious raw/final transcription differences.
- When the user chooses the default dictionary improvement preset, VoicePen shall explain that dictionary entries are prompt context rather than literal search-and-replace rules: exact technical artifacts should keep exact spelling, while ordinary-word canonicals may act as meaning hints for the downstream model.
- When the user chooses a technical terms preset, VoicePen shall bias the prompt toward product names, programming languages, frameworks, libraries, APIs, CLI tools, product-management terms, company vocabulary, and mixed-language work vocabulary.
- When the user chooses a product work preset, VoicePen shall bias the prompt toward feature names, metrics, roadmap terms, customer names, team names, Jira or tracker terminology, and business vocabulary.
- When building any dictionary review prompt, VoicePen shall tell the external assistant to keep the dictionary small by adding only high-confidence, high-irritation corrections from clear raw/final differences, leaving terms alone when the model already handled them.
- When building the default dictionary improvement prompt, VoicePen shall allow `raw_text == final_text` candidates only when the phrase is still an obvious high-impact technical artifact mistake or recurring malformed word.
- When building the default dictionary improvement prompt, VoicePen shall ask the external assistant to do a dedicated recovery pass over `raw_text == final_text` rows for still-broken high-impact technical phrases, workflow terms, file formats, programming terms, and project conventions.
- When building the default dictionary improvement prompt, VoicePen shall ask the external assistant to prefer phrase-level variants when a standalone mistaken variant is also a valid ordinary word that could create false corrections.
- When building the default dictionary improvement prompt, VoicePen shall tell the external assistant not to collect transient tool or product mentions merely because they appeared in history.
- When the external assistant cannot find strong dictionary candidates, the prompt shall prefer a CSV header with no entries over low-confidence filler entries.
- When VoicePen saves a completed transcription history entry, it shall store the selected model metadata used for that transcription.
- When building the prompt, VoicePen shall include current dictionary entries so external review can avoid duplicates.
- When building the prompt, VoicePen shall let the user choose a shared history review limit from fixed options and include that many newest eligible history entries with raw text and final text only.
- When the user has not chosen a history entry limit, VoicePen shall default to 50 entries.
- When building the prompt, VoicePen shall not include model identifiers, backend names, model versions, or model performance statistics.
- When history contains entries that are not `insertAttempted`, have empty raw text after trimming, or have empty final text after trimming, VoicePen shall exclude them from the review prompt and import impact preview.
- When the user copies a dictionary review prompt, VoicePen shall make clear that prompt data is copied to the local clipboard and may contain transcription history before the user sends it anywhere else.
- When the user imports dictionary CSV from a file or the clipboard, VoicePen shall parse and validate it through the same dictionary import path and show an impact preview before merging valid entries into the dictionary.
- When importing dictionary CSV from any source, VoicePen shall reject input unless it contains at least one entry and every parsed entry has a non-empty canonical value and at least one non-empty variant.
- When showing an import impact preview, VoicePen shall simulate the exact dictionary state that would exist after confirmed import, including the existing dictionary merge, deduplication, and overwrite rules.
- When showing an import impact preview, VoicePen shall use the shared history review limit, defaulting to 50 when the user has not chosen one, and show how many eligible entries would change.
- When showing an import impact preview, VoicePen shall clearly show that the user can return without importing and shall identify the terms that would be imported.
- When showing an import impact preview, VoicePen shall show up to 10 highlighted examples while still counting all changed eligible entries within the selected limit.
- When the simulated dictionary changes a history entry, VoicePen shall show word-level highlighting between the current final text and the simulated final text using deterministic whitespace token comparison that preserves punctuation inside displayed tokens.
- When the user confirms the import preview, VoicePen shall merge the valid entries into the dictionary.
- When the user cancels the import preview, VoicePen shall leave the dictionary unchanged.
- When a valid import would change no recent history entries, VoicePen shall still show a preview with zero affected entries before the user confirms or cancels.
- When imported CSV is invalid or empty, VoicePen shall show a predictable error and shall not corrupt the existing dictionary.
- VoicePen shall not send prompt data to any network service automatically.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default prompt | Dictionary has `TypeScript`; history has raw/final pairs with model metadata | Clipboard contains dictionary-improvement instructions, current dictionary, and eligible history without model metadata |
| Exact artifact | History suggests `AGENTS.md` through malformed spoken variants | Prompt asks GPT to keep exact artifact spelling as canonical |
| Linguistic hint | History has repeated malformed Russian word forms | Prompt allows a base-word canonical such as `модель` to guide contextual inflection |
| Conservative prompt | History contains terms already correctly transcribed | Prompt asks GPT not to add entries for terms the model already handled |
| Transient mention | History mentions a terminal tool in side discussion without recurring mistaken variants | Prompt asks GPT not to add the tool name just because it was mentioned |
| Review controls | User opens Dictionary settings with any term selected | GPT review controls appear above the dictionary editor, not in the selected term form |
| Technical terms prompt | History contains developer or product vocabulary | Clipboard prompt asks GPT to focus on technical/work terms while returning dictionary CSV only |
| Product work prompt | History contains roadmap, metric, customer, or tracker vocabulary | Clipboard prompt asks GPT to focus on product-management vocabulary while returning dictionary CSV only |
| Failed history | History entry has status `failed` | Entry is not included in prompt or impact preview |
| Textless history | History entry has empty raw or final text | Entry is not included in prompt or impact preview |
| History metadata | Stored history contains ids, timestamps, and model metadata | Prompt does not include ids, timestamps, model fields, or model stats |
| GPT response | Clipboard or file contains `canonical,variants` CSV | VoicePen shows import impact before changing the dictionary |
| Prose response | Clipboard or file contains explanatory prose without variants | Import is rejected because at least one parsed entry lacks variants |
| Partially valid CSV | CSV has one valid row and one canonical-only row | Entire import is rejected and dictionary remains unchanged |
| Impact preview | New dictionary would change `тайп скрипт` to `TypeScript` in older history | Preview shows changed words highlighted between current and simulated text |
| Zero impact preview | Valid CSV would not change recent history | Preview shows zero affected entries and allows confirm or cancel |
| Import preview exit | User opens clipboard import preview by mistake | Preview has an obvious way to return without changing the dictionary |
| Confirm preview | User approves valid imported entries | Entries are imported through existing dictionary merge behavior |
| Cancel preview | User cancels valid imported entries | Dictionary remains unchanged |
| Invalid response | Clipboard or file contains prose or malformed CSV | Dictionary remains unchanged and user sees an error |

## Test Mapping

- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers saving, loading, and `Unknown` export fallback for transcription model metadata on history entries.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers adding nullable model metadata storage while preserving existing history rows.
- Automated: `VoicePenTests/Transcription/RoutingTranscriptionClientTests.swift` and `VoicePenTests/App/AppControllerTests.swift` cover carrying the model metadata actually used for a transcription into saved history, even if the selected model changes before history is written.
- Automated: `VoicePenTests/Dictionary/DictionaryReviewPromptBuilderTests.swift` covers prompt assembly, preset selection, dictionary inclusion, raw/final history inclusion, history filtering, ordering, default limit, selected limit, and clipboard disclosure presence without locking exact prompt wording.
- Automated: `VoicePenTests/Dictionary/DictionaryMergerTests.swift` covers pure dictionary merge simulation for canonical overwrite, duplicate variant ownership, trimming, and deduplication.
- Automated: `VoicePenTests/Dictionary/DictionaryImportPreviewBuilderTests.swift` covers exact merge-rule simulation, selected history review limits, simulated history changes, unchanged histories, eligible history filtering, injected merge dependencies, and zero-impact previews.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers copying review prompts, preparing clipboard import previews without mutating the dictionary, confirming previews through the shared dictionary import path, and rejecting stale previews after dictionary changes.
- Automated: `VoicePenTests/Dictionary/DictionaryWordDiffTests.swift` covers unchanged text, single-word changes, multi-word changes, and punctuation-adjacent changes.
- Automated: `VoicePenTests/Dictionary/DictionaryCSVImporterTests.swift` and `VoicePenTests/Dictionary/DictionaryStoreTests.swift` cover valid file and clipboard-compatible CSV parsing, invalid input, prose rejection, partially valid import rejection, import merge behavior, and dictionary-corruption prevention.
- Manual: open Dictionary settings, select different terms, and verify Review with GPT remains above the dictionary editor rather than moving inside the selected term editor.
- Manual: copy the review prompt, paste it into GPT, copy a CSV-only response or save it as a file, import it, verify the impact preview highlights changed words, confirm import, and verify new dictionary entries appear in VoicePen.

## Notes

Keep the flow local and user-initiated. The review prompt may contain user transcription text, so copying it must be an explicit action. Use the existing dictionary CSV format: `canonical,variants`, where variants are semicolon-separated. The prompt should instruct external assistants to quote CSV fields that contain commas or quotes. File and clipboard imports must share parsing, validation, preview, and merge behavior; every parsed entry must contain both a canonical value and at least one variant.

Store enough model metadata for local history and diagnostics without depending on a future manifest lookup: model id, display name, backend or source kind, and version. Adding this storage must be backward-compatible, and dictionary review prompts must not export those model fields.

The import impact preview should compare the current stored final text with the simulated final text produced by applying the post-import dictionary to the stored raw transcript. It should not infer suspicious words, call external models, or alter saved history.

Initial prompt presets should be limited to dictionary improvement, technical terms, and product work. Initial history review limit options should be 10, 50, and 100 entries, with 50 as the default. The selected history review limit applies to both prompt export and import impact preview. Prefer deterministic ordering and bounded history limits so prompt output is stable and testable.

## Open Questions

- None.
