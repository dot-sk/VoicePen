# VoicePen diarization runtime

This package wraps FluidAudio 0.17.7, Apache-2.0:
https://github.com/FluidInference/FluidAudio/tree/v0.17.7

The dependency has `traits: []`. VoicePen does not link the optional Rust
NemoTextProcessing engine. FluidAudio's other native helpers and resources remain
upstream; this is a small adapter, not an extracted fork.

`NemotronOfflineContext` only loads local Core ML files. VoicePen owns verified
proxy-aware downloads, readiness and deletion. The app cache releases this context
after the last active operation and does not prewarm it while idle. The adapter uses the offline
preset with `.all` compute units. One recording keeps its streaming state through
the final tail; each call gets fresh speaker state. Core ML prediction boundaries
serialize access to the shared mutable model buffers, with cancellation checks
and actor yields between predictions.

Model files come from FluidInference/nemotron-3-diarization-coreml revision
`25a90f97f254428d4b30374b76af9c74fdee8327`, `monolithic/v2`, plus
`learnable_sil_emb.bin`. URLs, sizes and SHA-256 are bundled in
`NemotronDiarizationModelFiles.swift`. The model is distributed under the
OpenMDW License 1.1. See the upstream model cards:

- https://huggingface.co/FluidInference/nemotron-3-diarization-coreml
- https://huggingface.co/nvidia/Nemotron-3-Diarization

Local regression, excluded unless explicitly enabled:

```sh
VOICEPEN_NEMOTRON_REGRESSION_ROOT="$PWD/.local/diarization-alternatives-20261022" \
  make test TEST_FILTER=inspectNemotronOnFrozenLocalAudio
```

It compares all postprocessed turns against frozen whole-buffer results on both
local meetings, repeats inference, and verifies cancellation followed by reset
and retry. These references verify integration parity, not human-labeled DER.
