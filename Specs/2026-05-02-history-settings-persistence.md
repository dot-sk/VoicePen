---
id: SPEC-004
status: implemented
updated: 2026-05-06
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/Settings/UserConfigStoreTests.swift
  - VoicePenTests/History/VoiceHistoryStoreTests.swift
  - VoicePenTests/History/HistoryDayGroupsTests.swift
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
- When no hotkey hold duration has been saved, VoicePen shall use 0.15 seconds by default.
- When a hotkey hold duration is loaded or saved, VoicePen shall normalize it to the supported 0.1-0.5 second range.
- When no audio settings have been saved, VoicePen shall enable dictation microphone boost and Meeting voice leveling by default.
- When settings are updated, VoicePen shall persist them to SQLite and update published in-memory values.
- When a voice history entry is saved, VoicePen shall retain history rows without an application entry-count limit while using deterministic local size budgets for transcription text payloads.
- When the uncompressed transcription text budget is exceeded after saving an entry, VoicePen shall compress a fixed-size batch of oldest plain text-bearing rows instead of trimming to an exact byte target.
- When older history text is compressed to manage the local text budget, VoicePen shall preserve and restore raw and final text content when the row is loaded.
- When the total stored text payload budget is exceeded after compression, VoicePen shall evict a fixed-size batch of oldest text payloads while keeping the history rows.
- When older history text is compressed or evicted, VoicePen shall keep each history row's duration, status, timing, model metadata, app version used for decoding, and recognized word count so total dictated time and estimated time saved remain complete.
- When a voice history entry is saved after decoding, VoicePen shall store the app version used for that decoding alongside the transcription model metadata.
- When History detail shows processing metadata, VoicePen shall omit the app version row when the saved decoding app version is unknown.
- When General settings storage summary is shown, VoicePen shall show one approximate database disk usage value without splitting text payload and database sizes.
- When the History UI is shown, VoicePen shall not expose a file-reveal action for the SQLite history database; users inspect sessions through the in-app list and detail pane.
- When VoicePen shows total transcribed audio time, it shall label the total with recognized word count and countable session count.
- When VoicePen shows total transcribed audio time, it shall also show an approximate time-saved estimate by comparing recognized word count against a professional typing baseline.
- When VoicePen shows usage stats, it shall also show lightweight progress signals: active streak, words dictated today, best dictation day, the latest reached milestone, and the next milestone.
- When VoicePen computes usage milestones, it shall use a progressive ladder that mixes early wins, lifetime word volume, dictation count, active streak, best-day volume, and time saved so a single high-volume day cannot unlock the full ladder.
- When VoicePen computes active streak, it shall count consecutive local calendar days with at least one countable history entry, allowing the streak to remain active before today's first dictation when yesterday had activity.
- When VoicePen computes words dictated today and best dictation day, it shall use countable history entries and each entry's recognized word count.
- When the user clicks a visible history entry, VoicePen shall select that entry, show it as active in the list, and update the detail pane to that entry.
- When the user copies text from a visible history row, VoicePen shall temporarily replace that row's copy icon with a checkmark so the completed copy action is visible.
- When the user copies text from a visible history detail copy action, VoicePen shall temporarily replace that copy icon with a checkmark so the completed copy action is visible.
- Copy actions that show temporary copied feedback shall keep stable dimensions while switching between normal and copied states.
- When the user chooses to clear History, VoicePen shall ask for explicit confirmation before deleting saved history entries.
- When a history row has actions such as copy or delete, VoicePen shall keep hover controls available for pointer users and also expose the same actions through a row context menu and accessibility actions.
- When the history list shows a successful entry, VoicePen shall use a green checkmark without repeating a success label; non-success entries shall show a status or error reason.
- When the user opens a history entry detail, VoicePen shall show the final text immediately and keep the raw transcript in an expandable section.
- When the user opens a history entry detail, VoicePen shall show the repeat insertion action as an icon-only retry control.
- When the user opens a history entry detail, icon-only copy actions shall stay attached to the visible final text and expandable raw transcript sections.
- When the user expands raw transcript for one history entry, VoicePen shall keep that expansion state scoped to that entry rather than applying it to every history entry detail.
- When the History UI has visible entries from multiple local calendar days, VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.
- When the Open VoicePen at login setting is displayed, VoicePen shall reflect the current macOS login item status instead of only the last saved preference.
- When the main settings window shows its sidebar, VoicePen shall keep a flat settings list ordered with primary dictation settings before history, permissions, and app information.
- When tests touch persistence, they shall use temporary data paths rather than real user data directories.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| New database | Missing SQLite file | Current schema is created |
| Invalid language | Unsupported saved value | Default language is loaded |
| Missing hold duration | No saved hotkey hold duration | Hold duration defaults to 0.15 seconds |
| Long hold duration | Saved or entered hotkey hold duration is above 0.5 seconds | Hold duration is capped at 0.5 seconds |
| Missing audio settings | No saved audio setting values | Dictation microphone boost and Meeting voice leveling default to enabled |
| History append | New completed dictation | Entry appears first and stats update |
| History retention | More than 200 dictations are saved locally | All rows remain available, newest first, until explicitly deleted or cleared |
| History text budget | Plain stored `raw_text` and `final_text` exceed about 20 MiB total after saving | A fixed-size batch of oldest plain text payloads is compressed while newest text remains immediately plain; small budget overshoot is acceptable |
| History text payload cap | Stored plain plus compressed text payloads exceed about 20 MiB after compression | A fixed-size batch of oldest text payloads is evicted while rows, durations, metadata, and recognized word counts remain |
| Compressed history read | A compressed older row is loaded from SQLite | Raw and final text are restored into the history entry |
| History decode metadata | New completed dictation is saved | The entry stores both transcription model metadata and the app version used during decoding |
| Unknown history app version | Older history entry has no saved decoding app version | History detail omits the App version metadata row |
| Usage stats after text compression or eviction | Older text payloads are compressed or evicted by the budget | Total dictated duration and estimated time saved still include those retained rows |
| General storage display | History has saved rows | General settings show approximate database disk usage as one value |
| History database file | Open History | No history database reveal action is shown |
| Usage time saved | History contains completed dictations with recognized text | General settings shows estimated time saved versus manual typing at the professional typing baseline |
| Usage total caption | History contains completed dictations with recognized text | General settings labels the total with transcribed word count and session count |
| Lightweight progress stats | History contains entries across multiple days | General settings shows current streak, today's words, best day, latest reached milestone, and next milestone |
| Single high-volume day | One day contains thousands of dictated words | Early volume and daily-record milestones may unlock, but longer streak and elite lifetime milestones remain locked |
| History selection | Click an older visible history row | Row becomes active and the detail pane shows that row |
| History row copy feedback | Copy a row with final text | The row copy icon temporarily changes from copy to checkmark |
| History detail copy feedback | Copy final or raw transcript text from the detail pane | The clicked copy icon temporarily changes from copy to checkmark |
| Stable copy feedback | Copy action changes to copied feedback | The button keeps its existing dimensions |
| Clear history confirmation | Press Clear in History | A confirmation alert appears before saved history entries are deleted |
| History row actions | Secondary-click or use accessibility actions on a history row | Copy text and delete session are available without relying on hover-only controls |
| History success status | Entry inserted successfully | Row shows a green checkmark without `Insert attempted` text |
| History problem status | Entry is empty or failed | Row shows the status or error reason next to the status icon |
| History detail text | Selected entry has final and raw text | Final text is visible with its copy action; raw transcript is available under a disclosure with its own copy action |
| History repeat insertion | Open a history entry detail | The repeat insertion action is shown as an icon-only retry control |
| Raw transcript expansion | Expand raw transcript on one history entry, then select another entry | The other entry keeps its own raw transcript expansion state |
| History day groups | History contains entries from multiple local calendar days | Entries appear under sticky day sections while preserving newest-first order within each day |
| Open at login external change | macOS Login Items status changes outside VoicePen | VoicePen refreshes the toggle to the current system status |
| Settings sidebar | Open main VoicePen window | Primary dictation sections appear before history, permissions, and app information in a flat settings list |
| Test storage | Persistence test run | Temporary directory is used |

