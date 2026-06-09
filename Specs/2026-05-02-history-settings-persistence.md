---
id: SPEC-004
status: implemented
updated: 2026-05-26
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/App/AppPathsTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/Settings/UserConfigStoreTests.swift
  - VoicePenTests/History/VoiceHistoryStoreTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift
  - VoicePenTests/History/VoiceHistoryFilterTests.swift
  - VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift
---

# History And Settings Persistence

## Problem

VoicePen needs to remember local settings, usage history, dictionary data, and timing information without analytics or runtime data collection.

## Behavior

VoicePen stores app data in a local SQLite database under Application Support, migrates schema as needed, normalizes settings values, stores voice history entries, filters history, and computes usage stats. It does not provide cloud sync, analytics events, remote telemetry, or multi-user account storage.

The Sessions UI adopts the shared transcript workspace from SPEC-015. Sessions
uses that shared layout for search, grouped saved-text navigation, the
read-only center text surface, and sidebar placement while keeping
session-specific persistence and actions here.

## Acceptance Criteria

- When the database opens, VoicePen shall create or update required tables without losing existing compatible data.
- When saved settings are missing or invalid, VoicePen shall load safe defaults.
- When settings migrate to the immediate push-to-talk model, VoicePen shall remove any stored hotkey hold-duration setting.
- When no audio settings have been saved, VoicePen shall enable system microphone voice processing, dictation microphone boost, and Meeting voice leveling by default.
- When no saved-recordings settings have been saved, VoicePen shall disable saved dictation recordings and saved Meeting recordings by default, and use a 5 GB saved-audio storage limit.
- When saved-recordings settings are updated, VoicePen shall persist the dictation toggle, Meeting toggle, and storage limit to SQLite using the same immediate settings path as other Settings controls.
- When a saved-audio storage limit is loaded or saved, VoicePen shall normalize it to the supported 1-50 GB range.
- When VoicePen creates required local directories, it shall create saved-recordings directories under Application Support, separate from temporary audio cleanup.
- When settings are updated, VoicePen shall persist them to SQLite and update published in-memory values.
- When a voice history entry is saved, VoicePen shall retain history rows without an application entry-count limit while using deterministic local size budgets for transcription text payloads.
- When the uncompressed transcription text budget is exceeded after saving an entry, VoicePen shall compress a fixed-size batch of oldest plain text-bearing rows instead of trimming to an exact byte target.
- When older history text is compressed to manage the local text budget, VoicePen shall preserve and restore raw and final text content when the row is loaded.
- When the total stored text payload budget is exceeded after compression, VoicePen shall evict a fixed-size batch of oldest text payloads while keeping the history rows.
- When older history text is compressed or evicted, VoicePen shall keep each history row's duration, status, timing, model metadata, app version used for decoding, and recognized word count so total dictated time and typing time avoided remain complete.
- When a voice history entry is saved after decoding, VoicePen shall store the app version used for that decoding alongside the transcription model metadata.
- When History detail shows processing metadata, VoicePen shall omit the app version row when the saved decoding app version is unknown.
- When About settings shows the App block, VoicePen shall group app status, privacy, local storage, and database path there.
- When Settings shows app launch controls, VoicePen shall show the Open at login setting near the top of the Settings screen.
- When Settings shows appearance controls, VoicePen shall let the user choose System, Light, or Dark theme; System shall follow the current macOS appearance.
- When the user changes the app theme setting, VoicePen shall persist the choice and apply it to the app immediately without restart.
- When Settings shows system access controls, VoicePen shall show permission statuses and request/refresh actions near the top of the Settings screen rather than as a standalone activity bar section.
- When About settings shows local storage, VoicePen shall show one approximate database disk usage value without splitting text payload and database sizes.
- When the Sessions UI is shown, VoicePen shall not expose a file-reveal action for the SQLite history database; users inspect sessions through the in-app list and detail pane.
- When the Sessions UI is shown, VoicePen shall use the shared transcript workspace described in SPEC-015.
- When Home is selected, VoicePen shall show a compact readiness strip as the only Home readiness status surface.
- When Home is ready, the readiness strip shall include the current push-to-talk shortcut hint and the Meeting recording Command-R hint.
- When Home is not ready, busy, or in a problem state, the readiness strip shall show the current app status without also showing `Ready`.
- When Home shows an actionable readiness problem, permission problems shall route from the readiness strip to Settings and a missing local transcription model shall route to Models; transient busy states shall not show a readiness-strip action.
- When Home shows usage stats, it shall emphasize typing time avoided for the current Monday-Sunday week by converting recognized word count with the professional typing baseline.
- When Home computes typing time avoided, it shall use recognized word count only and shall not subtract spoken audio duration.
- When Home shows weekly usage stats, it shall show weekly recognized word count, countable session count, spoken audio duration, current active streak, active days this week, best typing-time-avoided day this week, and best streak.
- When Home has no countable activity for the current week, the weekly value area and daily activity chart shall present a calm empty weekly state rather than an empty chart or an oversized zero-value headline.
- When Home shows daily typing-time-avoided activity, it shall include one bucket for each Monday-Sunday day, including days with no countable activity.
- When VoicePen shows usage milestones, the Home progress block shall identify the progress as lifetime or all-time so it does not read as part of the current-week totals.
- When VoicePen shows usage milestones, it shall continue to use the existing progressive lifetime milestone ladder for the Home progress block.
- When VoicePen shows usage stats, it shall also compute lightweight progress signals: active streak, words dictated today, best dictation day, best streak, the latest reached milestone, and the next milestone.
- When VoicePen computes usage milestones, it shall use a progressive ladder that mixes early wins, lifetime word volume, dictation count, active streak, best-day volume, and typing time avoided so a single high-volume day cannot unlock the full ladder.
- When VoicePen computes active streak and best streak, it shall count consecutive local calendar days with at least one countable history entry, allowing the current streak to remain active before today's first dictation when yesterday had activity.
- When VoicePen computes words dictated today and best dictation day, it shall use countable history entries and each entry's recognized word count.
- When the user clicks a visible history entry, VoicePen shall select that entry, show it as active in the list, and update the detail pane to that entry.
- When the user copies text from a visible history detail copy action, VoicePen shall temporarily replace that copy icon with a checkmark so the completed copy action is visible.
- Copy actions that show temporary copied feedback shall keep stable dimensions while switching between normal and copied states.
- When Sessions is shown, VoicePen shall not expose a bulk Clear action; saved voice sessions shall be removed through per-session delete actions.
- When a Sessions row is shown, VoicePen shall use the same compact status, timestamp, duration, and preview-text row structure as Meetings.
- When a Sessions row has actions such as copy or delete, VoicePen shall expose them through a row context menu and accessibility actions.
- When the history list shows a successful entry, VoicePen shall use a green checkmark without repeating a success label; non-success entries shall show a status or error reason.
- When the user opens a Sessions entry detail, VoicePen shall show final text in the center workspace.
- When a Sessions entry has no final text, VoicePen shall show a secondary error or status fallback and disable copy and repeat-insert actions for that entry.
- When Sessions search runs, VoicePen shall search visible final text, status, error, date/time, duration, local transcription model, and visible VoicePen app version metadata.
- When Sessions search runs, VoicePen shall not match raw transcript text.
- When the user opens a history entry detail, VoicePen shall show the repeat insertion action as an icon-only retry control.
- When the user copies or repeats insertion from Sessions, VoicePen shall use final text only.
- When the Sessions UI has visible entries from multiple local calendar days, VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.
- When the Open VoicePen at login setting is displayed, VoicePen shall reflect the current macOS login item status instead of only the last saved preference.
- When no feature-flag-only sections are enabled, the main window activity bar shall show Home, Meetings, and Sessions as primary navigation, followed by Settings icons ordered Dictionary, Model, Settings, and About.
- When tests touch persistence, they shall use temporary data paths rather than real user data directories.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| New database | Missing SQLite file | Current schema is created |
| Invalid language | Unsupported saved value | Default language is loaded |
| Removed hold duration | Existing database contains `hotkey.holdDuration` | Migration deletes the key and VoicePen starts push-to-talk immediately |
| Missing audio settings | No saved audio setting values | System microphone voice processing, dictation microphone boost, and Meeting voice leveling default to enabled |
| Missing saved-recordings settings | No saved recording values | Saved dictation and Meeting recordings are off, with a 5 GB storage limit |
| Saved-recordings settings | User toggles dictation or Meeting saving and changes the limit | Values persist and reload from SQLite |
| Saved-audio limit bounds | Saved or entered storage limit is outside 1-50 GB | Limit is clamped into the supported range |
| Saved-recordings path | VoicePen cleans stale temporary audio | Saved recordings under Application Support are preserved |
| History append | New completed dictation | Entry appears first and stats update |
| History retention | More than 200 dictations are saved locally | All rows remain available, newest first, until explicitly deleted or cleared |
| History text budget | Plain stored `raw_text` and `final_text` exceed about 20 MiB total after saving | A fixed-size batch of oldest plain text payloads is compressed while newest text remains immediately plain; small budget overshoot is acceptable |
| History text payload cap | Stored plain plus compressed text payloads exceed about 20 MiB after compression | A fixed-size batch of oldest text payloads is evicted while rows, durations, metadata, and recognized word counts remain |
| Compressed history read | A compressed older row is loaded from SQLite | Raw and final text are restored into the history entry |
| History decode metadata | New completed dictation is saved | The entry stores both transcription model metadata and the app version used during decoding |
| Unknown history app version | Older history entry has no saved decoding app version | History detail omits the App version metadata row |
| Usage stats after text compression or eviction | Older text payloads are compressed or evicted by the budget | Total dictated duration and typing time avoided still include those retained rows |
| About app details | Open About settings | The App block shows status, privacy, storage, and database path |
| Launch setting | Open Settings | Open at login appears near the top of the Settings screen |
| Theme setting | User changes Settings theme from System to Light or Dark | VoicePen persists the choice and updates the app appearance immediately |
| Permission controls | Open Settings | Permission statuses and request/refresh actions appear near the top of Settings |
| About storage display | History has saved rows | About settings show approximate database disk usage as one value |
| History database file | Open Sessions | No history database reveal action is shown |
| Home ready status | App is ready | Home shows one readiness strip with the current push-to-talk hint and Meeting recording Command-R hint |
| Home not ready status | Microphone, Accessibility, model, busy, or error state is active | Home readiness strip shows the current non-ready status without also saying `Ready` |
| Home actionable status | Permission or model setup is missing | Home readiness strip can route the user to Settings for permissions or Models for model setup |
| Weekly typing time avoided | Current week contains completed dictations with recognized text | Home emphasizes weekly typing time avoided from recognized word count at the professional typing baseline |
| Weekly usage summary | Current week contains countable dictations | Home shows weekly recognized word count, countable sessions, spoken audio, and daily typing-time-avoided activity buckets |
| Weekly empty state | Current week has no countable dictations | Home presents a weekly empty state and an empty daily activity state without implying lifetime milestone progress is weekly progress |
| Weekly zero days | Current week has days without countable dictations | Home keeps those days visible in the Monday-Sunday activity buckets with zero typing time avoided |
| Lightweight progress stats | History contains entries across multiple days | Home shows current streak, all-time best streak, best typing-time-avoided day this week, latest reached milestone, and next lifetime milestone |
| Single high-volume day | One day contains thousands of dictated words | Early volume and daily-record milestones may unlock, but longer streak and elite lifetime milestones remain locked |
| History selection | Click an older visible history row | Row becomes active and the detail pane shows that row |
| History detail copy feedback | Copy final text from the detail pane | The clicked copy icon temporarily changes from copy to checkmark |
| Stable copy feedback | Copy action changes to copied feedback | The button keeps its existing dimensions |
| Sessions bulk clear | Open Sessions | No bulk Clear action is exposed; individual saved sessions can still be deleted |
| History row layout | Open Sessions with saved rows | Rows use the compact status, timestamp, duration, and preview-text structure used by Meetings |
| History row actions | Secondary-click or use accessibility actions on a history row | Copy text and delete session are available |
| History success status | Entry inserted successfully | Row shows a green checkmark without `Insert attempted` text |
| History problem status | Entry is empty or failed | Row shows the status or error reason next to the status icon |
| History detail text | Selected entry has final and raw text | Final text is visible in the shared center workspace; raw transcript is not shown in Sessions |
| Empty final text | Selected entry has raw text but no final text | Sessions shows an error or status fallback and disables copy and repeat insertion |
| History repeat insertion | Open a history entry detail | The repeat insertion action is shown as an icon-only retry control |
| Raw transcript search | Search for text that appears only in raw transcript | Sessions does not match that entry |
| History day groups | History contains entries from multiple local calendar days | Entries appear under sticky day sections while preserving newest-first order within each day |
| Open at login external change | macOS Login Items status changes outside VoicePen | VoicePen refreshes the toggle to the current system status |
| Activity bar | Open main VoicePen window without feature-flag-only sections | Activity bar shows Home, Meetings, Sessions, then Settings icons for Dictionary, Model, Settings, and About |
| Test storage | Persistence test run | Temporary directory is used |

