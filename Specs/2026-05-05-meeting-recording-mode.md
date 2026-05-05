---
id: SPEC-011
status: active
updated: 2026-05-05
tests:
  - VoicePenTests/Meetings/MeetingRecordingStateTests.swift
  - VoicePenTests/Meetings/MeetingPipelineTests.swift
  - VoicePenTests/Meetings/MeetingHistoryStoreTests.swift
  - VoicePenTests/Persistence/DatabaseMigratorTests.swift
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
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
local model used for transcription with a separate transcript storage budget.
`Partial Transcript` means VoicePen saved non-empty transcript text but did not
process the full meeting. `Failed` means no usable transcript text was saved.
Meeting entries are excluded from dictation usage totals and milestones. Meeting
transcripts can be copied or manually inserted, but Meeting Mode never
auto-pastes output.

Meeting Mode v1 captures both microphone input and system output audio where
available, chunks transcript processing by start time, caps meeting processing
at 120 minutes, applies best-effort system voice leveling before transcription,
and uses 1 minute chunk windows. v1 does not provide summaries,
action items, ticket drafts, engineering notes, speaker diarization, pause, or
resume.

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
- When recording is stopped, the saved meeting duration shall use the active wall-clock recording duration, not the sum of microphone and system audio source chunk durations.
- When recording exceeds the 120 minute processing limit and supported audio produces transcript text, VoicePen shall process only the supported window, save the meeting as a partial transcript, and show a user-facing error reason that includes the limit in minutes.
- When processing produces no usable transcript text, VoicePen shall save the meeting as failed even if capture or processing was incomplete.
- Meeting history rows shall not let technical incomplete-capture or incomplete-processing flags override the product status shown to the user.
- When a saved meeting duration is shorter than one minute, meeting history items shall display the duration in seconds instead of fractional minutes.
- While stopped meeting audio is processing, VoicePen shall show that transcript processing is underway in the persistent status panel without showing microphone or system audio as unavailable.
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
- When local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Добавил субтитры ...", or "Продолжение следует...", VoicePen shall remove those lines from meeting transcripts before saving history.
- When one source fails mid-recording, VoicePen shall stop capture and mark the session partial.
- When transcript exists, VoicePen shall let the user copy it without calling any LLM provider.
- Meeting detail copy and retry actions shall use compact icon-only controls with accessible labels.
- When transcript exists, VoicePen shall let the user manually insert it, but shall never auto-paste meeting output.
- When meeting transcript exceeds one chunk, VoicePen shall preserve chunk order.
- When meetings are deleted, VoicePen shall delete meeting rows and leave dictation history unchanged.
- Meeting detail shall show user-facing processing information: the local model that decoded the meeting and the total processing time, without exposing backend/version metadata as a primary detail.
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
| Recording limit exceeded with text | User records longer than the supported meeting limit and supported audio contains speech | VoicePen saves a partial transcript, caps processed duration at the supported limit, and shows that the limit was reached |
| Recording limit exceeded without text | User records longer than the supported meeting limit and no supported audio yields text | VoicePen saves a failed meeting with no transcript and shows that the limit was reached |
| Hung meeting processing | Local processing does not return | VoicePen exits processing and surfaces a timeout error |
| Hung later chunk | First chunk transcribes and second chunk hangs | VoicePen saves the first chunk as a partial meeting and keeps recovery audio retryable for 7 days |
| Retry failed meeting | User uses retry on a failed meeting before recovery audio expires | VoicePen reprocesses local audio and updates the same meeting history entry |
| Expired recovery audio | Seven days pass after a failed meeting | VoicePen deletes retained audio and keeps the failed meeting row without retry |
| Manual insert | User clicks Insert Transcript on a saved meeting | Transcript is inserted only from that explicit action |

## Test Mapping

- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers start, stop, cancel, composite microphone/system-audio source recording, active wall-clock duration, cleanup after canceled start, and partial source failure with fakes.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers local transcription flow, chunk ordering, active wall-clock duration, limit handling, silent source chunks, known subtitle/outro artifact cleanup, chunk timeout partial salvage, recovery audio retention and retry, temporary audio cleanup, and no automatic insertion.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers Meeting voice leveling routing and fallback.
- Automated: `VoicePenTests/Meetings/MeetingHistoryStoreTests.swift` covers append, load, delete, compression, separate storage budget, partial entries, error entries, recovery manifests, and expired recovery cleanup.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers `meeting_history` creation and migration from old databases.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers consent gating, permission gating, meeting state, meeting processing state, meeting timeout recovery, and no conflict with dictation history.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu and sidebar meeting commands, header recording controls, meeting processing UI, meeting status icons in navigation surfaces, recording limit display, and recording pulses in the menu bar, Meetings header, and persistent status panel.
- Manual: record real meeting audio with microphone plus Zoom, Meet, or browser audio and verify both sides appear in the transcript.
- Manual: deny System Audio access and verify the recovery path.
- Manual: stop, cancel, fail, retry, and expire a recording and verify temporary audio and recovery audio follow the documented cleanup behavior.

## Notes

Meeting Mode v1 uses separate audio-only sources for microphone input and system
output audio. VoicePen does not use ScreenCaptureKit or persist screen/video
frames for Meeting Mode. OpenRouter and hosted LLM providers are outside this v1
flow.

## Open Questions

- None.
