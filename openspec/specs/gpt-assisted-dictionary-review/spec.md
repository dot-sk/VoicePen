# GPT-Assisted Dictionary Review Specification

## Purpose

VoicePen users who dictate technical or product work text need an easy way to improve their custom dictionary from real transcription history. The app should help package useful local context for external review without adding cloud integrations, local model analysis, or automatic dictionary mutation.

## Requirements

### Requirement: GPT-Assisted Dictionary Review

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen records which transcription model produced each saved history entry for local app behavior. VoicePen then lets the user copy a ready-to-send dictionary review prompt containing a configurable bounded set of recent transcription history and current dictionary entries. The user can choose from prompt presets for different review goals. The prompt asks an external assistant to return CSV in VoicePen's existing dictionary import format. The user can then copy that CSV response or save it to a file, preview its impact on past transcriptions, and import it through the same dictionary import flow.

VoicePen does not analyze suspicious words locally, call external AI services, auto-generate dictionary entries, or update the dictionary without an explicit user import action.

#### Scenario: User requests a dictionary review prompt

- **WHEN** the user requests a dictionary review prompt
- **THEN** VoicePen shall let the user choose a prompt preset and copy a prompt that explains the dictionary format and asks for CSV-only output.

#### Scenario: Shows dictionary review controls

- **WHEN** VoicePen shows dictionary review controls
- **THEN** it shall present them in a standalone dictionary-level area above the dictionary editor rather than inside the selected term editor.

#### Scenario: User chooses the default dictionary improvement preset

- **WHEN** the user chooses the default dictionary improvement preset
- **THEN** VoicePen shall ask the external assistant to infer useful dictionary entries from recurring or obvious raw/final transcription differences.

#### Scenario: User chooses the default dictionary improvement preset 2

- **WHEN** the user chooses the default dictionary improvement preset
- **THEN** VoicePen shall explain that dictionary entries are prompt context rather than literal search-and-replace rules: exact technical artifacts should keep exact spelling, while ordinary-word canonicals may act as meaning hints for the downstream model.

#### Scenario: User chooses a technical terms preset

- **WHEN** the user chooses a technical terms preset
- **THEN** VoicePen shall bias the prompt toward product names, programming languages, frameworks, libraries, APIs, CLI tools, product-management terms, company vocabulary, and mixed-language work vocabulary.

#### Scenario: User chooses a product work preset

- **WHEN** the user chooses a product work preset
- **THEN** VoicePen shall bias the prompt toward feature names, metrics, roadmap terms, customer names, team names, Jira or tracker terminology, and business vocabulary.

#### Scenario: Building any dictionary review prompt

- **WHEN** building any dictionary review prompt
- **THEN** VoicePen shall tell the external assistant to keep the dictionary small by adding only high-confidence, high-irritation corrections from clear raw/final differences, leaving terms alone when the model already handled them.

#### Scenario: Building the default dictionary improvement prompt

- **WHEN** building the default dictionary improvement prompt
- **THEN** VoicePen shall allow `raw_text == final_text` candidates only when the phrase is still an obvious high-impact technical artifact mistake or recurring malformed word.

#### Scenario: Building the default dictionary improvement prompt 2

- **WHEN** building the default dictionary improvement prompt
- **THEN** VoicePen shall ask the external assistant to do a dedicated recovery pass over `raw_text == final_text` rows for still-broken high-impact technical phrases, workflow terms, file formats, programming terms, and project conventions.

#### Scenario: Building the default dictionary improvement prompt 3

- **WHEN** building the default dictionary improvement prompt
- **THEN** VoicePen shall ask the external assistant to prefer phrase-level variants when a standalone mistaken variant is also a valid ordinary word that could create false corrections.

#### Scenario: Building the default dictionary improvement prompt 4

- **WHEN** building the default dictionary improvement prompt
- **THEN** VoicePen shall tell the external assistant not to collect transient tool or product mentions merely because they appeared in history.

#### Scenario: External assistant cannot find strong dictionary candidates

- **WHEN** the external assistant cannot find strong dictionary candidates
- **THEN** the prompt shall prefer a CSV header with no entries over low-confidence filler entries.

#### Scenario: Saves a completed transcription history entry

- **WHEN** VoicePen saves a completed transcription history entry
- **THEN** it shall store the selected model metadata and VoicePen app version used for that transcription.

#### Scenario: Building the prompt

- **WHEN** building the prompt
- **THEN** VoicePen shall include current dictionary entries so external review can avoid duplicates.

