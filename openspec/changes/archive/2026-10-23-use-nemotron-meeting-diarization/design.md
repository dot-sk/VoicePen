## Context

The user chose the tested Nemotron offline + FluidAudio combination. Frozen local experiments use FluidAudio v0.17.7 and Core ML artifacts from FluidInference/nemotron-3-diarization-coreml revision 25a90f97f254428d4b30374b76af9c74fdee8327, monolithic/v2 offline. The streaming and whole-buffer interfaces produced bit-identical predictions on the long meeting. A size-only Release comparison measured +4.54 MiB for the full library after removing SpeakerKit, with optional text normalization disabled. These facts do not establish full speaker-attribution accuracy.

## Goals / Non-Goals

**Goals:** Adopt exactly that tested runtime and model preset, preserve meeting lifecycle and history, and remove the old dependency graph.

**Non-Goals:** New participant filtering, persistent voice profiles, a custom matcher, extracting a FluidAudio fork, or changing ASR/audio mastering. The old slim-diarization-runtime proposal is superseded in direction and is not implemented by this change.

## Decisions

### Pin the ready runtime behind a small local Swift package

Add Vendor/diarization.spm with a FluidAudio exact v0.17.7 dependency and traits: [], disabling optional NemoTextProcessing. Its small actor adapter owns local loading, serialized Core ML access and request-local Nemotron state. Core ML uses the tested .all policy, not a claim of ANE-only routing. Keep unrelated FluidAudio code upstream; do not copy or rewrite its cache/math implementation. Retain attribution and model license references in the package README and superseding ADR.

### Stream one full timeline through the offline preset

Feed bounded audio blocks through the offline-configured native streaming interface, accumulating the 10 ms results and flushing the tail. Keep cache/FIFO state for the whole recording and reset for each new recording. Check cancellation between blocks and yield at model execution boundaries so reset can invalidate active work. Verify parity with the frozen whole-buffer run, including the exact tail and repeated runs; do not restart state at arbitrary meeting chunks. The existing turn postprocessor and transcript assignment are retained.

### Keep installation in VoicePen

Bundle immutable per-file URLs, sizes and SHA-256 for the four compiled offline bundle files plus learnable_sil_emb.bin. Use VerifiedModelAssetDownloader with the existing proxy provider, not FluidAudio's downloading APIs. Download into a revision-specific sibling staging directory, validate the complete artifact set, write a revision-bound completion marker inside staging, then replace the managed model directory transactionally. Preserve the old directory on error/cancellation, and remove it only after successful replacement. Existing valid downloaded files in staging can be verified and reused by the shared downloader on retry.

Readiness requires the current marker and expected files/sizes. Native load remains a separate executable validity check; errors are surfaced through the existing lifecycle. No archive publication or external release is required.

### Normalize preferences, preserve history

Use a single lowercase nemotron backend identity, matching the existing case-insensitive settings normalization. All old/invalid values map to it. Reuse the managed DiarizationModels directory but distinguish installations by the new marker. No database schema change or automatic transcript rewrite is needed. Delete removes the managed model and any interrupted Nemotron staging files after resetting the runtime.

### Release the runtime immediately after use

Meetings are long enough that keeping an idle runtime offers little practical reuse. Do not prewarm diarization on app startup, model download or enabling the setting. Keep installed-file status separate from runtime-loaded state. The cache counts active warmup/analysis operations and releases the runtime when the last finishes, on success, error or cancellation. An overlapping request prevents premature unload. The next analysis loads local files again. Explicit diagnostic warmup also releases after validation. No timer or new setting is needed.

Core ML may keep internal caches or allocator pages after VoicePen drops its references. Do not promise that process RSS immediately returns to its baseline. A fresh diagnostic process repeatedly took about 46 seconds to load; same-process reloads were about 0.1 seconds. This is the accepted memory/latency trade-off.

## Risks / Trade-offs

- Native load returns non-Sendable model objects: transfer through an explicitly owned wrapper and keep inference isolated in the actor; coalesce loads and invalidate stale completions after reset.
- Dependency cleanup can break SwiftPM or Xcode independently: update both graphs and inspect Release link inputs for old products and optional Rust text normalization.
- Partial multi-file installation: staging plus verified replacement prevents readiness from describing a mixed model installation.
- Repeated recordings can contaminate identities: new request-local diarizer state, native repeated-input parity coverage and cancellation/retry tests.

## Migration Plan

Add contract tests, replace the dependency and adapter, update backend normalization/downloads, run make test and a Release app build, and exercise the production adapter on the frozen local meeting inputs. Record resource costs separately from quality. Sync the verified delta into main specs before handoff; do not commit, archive, install or publish automatically.
