# History And Settings Persistence Specification

## Purpose

VoicePen needs to remember local settings, usage history, dictionary data, and timing information without analytics or runtime data collection.

## Requirements

### Requirement: History And Settings Persistence

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen stores app data in a local SQLite database under Application Support, migrates schema as needed, normalizes settings values, stores voice history entries, filters history, and computes usage stats. It does not provide cloud sync, analytics events, remote telemetry, or multi-user account storage.

The Sessions UI adopts the shared transcript workspace from `shared-transcript-workspace` capability. Sessions
uses that shared layout for search, grouped saved-text navigation, the
read-only center text surface, and sidebar placement while keeping
session-specific persistence and actions here.

#### Scenario: Database opens

- **WHEN** the database opens
- **THEN** VoicePen shall create or update required tables without losing existing compatible data.

#### Scenario: Saved settings are missing or invalid

- **WHEN** saved settings are missing or invalid
- **THEN** VoicePen shall load safe defaults.

#### Scenario: Settings migrate to the immediate push-to-talk model

- **WHEN** settings migrate to the immediate push-to-talk model
- **THEN** VoicePen shall remove any stored hotkey hold-duration setting.

#### Scenario: No audio settings have been saved

- **WHEN** no audio settings have been saved
- **THEN** VoicePen shall enable dictation microphone boost, and Meeting voice leveling by default.

#### Scenario: No saved-recordings settings have been saved

- **WHEN** no saved-recordings settings have been saved
- **THEN** VoicePen shall disable saved dictation recordings and saved Meeting recordings by default, and use a 5 GB saved-audio storage limit.

#### Scenario: Saved-recordings settings are updated

- **WHEN** saved-recordings settings are updated
- **THEN** VoicePen shall persist the dictation toggle, Meeting toggle, and storage limit to SQLite using the same immediate settings path as other Settings controls.

#### Scenario: Saved-audio storage limit is loaded or saved

- **WHEN** a saved-audio storage limit is loaded or saved
- **THEN** VoicePen shall normalize it to the supported 1-50 GB range.

#### Scenario: Creates required local directories

- **WHEN** VoicePen creates required local directories
- **THEN** it shall create saved-recordings directories under Application Support, separate from temporary audio cleanup.

#### Scenario: Settings are updated

- **WHEN** settings are updated
- **THEN** VoicePen shall persist them to SQLite and update published in-memory values.

#### Scenario: Voice history entry is saved

- **WHEN** a voice history entry is saved
- **THEN** VoicePen shall retain history rows without an application entry-count limit while using deterministic local size budgets for transcription text payloads.

#### Scenario: Archived saved-recording audio file is associated with a voice history entry

- **WHEN** an archived saved-recording audio file is associated with a voice history entry
- **THEN** VoicePen shall keep that association with the history entry.

#### Scenario: Uncompressed transcription text budget is exceeded after saving an entry

- **WHEN** the uncompressed transcription text budget is exceeded after saving an entry
- **THEN** VoicePen shall compress a fixed-size batch of oldest plain text-bearing rows instead of trimming to an exact byte target.

#### Scenario: Older history text is compressed to manage the local text budget

- **WHEN** older history text is compressed to manage the local text budget
- **THEN** VoicePen shall preserve and restore raw and final text content when the row is loaded.

#### Scenario: Total stored text payload budget is exceeded after compression

- **WHEN** the total stored text payload budget is exceeded after compression
- **THEN** VoicePen shall evict a fixed-size batch of oldest text payloads while keeping the history rows.

#### Scenario: Older history text is compressed or evicted

- **WHEN** older history text is compressed or evicted
- **THEN** VoicePen shall keep each history row's duration, status, timing, model metadata, app version used for decoding, and recognized word count so total dictated time and typing time avoided remain complete.

#### Scenario: Voice history entry is saved after decoding

- **WHEN** a voice history entry is saved after decoding
- **THEN** VoicePen shall store the app version used for that decoding alongside the transcription model metadata.

#### Scenario: History detail shows processing metadata

- **WHEN** History detail shows processing metadata
- **THEN** VoicePen shall omit the app version row when the saved decoding app version is unknown.

#### Scenario: About settings shows the App block

- **WHEN** About settings shows the App block
- **THEN** VoicePen shall group app status, privacy, local storage, and database path there.

#### Scenario: Settings shows app launch controls

- **WHEN** Settings shows app launch controls
- **THEN** VoicePen shall show the Open at login setting and reflect the current macOS login item status.

#### Scenario: Settings shows appearance controls

- **WHEN** Settings shows appearance controls
- **THEN** VoicePen shall let the user choose System, Light, or Dark theme; System shall follow the current macOS appearance.

#### Scenario: User changes the app theme setting

- **WHEN** the user changes the app theme setting
- **THEN** VoicePen shall persist the choice and apply it to the app immediately without restart.

