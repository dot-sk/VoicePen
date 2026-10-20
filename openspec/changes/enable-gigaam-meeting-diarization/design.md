## Context

The pinned GigaAM CTC package reports `max_timestamp_kind=NONE`, but `transcribe_get_token` exposes aligned decoded tokens with global frame positions. A probe on the user's 30-second Meeting excerpt returned 198 monotonic tokens across the internal 25-second window boundary. VoicePen currently drops timing requests before reaching GigaAM, so Meeting skips its diarizer.

## Goals / Non-Goals

**Goals:** Reuse GigaAM's own CTC alignment for Meeting word positions; preserve existing plain-text behavior when alignment cannot be trusted; keep the extra work off dictation's text-only path.

**Non-Goals:** A new aligner, another ASR pass, changing SpeakerKit clustering, rewriting existing Meeting history automatically.

## Decisions

- Treat the accepted package's token alignment as an application-level timing capability. Keep the model manifest's native timestamp flag false because `transcribe_run` still rejects timestamp requests. Translate the application timing request into token extraction after a normal text-only native run.
- Group contiguous non-whitespace token characters into words, retaining each group's first and last aligned positions. Verify token concatenation against the native text and reject missing, out-of-order, or out-of-range positions. Return plain text if alignment fails.
- Feed word timing through the existing Meeting transcript formatter and SpeakerKit merge. Speaker clustering remains the diarizer's responsibility. A one-second third label in the user's recording is a known SpeakerKit error and is not silently relabeled without a separate quality change.

## Risks / Trade-offs

- CTC positions can be less precise than Whisper word alignment. Existing overlap fallback and tests cover boundary behavior; the actual recording should be visually reviewed after retry.
- The native token API is exposed despite `max_timestamp_kind=NONE`. The package pin and native integration test protect this dependency; failure degrades to plain text.
