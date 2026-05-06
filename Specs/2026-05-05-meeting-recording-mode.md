---
id: SPEC-011
status: active
updated: 2026-05-07
tests:
  - VoicePenTests/Meetings/MeetingRecordingStateTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/Meetings/MeetingHistoryStoreTests.swift
  - VoicePenTests/History/HistoryDayGroupsTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
---

# Meeting Recording Mode

## Problem

VoicePen needs a meeting workflow that records longer conversations with both
the user's microphone input and system output audio from other apps. This must
stay distinct from push-to-talk dictation because meeting output is sensitive,
should not auto-paste into the active app, and must not flow through hosted LLM
providers.

## Behavior

VoicePen provides Meeting Mode as an explicit menu and in-app action. Before the
first meeting recording, VoicePen shows a consent reminder. Recording starts
only when Microphone permission is available and system output audio capture can
start. Meeting Mode v1 uses audio-only capture backends and shall not create a
screen capture stream.

During recording, VoicePen shows a persistent status panel with elapsed active
time, the meeting recording limit in minutes, microphone status, system audio
status, and a non-intrusive red recording pulse. The Meetings header changes its
start action to stop while recording, shows a pulsing recording icon in the stop
action, and shows a compact cancel action. Cancel deletes temporary audio and
creates no history entry. Stop runs local transcription and saves a meeting
history entry. Successful processing deletes temporary audio immediately.
Failed or partial processing deletes temporary audio but keeps a local recovery
audio copy for retry for 7 days. While stopped meeting audio is processing, the
persistent status panel shows that transcript processing is underway instead of
showing microphone and system audio as unavailable.

Meeting history is separate from dictation history. It stores transcript text,
duration, creation date, source flags, product status, errors, timings, and the
local model and VoicePen app version used for transcription with a separate transcript storage budget.
`Partial Transcript` means VoicePen saved non-empty transcript text but did not
process the full meeting. `Failed` means no usable transcript text was saved.
Meeting entries are excluded from dictation usage totals and milestones. Meeting
transcripts can be copied, but Meeting Mode never auto-pastes output or exposes
an Insert Transcript action.

Meeting Mode v1 captures both microphone input and system output audio where
available, chunks transcript processing by start time, caps meeting processing
at 120 minutes, applies best-effort system voice leveling before transcription,
and uses 1 minute chunk windows. Meeting system audio can be configured before
recording to capture all system audio, capture selected apps only, or capture
all system audio except selected apps. Selected apps are persisted by bundle
identifier with a display name for settings UI. If VoicePen cannot apply the
selected filter at recording start because the selected list is empty or no
selected-only app is currently running, it switches the setting back to all
system audio, surfaces a warning, and starts recording with all system audio.
v1 does not provide summaries,
action items, ticket drafts, engineering notes, pause, or resume.

## Acceptance Criteria

