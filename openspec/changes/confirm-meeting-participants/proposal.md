## Why

A voice audible behind a meeting participant can become a separate speaker label and inflate the saved participant count. Raw diarization identities need evidence of participation before VoicePen presents them as meeting participants.

## What Changes

- Add a backend-independent participant confirmation pass before transcript assignment and counting.
- Require accumulated speech and repeated independent contributions; adjacent fragments of one background event must not count as repeated participation.
- Preserve recognized text in unconfirmed regions without inventing a participant or assigning that speech to another person.
- Keep saved counts consistent with confirmed transcript labels and expose aggregate confirmation diagnostics.
- Evaluate the policy against background speech and infrequent genuine participants before enabling it. Existing model selection remains unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `meeting-recording-mode`: distinguish detected voices from confirmed meeting participants when assigning labels and saving speaker counts.

## Impact

Meeting diarization postprocessing, MeetingPipeline speaker analysis and transcript assignment, focused Swift Testing coverage, and private local evaluation fixtures. No new models, dependencies, schema migration, settings screen, or automatic rewrite of existing history.
