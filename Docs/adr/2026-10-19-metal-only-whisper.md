---
id: ADR-0012
status: accepted
date: 2026-10-19
---

# Run Whisper ASR Entirely Through Metal

## Context

Whisper currently requires a large Core ML encoder companion and can trigger an expensive first compilation. Pinned whisper.cpp v1.8.5 already executes both ASR stages through Metal when supplied a model path without an adjacent companion. Local Q8 research demonstrated this with the same installed weights.

## Decision

Keep the pinned framework and weights. Bypass app-side Core ML ASR validation and initialize each context through an owned isolated symlink without adjacent companions. Preserve canonical model identity, context lifetime, load coordination, and Metal resource discovery. Require and download selected weights only for Whisper ASR readiness.

Retain legacy encoders for rollback and separate Meeting diarization. Report actual ASR acceleration and fail explicitly if Metal cannot initialize.

## Consequences

This avoids a custom framework distribution and removes ASR companion download/compilation. It depends on pinned supplied-path lookup, so upgrades require a real-runtime regression with legacy companions present. Profiles, model choices, timestamps, dictionary behavior, history, and routing are preserved.

ADR-0010's immutable GitHub distribution remains in force. Its shared Core ML ASR companion description is superseded for new Whisper installations; separate diarization distribution is unchanged.

## Verification

Pinned v1.8.5 completed Q5 and Q8 inference through the production adapter with both legacy companions and weights-only installations, in SwiftPM and a signed relocated app bundle. Initialization reported the selected Metal backend and both native ASR graphs. Tests confirmed context release and clean process exit.

The accepted frozen 27-recording Q8 corpus reproduced the historical Metal transcripts after the application's existing whitespace trimming, across 81 calls. Base WER/CER remained 7.8125%/4.2641%; the frozen term-alias protocol remained 6.9435%/3.6506%. Inference median was 0.9482 seconds, with model loading and warmup measured separately. This is a sequential host measurement, not a paired Core ML comparison. Q5 quality remains unmeasured. Detailed checks are recorded in the change's `verification.md`.

## Links

- `openspec/changes/use-metal-only-whisper/`
- `Docs/adr/2026-08-14-github-model-asset-distribution.md`
