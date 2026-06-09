---
id: SPEC-011
status: active
updated: 2026-06-09
tests:
  - VoicePenTests/Meetings/MeetingRecordingStoreTests.swift
  - VoicePenTests/Meetings/MeetingRecordingStateTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift
  - VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift
  - VoicePenTests/Meetings/MeetingHistoryEntryTests.swift
  - VoicePenTests/Meetings/MeetingHistoryStoreTests.swift
  - VoicePenTests/Meetings/MeetingHistoryFilterTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptEditorMetricsTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/AppPathsTests.swift
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
duration, creation date, source flags, product status, errors, timings, detected
speaker count when diarization provides one, and the local model and VoicePen app
version used for transcription with a separate transcript storage budget.
`Partial Transcript` means VoicePen saved non-empty transcript text but did not
process the full meeting. `Failed` means no usable transcript text was saved.
Meeting entries are excluded from dictation usage totals and milestones. Meeting
transcripts can be copied, but Meeting Mode never auto-pastes output or exposes
an Insert Transcript action.

On desktop, the Meetings screen adopts the shared transcript workspace from
SPEC-015. Meetings provides meeting-specific rows, metadata, actions, search
fields, and focused-entry transcript loading to that shared layout. Search
filters loaded meeting summaries and previews locally by the transcript preview
or full text already available in an entry, recording date/time, status, error,
duration, audio source labels, ASR model, and app version. Opening the Meetings
screen must not read or decompress every saved full transcript.

Meeting Mode v1 captures both microphone input and system output audio where
available, chunks transcript processing by start time, automatically stops live
recording at 120 minutes, applies best-effort system voice leveling before
transcription, and uses 1 minute chunk windows. Temporary, chunked, and recovery
meeting audio is stored as 16 kHz mono 16-bit PCM so long recordings use less
disk space without lowering ASR sample rate. The 120 minute limit applies to
live capture only; local processing and retry shall process available recovery
audio beyond that duration. Meeting system audio can be configured before
recording to capture all system audio, capture selected apps only, or capture
all system audio except selected apps. Selected apps are persisted by bundle
identifier with a display name for settings UI. If VoicePen cannot apply the
selected filter at recording start because the selected list is empty or no
selected-only app is currently running, it switches the setting back to all
system audio, surfaces a warning, and starts recording with all system audio.
v1 does not provide summaries,
action items, ticket drafts, engineering notes, pause, resume, playback,
waveforms, an audio player, export, speaker profiles, voice-profile linking or
creation, or transcript editing.

## Acceptance Criteria

