---
id: SPEC-004
status: implemented
updated: 2026-05-03
tests:
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/Settings/AppEnvironmentSettingsStoreTests.swift
  - VoicePenTests/History/VoiceHistoryStoreTests.swift
  - VoicePenTests/History/VoiceHistoryFilterTests.swift
  - VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift
---

# History And Settings Persistence

## Problem

VoicePen needs to remember local settings, usage history, dictionary data, and timing information without analytics or runtime data collection.

## Behavior

VoicePen stores app data in a local SQLite database under Application Support, migrates schema as needed, normalizes settings values, stores voice history entries, filters history, and computes usage stats. It does not provide cloud sync, analytics events, remote telemetry, or multi-user account storage.

## Acceptance Criteria

- When the database opens, VoicePen shall create or update required tables without losing existing compatible data.
- When saved settings are missing or invalid, VoicePen shall load safe defaults.
- When settings are updated, VoicePen shall persist them to SQLite and update published in-memory values.
- When a voice history entry is saved, VoicePen shall retain history rows without an application entry-count limit while using deterministic local size budgets for transcription text payloads.
- When the uncompressed transcription text budget is exceeded after saving an entry, VoicePen shall compress a fixed-size batch of oldest plain text-bearing rows instead of trimming to an exact byte target.
- When older history text is compressed to manage the local text budget, VoicePen shall preserve and restore raw and final text content when the row is loaded.
- When the total stored text payload budget is exceeded after compression, VoicePen shall evict a fixed-size batch of oldest text payloads while keeping the history rows.
- When older history text is compressed or evicted, VoicePen shall keep each history row's duration, status, timing, model metadata, and recognized word count so total dictated time and estimated time saved remain complete.
- When the History UI is shown, VoicePen shall show an approximate local storage size for saved history without exposing transcription content.
- When VoicePen shows total transcribed audio time, it shall also show an approximate time-saved estimate by comparing recognized word count against a professional typing baseline.
- When the user clicks a visible history entry, VoicePen shall select that entry, show it as active in the list, and update the detail pane to that entry.
- When the user copies text from a visible history row, VoicePen shall temporarily replace that row's copy icon with a checkmark so the completed copy action is visible.
- When the history list shows a successful entry, VoicePen shall use a green checkmark without repeating a success label; non-success entries shall show a status or error reason.
- When the user opens a history entry detail, VoicePen shall show the final text immediately and keep the raw transcript in an expandable section.
- When the Open VoicePen at login setting is displayed, VoicePen shall reflect the current macOS login item status instead of only the last saved preference.
- When tests touch persistence, they shall use temporary data paths rather than real user data directories.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| New database | Missing SQLite file | Current schema is created |
| Invalid language | Unsupported saved value | Default language is loaded |
| History append | New completed dictation | Entry appears first and stats update |
| History retention | More than 200 dictations are saved locally | All rows remain available, newest first, until explicitly deleted or cleared |
| History text budget | Plain stored `raw_text` and `final_text` exceed about 20 MiB total after saving | A fixed-size batch of oldest plain text payloads is compressed while newest text remains immediately plain; small budget overshoot is acceptable |
| History text payload cap | Stored plain plus compressed text payloads exceed about 20 MiB after compression | A fixed-size batch of oldest text payloads is evicted while rows, durations, metadata, and recognized word counts remain |
| Compressed history read | A compressed older row is loaded from SQLite | Raw and final text are restored into the history entry |
| Usage stats after text compression or eviction | Older text payloads are compressed or evicted by the budget | Total dictated duration and estimated time saved still include those retained rows |
| History storage display | History has saved rows | UI shows approximate local history storage size |
| Usage time saved | History contains completed dictations with recognized text | General settings shows estimated time saved versus manual typing at the professional typing baseline |
| History selection | Click an older visible history row | Row becomes active and the detail pane shows that row |
| History row copy feedback | Copy a row with final text | The row copy icon temporarily changes from copy to checkmark |
| History success status | Entry inserted successfully | Row shows a green checkmark without `Insert attempted` text |
| History problem status | Entry is empty or failed | Row shows the status or error reason next to the status icon |
| History detail text | Selected entry has final and raw text | Final text is visible; raw transcript is available under a disclosure |
| Open at login external change | macOS Login Items status changes outside VoicePen | VoicePen refreshes the toggle to the current system status |
| Test storage | Persistence test run | Temporary directory is used |

## Test Mapping

- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers schema migration.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` and `VoicePenTests/Settings/AppEnvironmentSettingsStoreTests.swift` cover settings persistence and normalization.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers launch-at-login updates and synchronization with current macOS login item status.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers unlimited local history rows, batch text compression, text payload eviction, storage stats, ordering, deletion, clearing, and persisted history metadata.
- Automated: `VoicePenTests/History/VoiceHistoryFilterTests.swift` and `VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift` cover history filtering and estimated time-saved usage stats.
- Manual: open History with at least two entries, click a non-selected entry, and verify the row becomes active and the detail pane changes to that entry.
- Manual: hover a completed History row, copy it with the row copy button or double-click, and verify the row copy icon temporarily changes to a checkmark while the clipboard receives the row text.
- Manual: verify successful History rows show only a green checkmark status, while empty or failed rows show a textual reason.
- Manual: select a completed History entry and verify final text is visible immediately while raw transcript is collapsed under a disclosure that can be expanded.
- Manual: verify README local data paths match where a running development build creates its database.

## Notes

Keep tests on temporary directories. Any migration that changes stored data shape needs a regression test with an old-schema fixture or setup.

Use a single code-level professional typing baseline for estimated time saved. The baseline should stay above the broad average reported in large computer-user typing studies while remaining below competitive typing speeds.

## Open Questions

- None.
