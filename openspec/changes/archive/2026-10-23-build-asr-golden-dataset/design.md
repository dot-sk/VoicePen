## Context

Saved WAVs and history text exist locally, but history text is an ASR draft, not truth. Existing saved WAVs generally follow preprocessing, so this initial corpus evaluates ASR inputs rather than raw capture quality. See proposal.md for motivation.

## Goals / Non-Goals

Provide a small review tool and a first private draft corpus. Recognition parameter sweeps, app UI changes, raw microphone capture changes, and automatic promotion of ASR output to gold are outside this change.

## Decisions

- Use Python standard-library SQLite/HTTP/JSON tooling and a static browser UI under Tools/ASRQuality. This avoids app-target wiring, package downloads, and new dependencies for a development-only workflow. Tests for this Python tool use unittest; existing Swift tests remain unchanged.
- Keep the default corpus under .local/asr-quality, excluded from Git. Store immutable source metadata and drafts in dataset.json; store user references separately in references.json with a revision for stale-save detection. Use atomic JSON replacement.
- Seed the user's selected 27 real dictations of at least 20 seconds of actual audio, longest first. Do not add shorter controls to reach a count. Add duplicate four-word sequence counts as review hints; only human listening establishes errors. Copy original ASR-input WAV bytes unchanged. Generate separate PCM16 playback derivatives for browser compatibility. Snapshot current glossary/settings for provenance without claiming these were the original historical settings.
- Use explicit draft/confirmed/excluded states and a no-speech choice. Confirmed text transcribes what is audible, preserves words and repetitions, and uses correct conventional technical spellings. Unclear recordings can be excluded; the user does not need to guess.
- Export confirmed samples into content-addressed local directories with original audio and SHA256. Later edits produce another snapshot. No evaluation result is reported until a verified corpus exists.
- Bind to 127.0.0.1, check same-origin mutation requests, restrict resource paths to manifest entries, and support audio ranges. No upload, cloud service, or model execution is needed.

## Risks / Trade-offs

- Historical ASR may anchor the reviewer: label every imported text as a draft and instruct listening before confirmation.
- Derived audio cannot test capture/preprocessing changes: retain provenance and state this limitation in the UI and documentation.
- A small selected corpus is not a population quality estimate: use it first for regression and per-example comparisons; expand with real failures later.
- Gold creation depends on manual review: deliver all entries unconfirmed and report the actual confirmed count.
