# ADR: Meeting Recording Capture And Privacy

Date: 2026-05-05

## Status

Accepted

## Context

Meeting Mode records longer, more sensitive audio than push-to-talk dictation and
needs to capture both the user's microphone input and system output audio from
meeting apps. Users also need a clear boundary between local transcription and
any optional LLM features.

## Decision

- Meeting recording starts only from an explicit user action.
- v1 captures microphone input and system output audio through separate
  audio-only source clients.
- v1 uses AVFoundation for microphone input and Core Audio process taps for
  system output audio.
- ScreenCaptureKit is not part of the v1 Meeting Mode capture path.
- v1 transcription uses only local VoicePen transcription models.
- OpenRouter and hosted LLM providers are not part of the v1 Meeting Mode flow.
- Temporary source audio is deleted after every terminal path: success, failure,
  cancellation, and transcription cancellation.
- Meeting history stores transcripts and metadata, not raw meeting audio.
- Speaker diarization is not promised in v1.

## Consequences

Meeting Mode can produce a full local transcript while keeping raw meeting audio
short-lived and avoiding screen-recording prompts in the product flow. Summaries,
ticket drafts, action items, and speaker labels require separate product
decisions and specs.