#### Scenario: Settings shows system access controls

- **WHEN** Settings shows system access controls
- **THEN** VoicePen shall show permission statuses and request/refresh actions in Settings rather than as a standalone activity bar section.

#### Scenario: About settings shows local storage

- **WHEN** About settings shows local storage
- **THEN** VoicePen shall show one approximate database disk usage value without splitting text payload and database sizes.

#### Scenario: Sessions UI is shown

- **WHEN** the Sessions UI is shown
- **THEN** VoicePen shall not expose a file-reveal action for the SQLite history database; users inspect sessions through the in-app list and detail pane.

#### Scenario: Sessions UI is shown 2

- **WHEN** the Sessions UI is shown
- **THEN** VoicePen shall use the shared transcript workspace described in `shared-transcript-workspace` capability.

#### Scenario: Home is selected

- **WHEN** Home is selected
- **THEN** VoicePen shall show a compact readiness strip as the only Home readiness status surface.

#### Scenario: Home is ready

- **WHEN** Home is ready
- **THEN** the readiness strip shall include the current push-to-talk shortcut hint and the Meeting recording Command-R hint.

#### Scenario: Home is not ready, busy, or in a problem state

- **WHEN** Home is not ready, busy, or in a problem state
- **THEN** the readiness strip shall show the current app status without also showing `Ready`.

#### Scenario: Home shows an actionable readiness problem

- **WHEN** Home shows an actionable readiness problem
- **THEN** permission problems shall route from the readiness strip to Settings and a missing local transcription model shall route to Models; transient busy states shall not show a readiness-strip action.

#### Scenario: Home is shown

- **WHEN** Home is shown
- **THEN** the dashboard layout shall be active and include one unified Activity block in the middle row.

#### Scenario: Home renders usage stats

- **WHEN** Home renders usage stats
- **THEN** it shall use the cached usage summary from the history store rather than recomputing stats from all history entries during view rendering.

#### Scenario: Home shows usage stats

- **WHEN** Home shows usage stats
- **THEN** it shall emphasize typing time avoided for the current Monday-Sunday week by converting recognized word count with the professional typing baseline.

#### Scenario: Home computes typing time avoided

- **WHEN** Home computes typing time avoided
- **THEN** it shall use recognized word count only and shall not subtract spoken audio duration.

#### Scenario: Home shows weekly usage stats

- **WHEN** Home shows weekly usage stats
- **THEN** it shall show weekly recognized word count, countable session count, spoken audio duration, current active streak, active days this week, best typing-time-avoided day this week, and best streak.

#### Scenario: Home has no countable activity for the current week

- **WHEN** Home has no countable activity for the current week
- **THEN** the weekly value area and daily activity chart shall present a calm empty weekly state rather than an empty chart or an oversized zero-value headline.

#### Scenario: Home shows weekly activity

- **WHEN** Home shows weekly activity
- **THEN** it shall include countable daily activity and hourly activity buckets for each of 7 local weekdays and 24 local hours.

#### Scenario: User hovers a Home unified Activity cell

- **WHEN** the user hovers a Home unified Activity cell
- **THEN** VoicePen shall show that cell's weekday, hour, and words without changing dashboard state.

#### Scenario: Home shows unified Activity

- **WHEN** Home shows unified Activity
- **THEN** it shall include one row for each Monday-Sunday day, including days with no countable activity.

#### Scenario: Home shows unified Activity 2

- **WHEN** Home shows unified Activity
- **THEN** the week mode shall default to the current Monday-Sunday local calendar week and show only words as the metric.

#### Scenario: Home shows unified Activity 3

- **WHEN** Home shows unified Activity
- **THEN** the 12-month mode shall cover the current calendar month plus prior 11 calendar months and expose daily buckets through today for the yearly contribution grid.

#### Scenario: Activity counts used in unified Activity

- **WHEN** this capability applies
- **THEN** Activity counts used in unified Activity shall require status-countable + positive usage word count and must ignore failed, zero-duration, and zero-word entries.

#### Scenario: Activity data for the visible 7-day and 12-month modes

- **WHEN** this capability applies
- **THEN** Activity data for the visible 7-day and 12-month modes shall be computed from already-aggregated daily/monthly/hourly structures without rescanning all entries in SwiftUI views.

#### Scenario: Shows usage milestones

- **WHEN** VoicePen shows usage milestones
- **THEN** the Home progress block shall identify the progress as lifetime or all-time so it does not read as part of the current-week totals.

#### Scenario: Shows usage milestones 2

- **WHEN** VoicePen shows usage milestones
- **THEN** it shall continue to use the existing progressive lifetime milestone ladder for the Home progress block.

#### Scenario: Shows usage stats

