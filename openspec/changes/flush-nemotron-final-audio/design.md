## Context

The English Core ML runtime processes 35,840-sample chunks at 16 kHz. Its finish method pads a remainder but does not submit another context chunk. The local 153-recognition experiment recovered short-word failures with one additional silent chunk. It did not reproduce the user's reported sentence-final omission.

## Goals / Non-Goals

Supply final context to every Nemotron file request without editing original audio or adding a user-visible wait. Keep the application recording cutoff and other backend paths unchanged.

## Decisions

Append one zero-filled mono Float32 buffer inside the native Nemotron file adapter, after the source-file read loop and before finish. Keep its frames outside original submitted-sample accounting. Retain the existing cancellation checks and reset-on-success/error path. This reuses the existing final-only adapter shared by dictation and Meetings, rather than adding workflow-specific padding or a new buffering abstraction.

## Risks / Trade-offs

An additional inference chunk adds processing time. The experiment measured about 64 ms median paired overhead on this Mac; this is not a general latency guarantee. Short-word recovery was verified, while sentence-final recovery is not established. Silence and longer-speech native regression tests guard against obvious unwanted text.
