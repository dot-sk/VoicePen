# ADR: Meeting Diarization Backend Boundary

Date: 2026-05-07

## Status

Accepted

## Context

Meeting diarization needs to produce stable speaker turns for recordings from
about one minute to two hours. A custom Silero VAD to WeSpeaker embedding path
made Silero false negatives too important: missed speech regions produced no
speaker evidence, and transcript fallback labeling could only hide the gap.

## Decision

- VoicePen owns a backend boundary of full meeting timeline recording in,
  global speaker turns out.
- Physical chunking is an implementation detail inside a backend, not part of
  VoicePen's speaker identity model.
- The default backend is speech-swift's Pyannote diarization pipeline.
- Silero VAD is not used as a hard pre-filter in the default backend.
- VoicePen still postprocesses backend speaker turns and merges them with ASR
  timestamps, but it does not create speaker labels for uncovered transcript
  spans.
- Sortformer remains a candidate backend to compare separately behind the same
  boundary.

## Consequences

VoicePen no longer depends on a custom VAD-window-clustering chain for Meeting
Mode. Backend swaps are easier because Pyannote and Sortformer can both fit the
same contract. Exact speaker count is carried through VoicePen's request, but
the Pyannote backend may not be able to force that count until speech-swift
exposes such a control or VoicePen adds a backend-specific adapter.

## Links

- `Specs/2026-05-05-meeting-recording-mode.md`
- `VoicePen/Features/Meetings/MeetingDiarization.swift`