## Test Mapping

- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers schema migration.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers main window sidebar ordering, General usage total caption, one-value disk usage display, history processing metadata display, stable shared copy-button feedback, and history row context/accessibility actions.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that History does not expose a SQLite file-reveal action.
- Automated: `VoicePenTests/History/HistoryDayGroupsTests.swift` covers History and Meeting list grouping by local calendar day while preserving entry order.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` and `VoicePenTests/Settings/UserConfigStoreTests.swift` cover settings defaults, persistence, and normalization.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers launch-at-login updates and synchronization with current macOS login item status.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers unlimited local history rows, batch text compression, text payload eviction, storage stats, ordering, deletion, clearing, and persisted history metadata including app version.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers saving the app version used for decoding with voice history model metadata.
- Automated: `VoicePenTests/History/VoiceHistoryFilterTests.swift` and `VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift` cover history filtering, estimated time-saved usage stats, streaks, daily word counts, best day, latest reached milestone, and next milestone.
- Manual: open General settings with several history entries and verify the progress stats appear near the usage summary without success popups.
- Manual: open History with at least two entries, click a non-selected entry, and verify the row becomes active and the detail pane changes to that entry.
- Manual: hover a completed History row, copy it with the row copy button or double-click, and verify the row copy icon temporarily changes to a checkmark while the clipboard receives the row text.
- Manual: secondary-click a completed History row and verify Copy Text and Delete Session are available; verify keyboard or VoiceOver accessibility actions expose the same actions.
- Manual: verify successful History rows show only a green checkmark status, while empty or failed rows show a textual reason.
- Manual: select a completed History entry and verify final text is visible immediately while raw transcript is collapsed under a disclosure that can be expanded.
- Manual: expand Raw transcript on one History entry, select another entry, and verify the second entry keeps its own raw transcript expansion state.
- Manual: open History with entries from several days and verify sessions are grouped by day and the current day header sticks while scrolling.
- Manual: verify README local data paths match where a running development build creates its database.

## Notes

Keep tests on temporary directories. Any migration that changes stored data shape needs a regression test with an old-schema fixture or setup.

Use a single code-level professional typing baseline for estimated time saved. The baseline should stay above the broad average reported in large computer-user typing studies while remaining below competitive typing speeds.

## Open Questions

- None.
