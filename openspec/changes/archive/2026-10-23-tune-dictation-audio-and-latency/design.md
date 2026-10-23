## Context

See proposal.md. RNNoise is selected by the existing settings closure. Pipeline results already serialize optional timings as JSON in history; no SQL migration is needed. AppController receives stop requests before it creates the processing task, including deferred stops during startup.

## Goals / Non-Goals

Capture the actual accepted release boundary without moving lifecycle orchestration. Keep settings controls and audio filters intact. Confidence highlighting is a separate change; punctuation is excluded.

## Decisions

- Change only the missing-value and initial RNNoise defaults. Explicit true and false remain authoritative; no bulk settings migration.
- Capture a ContinuousClock instant at the stop request and carry the earliest deferred release through startup into the pipeline. Default direct pipeline callers to the entry instant.
- Inject the pipeline clock for deterministic tests. Measure recording stop and model preparation separately, then measure the full interval immediately after synchronous insertion returns. Do not include input gain restoration or overlay cleanup afterward.
- Add optional fields to the existing Codable timings. Existing JSON decodes with nil fields. Preserve the previous measuredProcessingDuration meaning as a sum of the previous four processing stages, distinct from the actual total.

## Risks / Trade-offs

- Insertion completion is the app's attempt, not target-app acknowledgement. Label and document that boundary.
- RNNoise evidence is corpus-specific. Retain the toggle and saved choices.
- Deferred release must not leak into the next recording. Reset it at start, error, and when consuming the pending stop.

## Migration Plan

No SQL migration, preference overwrite, commit, or release. Existing sessions have absent new measurements.