- When Meeting Mode starts before consent acknowledgment, VoicePen shall show the consent reminder first.
- When microphone permission is missing, VoicePen shall not start recording and shall identify microphone as missing.
- When system output audio capture cannot start because permission is missing, VoicePen shall identify system audio permission as missing.
- When microphone permission is available and system output audio capture starts, VoicePen shall start one meeting session that captures microphone and system audio.
- When meeting audio is written to temporary, chunked, or recovery files, VoicePen shall store it as 16 kHz mono 16-bit PCM.
- When meeting audio capture does not start within 10 seconds, VoicePen shall leave the recording state and surface a capture timeout error.
- When meeting audio capture start is canceled or times out after one source has started, VoicePen shall stop any partially started audio sources before leaving the recording state.
- Meeting Mode v1 shall not request or use screen capture for meeting recording.
- While recording is active, the Meetings header shall keep a compact cancel action and switch the primary start recording button in place to Stop instead of showing a separate Stop button.
- While recording is active, VoicePen shall show a pulsing recording indicator in the Meetings header stop action and in the persistent status panel so users can notice that capture is still running.
- While recording is active, the persistent status panel shall show the meeting recording limit in minutes.
- When recording is canceled, VoicePen shall delete temporary audio and not create meeting history.
- When saved Meeting recordings are enabled, VoicePen shall schedule best-effort asynchronous copies of the post-chunking, pre-preprocessing Meeting audio chunks to the user's saved recordings folder before voice leveling or transcription.
- Saved Meeting recordings shall use the chunks that proceed to transcription, including readable original chunks, sliced chunks, or merged timeline chunks.
- When saved Meeting audio copying or pruning is scheduled, VoicePen shall continue voice leveling, transcription, retry, recovery audio, and history handling without waiting for that saved-audio work to finish.
- When Meeting saved-audio copying fails, VoicePen shall log the failure asynchronously and continue Meeting processing without changing transcription, retry, recovery audio, or history behavior.
- Retrying a failed or partial Meeting recording shall not create duplicate saved Meeting audio for chunks that were already saved during the original processing attempt.
- Canceling an active Meeting recording shall not save Meeting audio.
- When recording is stopped and audio is not discarded as all-silent preprocessing, VoicePen shall transcribe locally and save a meeting entry.
- When recording is stopped and decoding returns model metadata, VoicePen shall save the app version used for that decoding alongside the local model metadata.
- When recording is stopped, the saved meeting duration shall use the active wall-clock recording duration, not the sum of microphone and system audio source chunk durations.
- When active recording reaches the 120 minute limit, VoicePen shall automatically stop recording and start local transcription.
- When active recording is still running 5 minutes before the 120 minute limit, VoicePen shall show one non-blocking user notification that recording is still running and shall open the VoicePen window to the Meetings screen when the user clicks it.
- When active recording stops or is canceled before the 5-minute reminder point, VoicePen shall not show the limit reminder for that recording.
- When a configured live recording limit is shorter than the reminder lead time, VoicePen shall skip the reminder and keep automatic stop behavior unchanged.
- When recording reaches the 120 minute limit and transcription produces usable transcript text, VoicePen shall save the meeting without marking it failed or partial solely because the limit was reached.
- When recorded audio metadata extends beyond the readable audio frames after automatic stop, VoicePen shall process the readable audio instead of failing the meeting because of an empty trailing chunk.
- When retrying a failed or partial meeting with available recovery audio longer than 120 minutes, VoicePen shall process the available recovery audio beyond 120 minutes instead of rejecting or truncating it because of the recording limit.
- When local transcription runs but produces no usable transcript text, VoicePen shall save the meeting as failed even if capture or processing was incomplete.
- Meeting history rows shall not let technical incomplete-capture or incomplete-processing flags override the product status shown to the user.
- When a saved meeting duration is shorter than one minute, meeting history items shall display the duration in seconds instead of fractional minutes.
- While stopped meeting audio is processing, VoicePen shall show that transcript processing is underway in the persistent status panel without showing microphone or system audio as unavailable.
- While stopped meeting audio is processing and more than one chunk is known, VoicePen shall show determinate chunk progress as an approximate percentage in the persistent status panel.
- While stopped meeting audio is processing as a single chunk, VoicePen shall show generic transcript processing status without a determinate percentage.
- When transcription completes successfully, VoicePen shall delete temporary audio and shall not retain recovery audio.
- When transcription fails or saves only a partial transcript, VoicePen shall delete temporary audio but keep a local recovery audio copy for retry for 7 days.
- When VoicePen cleans stale temporary audio on startup, it shall remove old VoicePen-owned meeting `.caf` temporary audio as well as old VoicePen-owned `.wav` temporary audio.
- When retry processing succeeds, VoicePen shall update the same meeting history entry and delete its recovery audio.
- When retry processing fails, VoicePen shall keep the same meeting history entry retryable without extending the original recovery audio expiration.
- When recovery audio expires, VoicePen shall delete the audio, keep the meeting history entry, and make retry unavailable.
- When meeting processing does not complete within the processing timeout, VoicePen shall cancel processing, leave the meeting processing state, surface a timeout error, and keep recovery audio retryable instead of saving a completed meeting transcript.
- When a later meeting chunk does not complete within the chunk processing timeout after earlier chunks produced transcript text, VoicePen shall save a partial meeting entry with the transcript collected so far and keep recovery audio for retry.
- When one captured source chunk is silent but another source chunk contains speech, VoicePen shall skip the silent chunk and keep processing the meeting.
- When Meeting voice leveling is enabled, VoicePen shall best-effort render each non-silent chunk through system dynamics and peak limiting before transcription.
- When Meeting voice leveling fails, VoicePen shall continue transcribing the ordinary preprocessed chunk and keep a diagnostic note.
- When all captured chunks are rejected as audio silence before local transcription, VoicePen shall delete temporary audio, show an informational alert, and not save a meeting entry or recovery audio.
- When local transcription returns empty text or text that is fully removed as known transcript artifacts, VoicePen shall keep the failed meeting entry path.
- When local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Субтитры создавал ...", "Добавил субтитры ...", or "Продолжение следует...", VoicePen shall remove those lines from meeting transcripts before saving history.
- When Meeting system audio source is set to all system audio, VoicePen shall build a global system output tap.
- When Meeting system audio source is set to selected apps only, VoicePen shall build a non-exclusive app-filtered system output tap for the selected bundle identifiers.
- When Meeting system audio source is set to all except selected apps, VoicePen shall build an exclusive app-filtered system output tap excluding the selected bundle identifiers.
- When the current macOS release does not support bundle-ID system audio taps, VoicePen shall resolve selected bundle identifiers to CoreAudio process object IDs and build the app-filtered tap instead of failing capture solely because bundle-ID filtering is unavailable.
- When selected apps only has no selected apps at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- When selected apps only has no selected app running at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- When all except selected apps has no selected apps at recording start, VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.
- Meeting system audio source mode and selected app list shall persist across launches; invalid stored modes fall back to all system audio and invalid app entries are ignored.
- When Meeting system audio source is set to all system audio, the Settings screen shall hide the selected-app controls.
- When Meeting system audio source is set to selected apps only or all except selected apps, the Settings screen shall show selected-app controls and allow choosing one or more macOS `.app` bundles at once.
- When the Settings screen Meeting system audio source control changes, VoicePen shall persist the selected mode and hide or show selected-app controls without SwiftUI publishing warnings.
- When one source fails mid-recording, VoicePen shall stop capture and mark the session partial.
- When microphone and system audio overlap in the same meeting time window, VoicePen shall merge them into one timeline audio chunk before transcription, so dialogue order follows meeting time instead of source order.
- Meeting transcript timecodes shall be controlled by a persistent Settings screen setting that is enabled by default.
- When Meeting transcript timecodes are enabled, meeting transcripts shall include meeting-relative timecodes for each transcribed segment returned by local transcription; chunks without returned segments shall not receive synthetic timecodes.
- When Meeting transcript timecodes are enabled, VoicePen shall request fine-grained timestamp decoding from local models and shall trim leading or trailing inactive source-audio time from displayed segment intervals when source activity is available.
- Meeting diarization shall be controlled by a persistent Settings screen setting in the Meeting features section.
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
- When Meeting diarization produces structured speakers for a saved meeting, VoicePen shall save the detected speaker count on that meeting history entry.
- When Meeting recording starts while the selected transcription model warmup is in progress, VoicePen shall keep that warmup running instead of canceling it, so first meeting processing can reuse the warmed model when possible.
- When transcript exists, VoicePen shall let the user copy it without calling any LLM provider.
- When Meetings opens on desktop, VoicePen shall use the shared transcript workspace described in SPEC-015.
- Meeting search shall filter loaded meeting summaries and previews locally by transcript preview or full transcript text already available in an entry, recording date/time, status, error, duration, audio source labels, ASR model, and VoicePen app version.
- Meeting search shall not read or decompress every saved full transcript when the Meetings screen opens.
- When Meeting search has no matches, VoicePen shall show an empty state that communicates no meetings were found and suggests trying another query.
- When the main VoicePen window is focused, Command-R shall start Meeting recording when no capture is active and stop Meeting recording when capture is active, regardless of the selected section or active keyboard layout.
- Meeting detail shall show the focused transcript in the shared center workspace and copy the full saved transcript through the shared center copy action.
- When a failed meeting has no transcript, the center workspace shall show the saved error text.
- Meeting detail shall show Status, Recording, Duration, Audio sources, Processing, Speakers detected, and Actions in the right sidebar.
- Meeting detail shall keep the full-transcript Copy action in the editor header and avoid duplicating it in the right sidebar.
- Meeting detail shall keep Delete recording in the right sidebar as the bottom destructive action, after the scrollable metadata content.
- Meeting detail Speakers detected shall show the saved structured speaker count when present, and `—` when a count was not produced.
- Meeting detail shall not infer voice profiles or show speaker identity/profile actions.
- Meeting detail actions in this stage shall include Copy transcript in the editor and Delete recording in the right sidebar; existing retry may remain available for recoverable audio.
- Meeting detail shall not expose playback, waveform, audio player, export, speaker profile, voice-profile linking or creation, transcript editing, Insert Transcript, or auto-paste actions.
- Meeting detail Copy transcript action shall show temporary copied feedback after copying a transcript.
- When a Meeting detail with saved transcript is open and Command-C is pressed while no focused text input or selected transcript range handles the copy command, VoicePen shall copy the full saved transcript regardless of the active keyboard layout.
- When transcript text is selected in the editor, Command-C shall preserve the standard selected-text copy behavior instead of copying the full transcript.
- Meeting detail Command-C full-transcript copy shall show the same temporary copied feedback as the editor Copy action.
- Copy transcript feedback shall keep stable dimensions while switching between normal and copied states.
- When the Meetings screen opens, VoicePen shall load meeting history list metadata and transcript previews without reading or decompressing every saved full transcript.
- When a meeting history entry becomes focused, VoicePen shall load and decompress the full transcript for that focused entry only.
- When a new meeting history row appears in the Meetings list, its text shall be visible immediately without requiring the user to scroll the list first.
- Meeting list preview text shall omit leading transcript timecodes while preserving transcript text and speaker labels.
- When the Meetings list has entries from multiple local calendar days, VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.
- Meeting detail shall not expose an Insert Transcript action and shall never auto-paste meeting output.
- When meeting transcript exceeds one chunk, VoicePen shall preserve chunk order.
- When meetings are deleted, VoicePen shall delete meeting rows and leave dictation history unchanged.
- Meeting detail shall show user-facing processing information: the local model that decoded the meeting, the app version used for decoding when it is known, and the total processing time, without exposing backend/version metadata as a primary detail.
- Meeting detail shall show Meeting transcript timecode status only when the feature is unavailable or not produced for that saved transcript; when timecodes are present in the transcript, the detail shall not duplicate that obvious status as metadata.
- Meeting history shall not contribute to the general dictation minutes, word counts, streaks, or milestones.
- The main window activity bar shall place Meetings immediately after Home and before Sessions.
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
| Saved Meeting audio enabled | User stops a Meeting recording | The post-chunking audio files that proceed to transcription are scheduled for local copy with readable source/chunk filenames |
| Saved Meeting audio copy failure | Saved recordings folder cannot be written | Meeting processing still transcribes and saves or fails normally |
| Retry failed meeting with saved audio enabled | User retries before recovery audio expires | Retry updates the existing row without creating duplicate saved audio files |
| Meeting decode metadata | Meeting transcription returns local model metadata | Meeting history stores the local model metadata and app version used during decoding |
| Unknown meeting app version | Older meeting entry has no saved decoding app version | Meeting detail omits the App version metadata row |
| Recording limit reached with text | Active recording reaches the 120 minute limit and captured audio contains speech | VoicePen automatically stops recording, transcribes locally, and saves the meeting without a duration-limit failure |
| Recording limit reminder | Active recording is still running 5 minutes before the 120 minute limit | VoicePen shows one non-blocking notification that recording is still running; clicking it opens the VoicePen window to Meetings |
| Recording limit with short file tail | Active recording stops automatically and the audio file has fewer readable frames than the wall-clock metadata duration | VoicePen transcribes the readable audio and ignores the empty trailing split window |
| Retry long recovery audio | User retries an older failed meeting whose available recovery audio is longer than 120 minutes | VoicePen processes the available recovery audio beyond 120 minutes and updates the same entry when transcription succeeds |
| Silent meeting recording | User stops a meeting recording where every captured chunk is audio silence before transcription | VoicePen deletes temporary audio, shows an informational alert, and does not save a meeting row or recovery audio |
| Hung meeting processing | Local processing does not return | VoicePen exits processing and surfaces a timeout error |
| Meeting processing progress | A meeting has multiple chunks to process | The recording panel shows determinate processing progress as an approximate percentage |
| Hung later chunk | First chunk transcribes and second chunk hangs | VoicePen saves the first chunk as a partial meeting and keeps recovery audio retryable for 7 days |
| Selected app filter unavailable | Meeting system audio is set to selected apps only and none of those apps are running | VoicePen switches the setting to all system audio, shows a warning, and starts recording |
| Selected app filter on older macOS | Meeting system audio is set to selected apps only on a macOS release without bundle-ID tap filtering | VoicePen builds the filtered tap from CoreAudio process object IDs instead of failing recording start |
| Empty exclusion filter | Meeting system audio is set to all except selected apps with no selected apps | VoicePen switches the setting to all system audio, shows a warning, and starts recording |
| All system audio settings | Meeting system audio source is set to all system audio | Settings screen hides selected-app controls |
| Add selected apps | Meeting system audio source is selected apps only or all except selected apps, then the user uses the add-apps control and chooses several `.app` bundles | The apps are selectable and appear in the selected-app list with bundle identifiers |
| Retry failed meeting | User uses retry on a failed meeting before recovery audio expires | VoicePen reprocesses local audio and updates the same meeting history entry |
| Stale meeting temp audio | VoicePen starts after an interrupted meeting left an old `voicepen-*.caf` temp file | Startup temp cleanup deletes the stale VoicePen-owned `.caf` file |
| Expired recovery audio | Seven days pass after a failed meeting | VoicePen deletes retained audio and keeps the failed meeting row without retry |
| Meetings desktop layout | User opens Meetings on desktop | Meetings uses the shared transcript workspace with meeting-specific rows, center text, metadata, and recording controls |
| Meeting search metadata | User searches by transcript preview/full text, status, error, duration, audio source, ASR model, app version, or recording date/time | The loaded meeting list filters locally without decompressing every saved full transcript |
| Empty meeting search | User searches for a query with no matches | Meetings shows that no meetings were found and suggests trying another query |
| Meeting recording shortcut | User presses Command-R while the main VoicePen window is focused | VoicePen starts Meeting recording when idle, or stops the active Meeting recording |
| Failed meeting detail | User selects a failed meeting with no transcript | The center editor surface shows the saved error text as read-only content |
| Meeting transcript editor | User selects a saved meeting | The shared center workspace shows the transcript and copies the full saved transcript through the meeting copy action |
| Switch meeting selection | User selects text in one meeting transcript, then focuses another meeting | The transcript selection is cleared, the footer shows zero selected characters, and Command-C copies the newly focused full transcript unless the user selects text again |
| Meeting sidebar metadata | User selects a saved meeting | The sidebar shows Status, Recording, Duration, Audio sources, Processing, Speakers detected, and Actions; Speakers detected shows the saved structured count when present |
| Meeting stage actions | User selects a saved meeting | The editor offers Copy transcript, the right sidebar offers Delete recording as the bottom destructive action, recoverable entries may keep retry, and the UI does not show playback, waveform, audio player, export, speaker profile, voice-profile linking/creation, or transcript editing actions |
| New meeting row | A meeting finishes and a new row appears in Meetings history | The row preview text is visible immediately |
| Timecoded meeting preview | A saved meeting transcript line starts with a meeting timecode | The Meetings list preview hides the timecode and keeps the spoken text |
| Open Meetings | Saved meetings include large or compressed transcripts | The list opens from metadata and previews without decompressing every full transcript |
| Focus meeting | User selects a saved meeting | The full transcript for that meeting is loaded for the center workspace |
| Meeting day groups | Saved meetings include entries from multiple local calendar days | Meetings appear under sticky day sections while preserving newest-first order within each day |
| Copy transcript | User clicks Copy transcript in the editor | Transcript is copied without calling an LLM provider or showing an Insert Transcript action |
| Copy transcript shortcut | User presses Command-C with a saved transcript open and no text input or selected transcript range handling copy, including on a non-Latin keyboard layout | Full transcript is copied and the editor Copy action shows copied feedback |
| Selected transcript shortcut | User selects transcript text and presses Command-C | Selected text is copied instead of the full transcript |
| Stable copy feedback | Copy transcript action changes to copied feedback | The action keeps its existing dimensions |
| Present meeting transcript features | Transcript already shows timecodes | Meeting detail does not add duplicate `Present` metadata rows |
| Missing meeting transcript features | Model supports timestamps but transcript has no timecodes | Meeting detail shows that the feature was not present |