- When Meeting Mode starts before consent acknowledgment, VoicePen shall show the consent reminder first.
- When microphone permission is missing, VoicePen shall not start recording and shall identify microphone as missing.
- When system output audio capture cannot start because permission is missing, VoicePen shall identify system audio permission as missing.
- When microphone permission is available and system output audio capture starts, VoicePen shall start one meeting session that captures microphone and system audio.
- When meeting audio capture does not start within 10 seconds, VoicePen shall leave the recording state and surface a capture timeout error.
- When meeting audio capture start is canceled or times out after one source has started, VoicePen shall stop any partially started audio sources before leaving the recording state.
- Meeting Mode v1 shall not request or use screen capture for meeting recording.
- While recording is active, the Meetings header shall show a compact cancel action before the stop action instead of duplicating recording actions in the persistent status panel, so the primary start/stop action remains trailing-aligned and does not jump when recording starts.
- While recording is active, VoicePen shall show a pulsing recording indicator in the Meetings header stop action and in the persistent status panel so users can notice that capture is still running.
- While recording is active, the persistent status panel shall show the meeting recording limit in minutes.
- When recording is canceled, VoicePen shall delete temporary audio and not create meeting history.
- When recording is stopped, VoicePen shall transcribe locally and save a meeting entry.
- When recording is stopped and decoding returns model metadata, VoicePen shall save the app version used for that decoding alongside the local model metadata.
- When recording is stopped, the saved meeting duration shall use the active wall-clock recording duration, not the sum of microphone and system audio source chunk durations.
- When recording exceeds the 120 minute processing limit and supported audio produces transcript text, VoicePen shall process only the supported window, save the meeting as a partial transcript, and show a user-facing error reason that includes the limit in minutes.
- When processing produces no usable transcript text, VoicePen shall save the meeting as failed even if capture or processing was incomplete.
- Meeting history rows shall not let technical incomplete-capture or incomplete-processing flags override the product status shown to the user.
- When a saved meeting duration is shorter than one minute, meeting history items shall display the duration in seconds instead of fractional minutes.
- While stopped meeting audio is processing, VoicePen shall show that transcript processing is underway in the persistent status panel without showing microphone or system audio as unavailable.
- While stopped meeting audio is processing and more than one chunk is known, VoicePen shall show determinate chunk progress as an approximate percentage in the persistent status panel.
- While stopped meeting audio is processing as a single chunk, VoicePen shall show generic transcript processing status without a determinate percentage.
- When transcription completes successfully, VoicePen shall delete temporary audio and shall not retain recovery audio.
- When transcription fails or saves only a partial transcript, VoicePen shall delete temporary audio but keep a local recovery audio copy for retry for 7 days.
- When retry processing succeeds, VoicePen shall update the same meeting history entry and delete its recovery audio.
- When retry processing fails, VoicePen shall keep the same meeting history entry retryable without extending the original recovery audio expiration.
- When recovery audio expires, VoicePen shall delete the audio, keep the meeting history entry, and make retry unavailable.
- When meeting processing does not complete within the processing timeout, VoicePen shall cancel processing, leave the meeting processing state, surface a timeout error, and keep recovery audio retryable instead of saving a completed meeting transcript.
- When a later meeting chunk does not complete within the chunk processing timeout after earlier chunks produced transcript text, VoicePen shall save a partial meeting entry with the transcript collected so far and keep recovery audio for retry.
- When one captured source chunk is silent but another source chunk contains speech, VoicePen shall skip the silent chunk and keep processing the meeting.
- When Meeting voice leveling is enabled, VoicePen shall best-effort render each non-silent chunk through system dynamics and peak limiting before transcription.
- When Meeting voice leveling fails, VoicePen shall continue transcribing the ordinary preprocessed chunk and keep a diagnostic note.
- When all captured chunks are silent, VoicePen shall save a failed meeting entry that identifies no detected speech.
- When local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Субтитры создавал ...", "Добавил субтитры ...", or "Продолжение следует...", VoicePen shall remove those lines from meeting transcripts before saving history.
- When Meeting system audio source is set to all system audio, VoicePen shall build a global system output tap.
- When Meeting system audio source is set to selected apps only, VoicePen shall build a non-exclusive app-filtered system output tap for the selected bundle identifiers.
- When Meeting system audio source is set to all except selected apps, VoicePen shall build an exclusive app-filtered system output tap excluding the selected bundle identifiers.
- When selected apps only has no selected apps at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- When selected apps only has no selected app running at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- When all except selected apps has no selected apps at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- Meeting system audio source mode and selected app list shall persist across launches; invalid stored modes fall back to all system audio and invalid app entries are ignored.
- When Meeting system audio source is set to all system audio, Config settings shall hide the selected-app controls.
- When Meeting system audio source is set to selected apps only or all except selected apps, Config settings shall show selected-app controls and allow choosing one or more macOS `.app` bundles at once.
- When the Config Meeting system audio source control changes, VoicePen shall persist the selected mode and hide or show selected-app controls without SwiftUI publishing warnings.
- When one source fails mid-recording, VoicePen shall stop capture and mark the session partial.
- When microphone and system audio overlap in the same meeting time window, VoicePen shall merge them into one timeline audio chunk before transcription, so dialogue order follows meeting time instead of source order.
- Meeting transcript timecodes shall be controlled by a persistent Config setting that is enabled by default in Config settings.
- When Meeting transcript timecodes are enabled, meeting transcripts shall include meeting-relative timecodes for each transcribed segment returned by local transcription; chunks without returned segments shall not receive synthetic timecodes.
- When Meeting transcript timecodes are enabled, VoicePen shall request fine-grained timestamp decoding from local models and shall trim leading or trailing inactive source-audio time from displayed segment intervals when source activity is available.
- Meeting diarization shall be controlled by a persistent Config setting in the Meeting features section.
- Meeting diarization settings help shall describe experimental speaker labels from a separate local diarization model.
- When Meeting diarization is enabled and the local diarization model is installed, VoicePen shall warm the diarization model automatically at app start, after enabling the setting, and after a successful diarization model download.
- Model settings shall keep the Meeting diarization model lifecycle limited to download, progress, status, and delete controls while warm-up remains automatic when diarization is enabled.
- When the user starts a Meeting diarization model download, VoicePen shall expose download progress state, retry transient artifact download failures, and log the download start, model artifact stages, retry attempts, completion, cancellation, and failure.
- When proxy settings exist in the local environment settings file, Meeting diarization model downloads shall use the same proxy configuration as transcription model downloads.
- When Meeting diarization runs, VoicePen shall log enough diagnostics to identify whether missing speaker labels came from model loading, backend pipeline execution, backend speaker-turn output, VoicePen turn postprocessing, or transcript speaker merge assignment.
- When Meeting processing runs, VoicePen shall log diarization and per-chunk transcription elapsed times so short-recording latency can be traced to the expensive stage.
- When Meeting diarization is enabled and the local diarization model is available, VoicePen shall run diarization as a separate offline pass from ASR.
- Meeting diarization shall use a VoicePen backend contract that accepts the full meeting timeline recording and returns global speaker turns on that same timeline; any physical chunking is backend-internal and shall not create per-chunk speaker identities in VoicePen.
- Meeting diarization shall use the speech-swift Pyannote diarization pipeline as the default backend, with Silero VAD disabled as a hard pre-filter so Silero false negatives cannot be the only gate for speaker evidence.
- When the user provides an expected speaker count, VoicePen shall carry that count in the diarization backend request and log when the active backend cannot force an exact speaker count.
- When Meeting diarization is enabled with Auto speaker count for a recording shorter than 15 seconds, VoicePen shall skip the diarization backend to avoid high fixed startup cost for a low-evidence speaker-label pass; choosing an exact speaker count shall still force diarization.
- Meeting diarization postprocessing shall remove tiny turns, merge nearby turns from the same speaker, smooth short speaker flips, and avoid creating new speakers from uncertain regions.
- Meeting transcript speaker labels shall assign speakers from diarization turns by word timestamp overlap when word timestamps are available, and by ASR segment overlap or midpoint when word timestamps are unavailable; VoicePen shall not invent labels for transcript spans that have no diarization overlap.
- Meeting transcript speaker labels shall avoid splitting ASR segments on every tiny speaker boundary; splits shall be limited to meaningful text/time groups.
- The bundled model manifest shall expose transcription models independently from Meeting diarization models.
- When Meeting transcription ends with repeated short identical transcript segments that are likely local model silence hallucinations, VoicePen shall remove that repeated tail before saving the meeting transcript.
- When Meeting diarization is enabled, VoicePen shall request segment timestamps from the local transcription backend even when transcript timecodes are not displayed.
- When Meeting diarization is unavailable or fails, VoicePen shall keep the transcript rather than failing the meeting solely because speaker labels could not be produced.
- When Meeting recording starts while the selected transcription model warmup is in progress, VoicePen shall keep that warmup running instead of canceling it, so first meeting processing can reuse the warmed model when possible.
- When transcript exists, VoicePen shall let the user copy it without calling any LLM provider.
- Meeting detail shall expose one copy transcript action near the transcript text area, and retry actions shall use compact icon-only controls with accessible labels.
- Meeting detail copy actions shall show temporary copied feedback after copying a transcript.
- Copy actions that show temporary copied feedback shall keep stable dimensions while switching between normal and copied states.
- Meeting detail shall let users resize the saved transcript text area vertically while keeping the transcript selectable and read-only.
- When the Meetings screen opens, VoicePen shall load meeting history list metadata and transcript previews without reading or decompressing every saved full transcript.
- When a meeting history entry becomes focused, VoicePen shall load and decompress the full transcript for that focused entry only.
- When a new meeting history row appears in the Meetings list, its text shall be visible immediately without requiring the user to scroll the list first.
- When the Meetings list has entries from multiple local calendar days, VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.
- Meeting detail shall not expose an Insert Transcript action and shall never auto-paste meeting output.
- When meeting transcript exceeds one chunk, VoicePen shall preserve chunk order.
- When meetings are deleted, VoicePen shall delete meeting rows and leave dictation history unchanged.
- Meeting detail shall show user-facing processing information: the local model that decoded the meeting, the app version used for decoding when it is known, and the total processing time, without exposing backend/version metadata as a primary detail.
- Meeting detail shall show Meeting transcript timecode status only when the feature is unavailable or not produced for that saved transcript; when timecodes are present in the transcript, the detail shall not duplicate that obvious status as metadata.
- Meeting history shall not contribute to the general dictation minutes, word counts, streaks, or milestones.
- The main window settings navigation shall place Meeting Mode immediately after General settings, before Modes, AI, Dictionary, and the remaining settings sections.
- While Meeting Mode is recording or processing, VoicePen shall show meeting-specific status icons in the menu bar and main window navigation.
- While Meeting Mode is actively recording, the menu bar icon shall show a clear recording indicator with a non-intrusive red pulse so the user can notice that capture is still running.
- OpenRouter shall not be called anywhere in Meeting Mode v1.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| First meeting | User chooses Start Meeting Recording | Consent reminder appears before recording starts |
| Missing microphone | Microphone permission is denied | Recording does not start and microphone is identified as missing |
| Missing system audio | System output audio capture is denied | Recording does not start and system audio is identified as missing |
| Hung capture start | Audio capture does not finish starting | VoicePen exits recording state and shows a capture timeout error |
| Canceled capture start | One audio source starts and another source does not finish starting before cancellation | Started sources are stopped before VoicePen exits recording state |
| Cancel meeting | User cancels an active recording | Temporary audio is deleted and no meeting row is saved |
| Stop meeting | User stops an active recording from the Meetings header | Local transcription runs, processing status is shown, meeting history is saved with active wall-clock duration, temporary audio is deleted after success |
| Meeting decode metadata | Meeting transcription returns local model metadata | Meeting history stores the local model metadata and app version used during decoding |
| Unknown meeting app version | Older meeting entry has no saved decoding app version | Meeting detail omits the App version metadata row |
| Recording limit exceeded with text | User records longer than the supported meeting limit and supported audio contains speech | VoicePen saves a partial transcript, caps processed duration at the supported limit, and shows that the limit was reached |
| Recording limit exceeded without text | User records longer than the supported meeting limit and no supported audio yields text | VoicePen saves a failed meeting with no transcript and shows that the limit was reached |
| Hung meeting processing | Local processing does not return | VoicePen exits processing and surfaces a timeout error |
| Meeting processing progress | A meeting has multiple chunks to process | The recording panel shows determinate processing progress as an approximate percentage |
| Hung later chunk | First chunk transcribes and second chunk hangs | VoicePen saves the first chunk as a partial meeting and keeps recovery audio retryable for 7 days |
| Selected app filter unavailable | Meeting system audio is set to selected apps only and none of those apps are running | VoicePen switches the setting to all system audio, shows a warning, and starts recording |
| Empty exclusion filter | Meeting system audio is set to all except selected apps with no selected apps | VoicePen switches the setting to all system audio, shows a warning, and starts recording |
| All system audio settings | Meeting system audio source is set to all system audio | Config settings hides selected-app controls |
| Add selected apps | Meeting system audio source is selected apps only or all except selected apps, then the user uses the add-apps control and chooses several `.app` bundles | The apps are selectable and appear in the selected-app list with bundle identifiers |
| Retry failed meeting | User uses retry on a failed meeting before recovery audio expires | VoicePen reprocesses local audio and updates the same meeting history entry |
| Expired recovery audio | Seven days pass after a failed meeting | VoicePen deletes retained audio and keeps the failed meeting row without retry |
| New meeting row | A meeting finishes and a new row appears in Meetings history | The row preview text is visible immediately |
| Open Meetings | Saved meetings include large or compressed transcripts | The list opens from metadata and previews without decompressing every full transcript |
| Focus meeting | User selects a saved meeting | The full transcript for that meeting is loaded for the detail pane |
| Meeting day groups | Saved meetings include entries from multiple local calendar days | Meetings appear under sticky day sections while preserving newest-first order within each day |
| Resize transcript | User drags the saved meeting transcript text area resize handle | The transcript area changes height without editing the saved transcript |
| Copy transcript | User clicks the copy action in the saved meeting transcript section | Transcript is copied without a duplicate header copy action or Insert Transcript action |
| Stable copy feedback | Copy transcript action changes to copied feedback | The button keeps its existing dimensions |
| Present meeting transcript features | Transcript already shows timecodes | Meeting detail does not add duplicate `Present` metadata rows |
| Missing meeting transcript features | Model supports timestamps but transcript has no timecodes | Meeting detail shows that the feature was not present |

