## Context

See `proposal.md` for motivation and the delta spec for required behavior.

The bundled manifest currently offers Q5_0, Q5_1, and Q8_0. Model selection is stored as an ID in SQLite. Runtime lookup already falls back to the recommended model when that ID is absent from the manifest, but the stored value remains unchanged. Each downloaded model has its own directory under VoicePen's Application Support folder, so removing Q5_1 from the manifest alone would leave its files on disk with no corresponding Settings option.

The published `model-assets-v1` release is immutable and remains in use by older VoicePen versions.

## Goals / Non-Goals

**Goals:**

- Keep the stored selection, visible selection, diagnostics, and runtime model consistent after Q5_1 retirement.
- Delete only the app-managed Q5_1 directory during startup.
- Keep cleanup failure non-blocking and retry it on later launches.
- Preserve a working download path for released VoicePen versions that still support Q5_1.

**Non-Goals:**

- Deleting or modifying the published `model-assets-v1` release.
- Changing Q5_0 or Q8_0 model artifacts, decoding behavior, or descriptions.
- Adding a general model deprecation framework or database schema migration.

## Decisions

### Remove Q5_1 only from the current runtime catalog

Delete the Q5_1 entry from the bundled manifest. Keep Q5_0 as the recommended model and keep Q8_0 as the alternative.

The model asset build scripts, checksums, notices, and published GitHub release describe an existing immutable asset set. Leave them unchanged so old application versions can still install the model and the published release remains reproducible.

Alternative considered: remove the remote Q5_1 asset and its publication metadata. Rejected because this would break old VoicePen versions and contradict the immutable asset release contract.

### Persist the recommended model when a saved selection is no longer compatible

During startup, compare the loaded model ID with the compatible IDs in the current manifest. If it is absent, persist the recommended model ID before warmup or transcription state is prepared.

This makes the existing generic missing-or-incompatible fallback durable instead of adding a one-off database migration for Q5_1.

Alternative considered: rely on the current computed fallback while leaving Q5_1 in SQLite. Rejected because Settings and runtime state would depend on an invalid stored value on every launch.

### Clean one exact retired model directory during startup

Keep the retired Q5_1 ID as an explicit application constant. Resolve its directory through the existing Application Support path boundary and remove only that directory if it exists. Run cleanup before model warmup.

Handle deletion errors separately from the main startup failure path. Log the failure, continue with Q5_0, and attempt the same cleanup again on the next launch. Inject the cleanup operation at the startup boundary so success and failure behavior can be tested without file-permission tricks.

Alternative considered: delete every model directory absent from the manifest. Rejected because a broad sweep could remove artifacts from a newer version after rollback or from future compatible workflows.

## Risks / Trade-offs

- [The cleanup targets the wrong directory] → Build the path from the exact retired model ID and test that Q5_0, Q8_0, saved recordings, and unrelated files remain.
- [The Q5_1 directory cannot be removed] → Log the error, continue startup, and retry on the next launch.
- [A user rolls back after cleanup] → The immutable Q5_1 asset remains available, but the older app must download it again.
- [Q5_0 is not installed when Q5_1 is retired] → Preserve the existing missing-model state and require normal user-confirmed Q5_0 download.

## Migration Plan

1. Ship a manifest containing only Q5_0 and Q8_0.
2. On the first launch after upgrade, persist Q5_0 when the saved model ID is no longer compatible.
3. Remove the app-managed Q5_1 directory before scheduling model warmup.
4. Leave the published Q5_1 asset unchanged for older application versions.

Rollback restores the Q5_1 manifest entry. Users whose Q5_1 cache was removed can download it again from the existing immutable release.