#### Scenario: Building the prompt 2

- **WHEN** building the prompt
- **THEN** VoicePen shall let the user choose a shared history review limit from fixed options and include that many newest eligible history entries with raw text and final text only.

#### Scenario: User has not chosen a history entry limit

- **WHEN** the user has not chosen a history entry limit
- **THEN** VoicePen shall default to 50 entries.

#### Scenario: Building the prompt 3

- **WHEN** building the prompt
- **THEN** VoicePen shall not include model identifiers, backend names, model versions, VoicePen app versions, or model performance statistics.

#### Scenario: History contains entries that are not insertAttempted, have empty raw text after trimming, or

- **WHEN** history contains entries that are not `insertAttempted`, have empty raw text after trimming, or have empty final text after trimming
- **THEN** VoicePen shall exclude them from the review prompt and import impact preview.

#### Scenario: User copies a dictionary review prompt

- **WHEN** the user copies a dictionary review prompt
- **THEN** VoicePen shall make clear that prompt data is copied to the local clipboard and may contain transcription history before the user sends it anywhere else.

#### Scenario: User copies a dictionary review prompt 2

- **WHEN** the user copies a dictionary review prompt
- **THEN** VoicePen shall show temporary copied feedback on the copy action.

#### Scenario: Copy actions that show temporary copied feedback

- **WHEN** this capability applies
- **THEN** Copy actions that show temporary copied feedback shall keep stable dimensions while switching between normal and copied states.

#### Scenario: User imports dictionary CSV from a file or the clipboard

- **WHEN** the user imports dictionary CSV from a file or the clipboard
- **THEN** VoicePen shall parse and validate it through the same dictionary import path and show an impact preview before merging valid entries into the dictionary.

#### Scenario: Importing dictionary CSV from any source

- **WHEN** importing dictionary CSV from any source
- **THEN** VoicePen shall reject input unless it contains at least one entry and every parsed entry has a non-empty canonical value and at least one non-empty variant.

#### Scenario: Showing an import impact preview

- **WHEN** showing an import impact preview
- **THEN** VoicePen shall simulate the exact dictionary state that would exist after confirmed import, including the existing dictionary merge, deduplication, and overwrite rules.

#### Scenario: Showing an import impact preview 2

- **WHEN** showing an import impact preview
- **THEN** VoicePen shall use the shared history review limit, defaulting to 50 when the user has not chosen one, and show how many eligible entries would change.

#### Scenario: Showing an import impact preview 3

- **WHEN** showing an import impact preview
- **THEN** VoicePen shall clearly show that the user can return without importing and shall identify the terms that would be imported.

#### Scenario: Showing an import impact preview 4

- **WHEN** showing an import impact preview
- **THEN** VoicePen shall show up to 10 highlighted examples while still counting all changed eligible entries within the selected limit.

#### Scenario: Simulated dictionary changes a history entry

- **WHEN** the simulated dictionary changes a history entry
- **THEN** VoicePen shall show word-level highlighting between the current final text and the simulated final text using deterministic whitespace token comparison that preserves punctuation inside displayed tokens.

#### Scenario: User confirms the import preview

- **WHEN** the user confirms the import preview
- **THEN** VoicePen shall merge the valid entries into the dictionary.

#### Scenario: User cancels the import preview

- **WHEN** the user cancels the import preview
- **THEN** VoicePen shall leave the dictionary unchanged.

#### Scenario: Valid import would change no recent history entries

- **WHEN** a valid import would change no recent history entries
- **THEN** VoicePen shall still show a preview with zero affected entries before the user confirms or cancels.

#### Scenario: Imported CSV is invalid or empty

- **WHEN** imported CSV is invalid or empty
- **THEN** VoicePen shall show a predictable error and shall not corrupt the existing dictionary.

#### Scenario: User imports dictionary CSV from the clipboard and the clipboard is empty or does

- **WHEN** the user imports dictionary CSV from the clipboard and the clipboard is empty or does not contain valid dictionary CSV
- **THEN** VoicePen shall not open the import preview and shall leave any existing import preview state closed.

#### Scenario: Dictionary import preview is open

- **WHEN** the dictionary import preview is open
- **THEN** Escape shall close the preview without changing the dictionary.

#### Scenario: Shall not send prompt data to any network service automatically

- **WHEN** this capability applies
- **THEN** VoicePen shall not send prompt data to any network service automatically.