## Test Mapping

- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers start, stop, cancel, composite microphone/system-audio source recording, active wall-clock duration, cleanup after canceled start, and partial source failure with fakes.
- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers Meeting system audio tap planning and preflight fallback.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers local transcription flow, chunk ordering, overlapping source merging before transcription, optional meeting timecodes, separate diarization speaker labels, app version metadata, active wall-clock duration, limit handling, silent source chunks, known subtitle/outro artifact cleanup, chunk timeout partial salvage, recovery audio retention and retry, temporary audio cleanup, and no automatic insertion.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers removing repeated short trailing Meeting transcription hallucinations.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers diarization chunk planning, full-recording diarization request wiring, very-short Auto diarization skip with exact-count override, speaker turn postprocessing, word overlap speaker merge, segment midpoint fallback, uncovered-gap behavior, tiny-overlap rejection, diarization failure fallback, and separate diarization execution before ASR chunk formatting.
- Automated: `VoicePenTests/Meetings/MeetingDiarizationModelDownloadTests.swift` covers Meeting diarization Hugging Face artifact selection, URL construction, and proxy-aware download session configuration.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers prompting for an expected Meeting diarization speaker count when diarization is enabled.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers Meeting diarization model lifecycle state, automatic warmup when diarization is enabled, automatic warmup after a successful diarization model download, and keeping transcription model warmup running when Meeting recording starts.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers Meeting voice leveling routing and fallback.
- Automated: `VoicePenTests/Meetings/MeetingHistoryStoreTests.swift` covers append, preview-only list load, focused full transcript load, delete, compression, separate storage budget, partial entries, error entries, model/app version metadata, recovery manifests, and expired recovery cleanup.
- Automated: `VoicePenTests/History/HistoryDayGroupsTests.swift` covers Meeting and History list grouping by local calendar day while preserving entry order.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers `meeting_history` creation and migration from old databases.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers consent gating, permission gating, meeting state, Meeting system audio source settings updates, selected-app fallback, meeting processing state, meeting timeout recovery, and no conflict with dictation history.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu and sidebar meeting commands, header recording controls, meeting processing UI, Config placement for Meeting features, Meeting system audio source settings controls, stable shared copy-button feedback, meeting status icons in navigation surfaces, recording limit display, and recording pulses in the menu bar, Meetings header, and persistent status panel.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers Meeting system audio source defaults, persistence, invalid mode fallback, and invalid selected-app filtering.
- Manual: switch Config Meeting system audio source between all system audio and filtered modes; verify selected-app controls hide and show without SwiftUI publishing warnings, then use the add-apps control, select multiple macOS `.app` bundles, and verify they appear with bundle identifiers.
- Manual: record real meeting audio with microphone plus Zoom, Meet, or browser audio and verify both sides appear in the transcript.
- Manual: finish a new meeting while the Meetings screen is open and verify the new history row text appears without scrolling.
- Manual: open Meetings with entries from several days and verify meetings are grouped by day and the current day header sticks while scrolling.
- Manual: open a saved meeting, drag the full transcript text area handle, and verify the transcript area resizes while text remains selectable and read-only.
- Manual: deny System Audio access and verify the recovery path.
- Manual: stop, cancel, fail, retry, and expire a recording and verify temporary audio and recovery audio follow the documented cleanup behavior.

## Notes

Meeting Mode v1 uses separate audio-only sources for microphone input and system
output audio. VoicePen does not use ScreenCaptureKit or persist screen/video
frames for Meeting Mode. OpenRouter and hosted LLM providers are outside this v1
flow.

## Open Questions

- None.