## Test Mapping

- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers start, stop, cancel, composite microphone/system-audio source recording, active wall-clock duration, cleanup after canceled start, and partial source failure with fakes.
- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers the meeting audio sink writing 16 kHz mono 16-bit PCM files.
- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers Meeting system audio tap planning, older-macOS process-object app filtering, and preflight fallback.
- Automated: `VoicePenTests/Meetings/MeetingRecordingStoreTests.swift` covers scheduling, canceling, and firing the one-time recording limit reminder.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers local transcription flow, chunk ordering, overlapping source merging before transcription, 16-bit PCM merged chunk output, optional meeting timecodes, separate diarization speaker labels, app version metadata, active wall-clock duration, processing recovery audio beyond the live recording limit, silent source chunks, all-silent discard, known subtitle/outro artifact cleanup, chunk timeout partial salvage, recovery audio retention and retry, temporary audio cleanup, and no automatic insertion.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers saved Meeting audio scheduling after chunking, cancel/no-save behavior, and retry without duplicate saved audio.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveTests.swift` covers byte-for-byte saved audio copies, readable source/chunk filenames, extension preservation, and oldest-first pruning.
- Automated: `VoicePenTests/AudioProcessing/SavedAudioArchiveSchedulerTests.swift` covers asynchronous saved-audio scheduling, request forwarding, non-fatal archive failures, and serialized copy/pruning work.
- Automated: `VoicePenTests/App/AppPathsTests.swift` covers stale VoicePen-owned `.wav` and `.caf` temporary audio cleanup while preserving recent and unrelated files.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers removing repeated short trailing Meeting transcription hallucinations.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers diarization chunk planning, full-recording diarization request wiring, very-short Auto diarization skip with exact-count override, speaker turn postprocessing, word overlap speaker merge, segment midpoint fallback, uncovered-gap behavior, tiny-overlap rejection, diarization failure fallback, saving detected speaker count, and separate diarization execution before ASR chunk formatting.
- Automated: `VoicePenTests/Meetings/MeetingDiarizationModelDownloadTests.swift` covers Meeting diarization Hugging Face artifact selection, URL construction, and proxy-aware download session configuration.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers prompting for an expected Meeting diarization speaker count when diarization is enabled.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers Meeting diarization model lifecycle state, automatic warmup when diarization is enabled, automatic warmup after a successful diarization model download, and keeping transcription model warmup running when Meeting recording starts.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers Meeting voice leveling routing and fallback.
- Automated: `VoicePenTests/Meetings/MeetingHistoryEntryTests.swift` covers Meeting list preview fallback text and omission of leading transcript timecodes.
- Automated: `VoicePenTests/Meetings/MeetingHistoryStoreTests.swift` covers append, preview-only list load, focused full transcript load, delete, compression, separate storage budget, partial entries, error entries, model/app version metadata, detected speaker count, recovery manifests, and expired recovery cleanup.
- Automated: `VoicePenTests/Meetings/MeetingHistoryFilterTests.swift` covers Meeting-specific search fields across loaded transcript preview/full text, recording date/time, status, error, duration, audio source labels, ASR model, app version, and avoiding full-transcript decompression on screen open.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift` covers shared filtering mechanics and empty search behavior.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptEditorMetricsTests.swift` covers transcript editor line, character, and selected-character counting, including empty text, trailing newlines, and Unicode text.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift` covers shared list grouping by local calendar day while preserving entry order.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers `meeting_history` creation and migration from old databases.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers consent gating, permission gating, meeting state, Meeting system audio source settings updates, selected-app fallback, meeting processing state, live recording limit auto-stop, silent recording discard prompt/no-history behavior, meeting timeout recovery, and no conflict with dictation history.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu and sidebar meeting commands, header recording controls, shared transcript workspace wiring, main-window Command-R recording shortcut wiring, right sidebar metadata/actions content, empty search UI, allowed actions, absence of out-of-stage playback/waveform/audio-player/export/speaker-profile/voice-profile/editing actions, meeting processing UI, Settings screen placement for Meeting features, Meeting system audio source settings controls, stable shared copy-button feedback behavior, meeting status icons in navigation surfaces, recording limit display, and recording pulses in the menu bar, Meetings header, and persistent status panel.
- Manual: Meetings desktop UI review covers the three-pane visual layout, independent pane scrolling, compact search field, right sidebar compactness, bottom Delete recording placement, transcript editor Copy action, line numbers, bounded line-number separator, selected-character count, read-only transcript selection/copying, and clearing transcript selection when switching focused meeting rows.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers Meeting system audio source defaults, persistence, invalid mode fallback, and invalid selected-app filtering.
- Manual: switch the Settings screen Meeting system audio source between all system audio and filtered modes; verify selected-app controls hide and show without SwiftUI publishing warnings, then use the add-apps control, select multiple macOS `.app` bundles, and verify they appear with bundle identifiers.
- Manual: record real meeting audio with microphone plus Zoom, Meet, or browser audio and verify both sides appear in the transcript.
- Manual: finish a new meeting while the Meetings screen is open and verify the new history row text appears without scrolling.
- Manual: open Meetings on desktop and verify the left searchable date-grouped list, center read-only transcript workspace, and right metadata/actions sidebar scroll independently.
- Manual: open Meetings with entries from several days and verify meetings are grouped by day and the current day header sticks while the list scrolls.
- Manual: deny System Audio access and verify the recovery path.
- Manual: stop, cancel, fail, retry, and expire a recording and verify temporary audio and recovery audio follow the documented cleanup behavior.

## Notes

Meeting Mode v1 uses separate audio-only sources for microphone input and system
output audio. VoicePen does not use ScreenCaptureKit or persist screen/video
frames for Meeting Mode. OpenRouter and hosted LLM providers are outside this v1
flow.

## Open Questions

- None.