## Test Mapping

- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers schema migration.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers main window activity bar grouping and ordering, Home usage data wiring, Home actionable status routing, Settings launch and permission placement, About App block placement, one-value disk usage display, history processing metadata display, stable shared copy-button feedback, and Sessions row layout and context/accessibility actions.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that History does not expose a SQLite file-reveal action.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift` covers shared list grouping by local calendar day while preserving entry order.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` and `VoicePenTests/Settings/UserConfigStoreTests.swift` cover settings defaults, persistence, and normalization, including app appearance mode.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers deleting the removed hotkey hold-duration setting during migration.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers saved-recordings defaults, persistence, and storage-limit clamping.
- Automated: `VoicePenTests/App/AppPathsTests.swift` covers saved-recordings directories under Application Support and preservation during temporary-audio cleanup.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers launch-at-login updates, synchronization with current macOS login item status, and app appearance application.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers unlimited local history rows, batch text compression, text payload eviction, storage stats, ordering, deletion, clearing, and persisted history metadata including app version.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers saving the app version used for decoding with voice history model metadata.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift`, `VoicePenTests/History/VoiceHistoryFilterTests.swift`, and `VoicePenTests/History/VoiceTranscriptionUsageStatsTests.swift` cover shared filtering mechanics, Sessions search field indexing, typing-time-avoided usage stats, weekly buckets, streaks, best streak, daily word counts, best day, latest reached milestone, and next milestone.
- Manual: open Home with empty and populated history in light and dark mode; verify the readiness strip, weekly dashboard, daily activity chart, and milestone progress read as one compact dashboard.
- Manual: open Settings and verify the Open at login control appears near the top.
- Manual: open Settings and verify permission statuses and request/refresh actions appear near the top.
- Manual: open About settings and verify the App block contains status, privacy, storage, and database path.
- Manual: open Sessions with at least two entries, click a non-selected entry, and verify the row becomes active and the detail pane changes to that entry.
- Manual: copy a completed Sessions row from the row context menu, and verify the clipboard receives the row text.
- Manual: secondary-click a completed Sessions row and verify Copy Text and Delete Session are available; verify keyboard or VoiceOver accessibility actions expose the same actions.
- Manual: verify successful Sessions rows show only a green checkmark status, while empty or failed rows show a textual reason.
- Manual: select a completed Sessions entry and verify final text is visible immediately in the center workspace while raw transcript is not shown.
- Manual: open Sessions with entries from several days and verify sessions are grouped by day and the current day header sticks while scrolling.
- Manual: verify README local data paths match where a running development build creates its database.

## Notes

Keep tests on temporary directories. Any migration that changes stored data shape needs a regression test with an old-schema fixture or setup.

Use a single code-level professional typing baseline for typing time avoided. The baseline should stay above the broad average reported in large computer-user typing studies while remaining below competitive typing speeds.

## Open Questions

- None.
