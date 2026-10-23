## Context

See `proposal.md` for scope. VoicePen validates and opens a Core ML companion before initializing pinned whisper.cpp v1.8.5. Setting `use_gpu=true` alone does not disable it. The runtime already falls back to a Metal encoder when no companion exists beside the supplied model path.

Local Q8 research used an isolated weight symlink without adjacent encoder files: WER 7.81%, CER 4.26%, median inference 0.96 seconds on the accepted 27 recordings. An earlier Core ML encoder baseline produced 8.49%, 4.80%, and 1.40 seconds. Different repeat counts and separate runs limit causal conclusions. Q5 quality improvement remains unmeasured.

## Goals / Non-Goals

**Goals:** Reproduce benchmark Metal execution using the existing framework and weights, remove ASR companion installation/compilation, and preserve current transcription contracts.

**Non-Goals:** Changing weights, quantization defaults, decoding, microphone processing, language choices, dictionary semantics, request scheduling, or separate Meeting diarization.

## Decisions

### Reuse the pinned runtime with an isolated model path

Create an app-owned directory per loaded context containing a symlink to canonical selected weights. Supply that path to initialization without any adjacent encoder companion. The pinned runtime derives the companion location from the supplied path rather than the symlink target. Remove app-side Core ML ASR validation and `MLModel` loading; retain GPU and packaged Metal kernel configuration for app and SwiftPM execution.

Alternative: compile a custom Core-ML-disabled framework. This creates binary distribution and maintenance work without a demonstrated need. Reconsider only if a future framework version breaks the isolated-path mechanism.

### Keep path lifetime separate from model identity

Shared-load identity remains the canonical model and artifact fingerprint, not the temporary alias name. Retain the directory with its context through initialization that continues after requester cancellation. Remove only owned paths after context release; use marked-directory cleanup after crashes. Do not copy, rewrite, move, or delete installed weights or legacy companions. Alias failures use the existing retryable model-load error path.

Keep the existing actor/routing path and all `transcription-model-loading` contracts: shared initialization, canceled waiters independent from native loading, cold loading outside processing timeout, selection isolation, and retry after failure. No new execution coordinator is needed.

### Install selected weights only

Remove ASR companion descriptors from bundled manifest and fallback. Update readiness, warmup, download sets, and required-artifact diagnostics. Reuse valid weights and completion state, including installations interrupted before the old companion finished.

Preserve immutable GitHub URLs, byte-size/SHA validation, proxy settings, confirmed downloads, progress, atomic installation, cancellation, and retry. Keep generic companion/archive utilities for other assets. Leave legacy encoder files and separate diarization assets intact.

### Verify actual Metal execution

Report the initialized encoder/decoder device rather than inferring execution from `COREML=1` or `use_gpu=true`. Verify the actual pinned framework with a legacy encoder beside canonical weights and the isolated supplied path. If Metal or packaged kernels cannot initialize, return an actionable error without silent CPU ASR. Routine diagnostics exclude transcript and prompt content.

The pinned public API does not expose context backend handles. Observe its initialization callback under a synchronous initialization lock. Require the selected MTL backend and both native encoder and decoder graph allocations, reject GPU/backend/library initialization failures and any successful Core ML encoder load. Keep only these structural signals, never raw native output. Native integration must also complete inference. Readiness accepts the existing verified weights-artifact marker when a legacy installation stopped before its companion, without modifying or removing legacy files.

Keep model metadata, profiles, glossary construction, dictionary normalization, timestamps, warmup ownership, dictation, and Meeting on their existing paths. Keep `AppController` thin.

## Risks / Trade-offs

- Supplied-path lookup depends on the pinned framework. Gate upgrades on a native regression with legacy companions present.
- An alias released too early can break non-cooperative loading. Retain it with context ownership and test cancellation, failure, retry, and cleanup.
- Metal resources can resolve differently in the app and SwiftPM. Verify both with actual Q5/Q8 weights.
- Old completion metadata can include companions. Test valid weights, partial old installs, invalid weights, and interrupted downloads without unnecessary redownloads.
- Quality gains are not established for all inputs or quantizations. Keep exact model/settings, immutable corpus, and timing boundaries when comparing results.

## Migration Plan

1. Add targeted behavior and native integration tests before implementation.
2. Implement isolated-path ownership and bypass Core ML ASR validation while retaining shared-load behavior.
3. Update weights-only readiness, manifest/fallback, downloads, and diagnostics without deleting existing model data.
4. Run focused checks, `make test`, `make build`, packaged Metal verification, and the same Q8 corpus comparison. Include Q5 native smoke checks; do not claim unmeasured Q5 quality gains.
5. Sync deltas into main specs and audit unrelated scenario preservation before archive. CLI-required complete modified-requirement envelopes retain unchanged scenarios verbatim solely for safe synchronization.

Rollback reuses existing weights. Older applications can reuse retained companions; a fresh weights-only installation may need its companion downloaded when run with an older application. No history or recording migration is needed.
