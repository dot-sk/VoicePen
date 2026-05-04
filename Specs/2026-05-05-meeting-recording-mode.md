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

During recording, VoicePen shows persistent controls with elapsed active time,
microphone status, system audio status, pause or resume, stop, and cancel. Pause
excludes paused time from transcript processing. Cancel deletes temporary audio
and creates no history entry. Stop runs local transcription, saves a meeting
history entry, and deletes temporary audio after success or failure.

Meeting history is separate from dictation history. It stores transcript text,
duration, creation date, source flags, partial status, errors, timings, and local
model metadata with a separate transcript storage budget. Meeting entries are
excluded from dictation usage totals and milestones. Meeting transcripts can be
copied or manually inserted, but Meeting Mode never auto-pastes output.

Meeting Mode v1 captures both microphone input and system output audio where
available, chunks transcript processing by start time, caps meeting processing
at 120 minutes, and uses 1 minute chunk windows. v1 does not provide summaries,
action items, ticket drafts, engineering notes, or speaker diarization.

## Acceptance Criteria

- When Meeting Mode starts before consent acknowledgment, VoicePen shall show the consent reminder first.
- When microphone permission is missing, VoicePen shall not start recording and shall identify microphone as missing.
- When system output audio capture cannot start because permission is missing, VoicePen shall identify system audio permission as missing.
- When microphone permission is available and system output audio capture starts, VoicePen shall start one meeting session that captures microphone and system audio.
- Meeting Mode v1 shall not request or use screen capture for meeting recording.
- When recording is paused, VoicePen shall exclude paused time from the final transcript.
- When recording is canceled, VoicePen shall delete temporary audio and not create meeting history.
- When recording is stopped, VoicePen shall transcribe locally and save a meeting entry.
- When transcription completes or fails, VoicePen shall delete temporary audio.
- When one captured source chunk is silent but another source chunk contains speech, VoicePen shall skip the silent chunk and keep processing the meeting.
- When all captured chunks are silent, VoicePen shall save a failed meeting entry that identifies no detected speech.
- When one source fails mid-recording, VoicePen shall stop capture and mark the session partial.
- When transcript exists, VoicePen shall let the user copy it without calling any LLM provider.
- When transcript exists, VoicePen shall let the user manually insert it, but shall never auto-paste meeting output.
- When meeting transcript exceeds one chunk, VoicePen shall preserve chunk order.
- When meetings are deleted, VoicePen shall delete meeting rows and leave dictation history unchanged.
- Meeting history shall not contribute to the general dictation minutes, word counts, streaks, or milestones.
- The main window settings navigation shall place Meeting Mode immediately after General settings, before Modes, AI, Dictionary, and the remaining settings sections.
- While Meeting Mode is recording, paused, or processing, VoicePen shall show meeting-specific status icons in the menu bar and main window navigation.
- While Meeting Mode is actively recording, the menu bar icon shall show a clear recording indicator with a non-intrusive red pulse so the user can notice that capture is still running.
- OpenRouter shall not be called anywhere in Meeting Mode v1.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| First meeting | User chooses Start Meeting Recording | Consent reminder appears before recording starts |
| Missing microphone | Microphone permission is denied | Recording does not start and microphone is identified as missing |
| Missing system audio | System output audio capture is denied | Recording does not start and system audio is identified as missing |
| Cancel meeting | User cancels an active recording | Temporary audio is deleted and no meeting row is saved |
| Stop meeting | User stops an active recording | Local transcription runs, meeting history is saved, temporary audio is deleted |
| Manual insert | User clicks Insert Transcript on a saved meeting | Transcript is inserted only from that explicit action |

## Test Mapping

- Automated: `VoicePenTests/Meetings/MeetingRecordingStateTests.swift` covers start, pause, resume, stop, cancel, composite microphone/system-audio source recording, and partial source failure with fakes.
- Automated: `VoicePenTests/Meetings/MeetingPipelineTests.swift` covers local transcription flow, chunk ordering, cap handling, silent source chunks, temporary audio cleanup, and no automatic insertion.
- Automated: `VoicePenTests/Meetings/MeetingHistoryStoreTests.swift` covers append, load, delete, compression, separate storage budget, partial entries, and error entries.
- Automated: `VoicePenTests/Persistence/DatabaseMigratorTests.swift` covers `meeting_history` creation and migration from old databases.
- Automated: `VoicePenTests/App/AppControllerTests.swift` covers consent gating, permission gating, meeting state, and no conflict with dictation history.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers menu and sidebar meeting commands, meeting status icons in navigation surfaces, and the menu bar recording pulse.
- Manual: record real meeting audio with microphone plus Zoom, Meet, or browser audio and verify both sides appear in the transcript.
- Manual: deny System Audio access and verify the recovery path.
- Manual: stop, cancel, and fail a recording and verify temporary audio is removed.

## Notes

Meeting Mode v1 uses separate audio-only sources for microphone input and system
output audio. VoicePen does not use ScreenCaptureKit or persist screen/video
frames for Meeting Mode. OpenRouter and hosted LLM providers are outside this v1
flow.

## Open Questions

- None.
