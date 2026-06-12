# ADR: Meeting Diarization Backend Boundary

Date: 2026-05-07

## Status

Accepted

## Context

Meeting diarization needs to produce stable speaker turns for recordings from
about one minute to two hours. The phase-1 migration standardizes on a
single backend path to remove backend swaps and custom pre/post-processing
branches that caused silent regions and recovery gaps.

## Decision

- VoicePen owns a backend boundary that consumes full meeting timeline audio and
  emits speaker turns in timeline coordinates, which are then mapped to
  transcript regions.
- Physical chunking and capture strategy are backend implementation details;
  VoicePen owns the merged full-timeline inputs and timeline remapping contract.
- The only supported meeting diarization backend is `SpeakerKit` from
  `argmax-oss-swift`.
- SpeakerKit is loaded from local artifacts with `download: false` during local
  warm/load/diarization operations after successful download and during playback
  flows.
- VoicePen validates backend readiness during warm/load and logs setup/load errors
  before processing to make model failures explicit.

## Consequences

VoicePen no longer depends on `speech-swift` backend variants or custom
clustering branches in Meeting Mode. A single local `.speakerKit` path keeps
frontend behavior stable while reducing complexity around backend-specific
controls and feature flags. Legacy backend values are normalized to `.speakerKit`
so migration is tolerant and automatic.

## Links

- `Specs/2026-05-05-meeting-recording-mode.md`
- `VoicePen/Features/Meetings/MeetingDiarization.swift`
