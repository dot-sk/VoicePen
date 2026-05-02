---
id: SPEC-004
status: implemented
updated: 2026-05-02
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
- When voice history changes, VoicePen shall keep append, filtering, maximum entry count, and usage stats deterministic.
- When VoicePen shows total transcribed audio time, it shall also show an approximate time-saved estimate by comparing recognized word count against a professional typing baseline.
- When the user clicks a visible history entry, VoicePen shall select that entry, show it as active in the list, and update the detail pane to that entry.
- When the user copies text from a visible history row, VoicePen shall temporarily replace that row's copy icon with a checkmark so the completed copy action is visible.
- When the history list shows a successful entry, VoicePen shall use a green checkmark without repeating a success label; non-success entries shall show a status or error reason.
- When the user opens a history entry detail, VoicePen shall show the final text immediately and keep the raw transcript in an expandable section.
- When tests touch persistence, they shall use temporary data paths rather than real user data directories.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| New database | Missing SQLite file | Current schema is created |
| Invalid language | Unsupported saved value | Default language is loaded |
| History append | New completed dictation | Entry appears first and stats update |
| Usage time saved | History contains completed dictations with recognized text | General settings shows estimated time saved versus manual typing at the professional typing baseline |
| History selection | Click an older visible history row | Row becomes active and the detail pane shows that row |
| History row copy feedback | Copy a row with final text | The row copy icon temporarily changes from copy to checkmark |
| History success status | Entry inserted successfully | Row shows a green checkmark without `Insert attempted` text |
| History problem status | Entry is empty or failed | Row shows the status or error reason next to the status icon |
| History detail text | Selected entry has final and raw text | Final text is visible; raw transcript is available under a disclosure |
| Test storage | Persistence test run | Temporary directory is used |

## Test Mapping

- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers schema migration.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` and `VoicePenTests/Settings/AppEnvironmentSettingsStoreTests.swift` cover settings persistence and normalization.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift`, `VoicePenTests/History/VoiceHistoryFilterTests.swift`, and `VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift` cover history behavior and estimated time-saved usage stats.
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