- **WHEN** VoicePen shows usage stats
- **THEN** it shall also compute lightweight progress signals: active streak, words dictated today, best dictation day, best streak, the latest reached milestone, and the next milestone.

#### Scenario: Computes usage milestones

- **WHEN** VoicePen computes usage milestones
- **THEN** it shall use a progressive ladder that mixes early wins, lifetime word volume, dictation count, active streak, best-day volume, and typing time avoided so a single high-volume day cannot unlock the full ladder.

#### Scenario: Computes active streak and best streak

- **WHEN** VoicePen computes active streak and best streak
- **THEN** it shall count consecutive local calendar days with at least one countable history entry, allowing the current streak to remain active before today's first dictation when yesterday had activity.

#### Scenario: Computes words dictated today and best dictation day

- **WHEN** VoicePen computes words dictated today and best dictation day
- **THEN** it shall use countable history entries and each entry's recognized word count.

#### Scenario: User clicks a visible history entry

- **WHEN** the user clicks a visible history entry
- **THEN** VoicePen shall select that entry, show it as active in the list, and update the detail pane to that entry.

#### Scenario: User copies text from a visible history detail copy action

- **WHEN** the user copies text from a visible history detail copy action
- **THEN** VoicePen shall temporarily replace that copy icon with a checkmark so the completed copy action is visible.

#### Scenario: Copy actions that show temporary copied feedback

- **WHEN** this capability applies
- **THEN** Copy actions that show temporary copied feedback shall keep stable dimensions while switching between normal and copied states.

#### Scenario: Sessions is shown

- **WHEN** Sessions is shown
- **THEN** VoicePen shall not expose a bulk Clear action; saved voice sessions shall be removed through per-session delete actions.

#### Scenario: Sessions row has actions such as copy or delete

- **WHEN** a Sessions row has actions such as copy or delete
- **THEN** VoicePen shall expose them through a row context menu and accessibility actions.

#### Scenario: History list shows a successful entry

- **WHEN** the history list shows a successful entry
- **THEN** VoicePen shall use a green checkmark without repeating a success label; non-success entries shall show a status or error reason.

#### Scenario: User opens a Sessions entry detail

- **WHEN** the user opens a Sessions entry detail
- **THEN** VoicePen shall show final text in the center workspace.

#### Scenario: Sessions entry has no final text

- **WHEN** a Sessions entry has no final text
- **THEN** VoicePen shall show a secondary error or status fallback and disable copy and repeat-insert actions for that entry.

#### Scenario: Sessions search runs

- **WHEN** Sessions search runs
- **THEN** VoicePen shall search visible final text, status, error, date/time, duration, local transcription model, and visible VoicePen app version metadata.

#### Scenario: Sessions search runs 2

- **WHEN** Sessions search runs
- **THEN** VoicePen shall not match raw transcript text.

#### Scenario: Sessions renders the shared transcript workspace

- **WHEN** Sessions renders the shared transcript workspace
- **THEN** VoicePen shall pass precomputed text metrics, text revision with content identity, visible entry IDs, and day groups so hover, selection, and body refreshes do not rescan every visible history entry or the selected full transcript while still updating the editor when two entries have the same local revision.

#### Scenario: User opens a history entry detail

- **WHEN** the user opens a history entry detail
- **THEN** VoicePen shall show the repeat insertion action as an icon-only retry control.

#### Scenario: User opens a Sessions entry detail and that entry has an existing archived saved-recording

- **WHEN** the user opens a Sessions entry detail and that entry has an existing archived saved-recording audio file
- **THEN** VoicePen shall show a Reveal in Finder action in the right sidebar after the metadata content.

#### Scenario: Sessions entry has no archived saved-recording audio file, or the archived file no longer

- **WHEN** a Sessions entry has no archived saved-recording audio file, or the archived file no longer exists
- **THEN** VoicePen shall hide the Reveal in Finder action.

#### Scenario: User copies or repeats insertion from Sessions

- **WHEN** the user copies or repeats insertion from Sessions
- **THEN** VoicePen shall use final text only.

#### Scenario: Sessions UI has visible entries from multiple local calendar days

- **WHEN** the Sessions UI has visible entries from multiple local calendar days
- **THEN** VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.

#### Scenario: Open VoicePen at login setting is displayed

- **WHEN** the Open VoicePen at login setting is displayed
- **THEN** VoicePen shall reflect the current macOS login item status instead of only the last saved preference.

#### Scenario: No feature-flag-only sections are enabled

- **WHEN** no feature-flag-only sections are enabled
- **THEN** the main window activity bar shall show Home, Meetings, and Sessions as primary navigation, followed by Settings icons ordered Dictionary, Model, Settings, and About.

#### Scenario: Tests touch persistence

- **WHEN** tests touch persistence
- **THEN** they shall use temporary data paths rather than real user data directories.

