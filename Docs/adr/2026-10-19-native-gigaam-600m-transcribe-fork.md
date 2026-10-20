---
id: ADR-0013
status: proposed
date: 2026-10-19
---

# Maintain a pinned native fork for GigaAM Multilingual 600M

## Context

The measured GigaAM Multilingual 600M checkpoint currently has a working Python/MLX research path. VoicePen needs a native package before a later application-integration decision. Upstream transcribe.cpp has C/Swift interfaces and a related ggml/Metal GigaAM encoder, but does not yet provide a verified conversion/profile for this checkpoint. The preserved research prototype reuses that encoder and has demonstrated matched-arithmetic whole-input transcript agreement on all 27 corpus recordings. The selected windowed profile still needs its own matched-window oracle, native regression tests and package validation. The source checkpoint, derived weights, runtime, and quantization formats have separate identities and provenance.

## Decision

Propose maintaining a small pinned fork of `handy-computer/transcribe.cpp`, initially based on v0.4.0 commit `1dc22facfc931e2f8adb43924b0e38b9c46f83c7`. Promote the existing converter and native prototype from the change's research handoff. Select F16 storage with the measured stock planner of windows up to 25 seconds and context up to 2 seconds per side. Prove numerical and decoded-output parity with a floating oracle using identical logical weights, activation arithmetic and window policy, preserve the research stock25 outputs, then evaluate optional native ggml Q8 under the same context policy. F16 means weight storage; native activations are F32. Keep default MLX F16-activation quality results as a separate comparator without changing accepted gold references.

Keep Python/MLX in offline conversion and validation only. Package native C++/ggml inference behind the existing C interface for Swift consumption. Use the existing host frontend, Metal encoder, and host CTC projection/search as the baseline, with explicit stage diagnostics and timings. The completed full-corpus A/B preserved quality and reduced summed recording medians by 0.42%, but its end-to-end confidence interval crossed zero. Keep the simpler host head; reconsider Metal projection only with parity and a repeatable end-to-end benefit beyond observed run noise. Required Metal must fail explicitly rather than silently run the encoder on CPU. Do not describe a host-head path as full GPU inference. Keep upstream v3 behavior unchanged. The new primary profile uses the measured stock-window policy; whole-input remains a separately labeled diagnostic. Stitch retained encoder frames before one CTC collapse and verify boundary repetitions and full input coverage.

Bind each candidate to pinned source/build/conversion inputs, licenses, digests, acceptance evidence, and a known-good rollback pair. Keep patches reviewable and evaluate upstreaming after the port is proven. This ADR authorizes no hosted fork creation or artifact publication and does not select a VoicePen model, change defaults, or integrate dictation/Meeting routing. It remains proposed until implementation and evidence review.

## Consequences

The native package avoids a shipping Python environment and reuses an existing multi-model interface. It introduces fork maintenance, native packaging, Metal resource validation, and checkpoint conversion ownership. Windowing bounds encoder attention workspace, while full frontend and stitched sequence memory still grow with recording length. Whole-input diagnostics may require more memory. Q8 availability can remain blocked by the conservative no-degradation gate even if F16 passes.

Waiting for upstream avoids ownership but leaves delivery outside our control. Shipping Python/MLX adds an inference environment and conflicts with the native goal. A new inference engine would duplicate more code than this bounded extension. If shared runtime changes become large or parity cannot be established, stop and review this decision rather than silently expanding the fork.

## Implementation status

The local reviewable recipe is `Vendor/transcribe-native`, using a pinned
upstream archive and two ordered patches. Candidate.2 embeds Metal source and
registers no Objective-C resource lookup class; it contains private static
ggml and exposes only the public C ABI. Its package remains unaccepted.
The exact release pair passes all 27 corpus transcripts against an independent
matched-window oracle and the frozen stock25 baseline, all F16 numerical
fixtures and speech boundary checks. These results do not accept every package
or compatibility gate.

F32 activations describe tensor storage. The pinned ggml Metal matrix kernel
uses half operands even with F32 weights. A separate F32-storage/Metal
diagnostic exceeds its strict NRMSE limit on four intermediate Kyrgyz blocks;
that failure is retained. No new kernel or relaxed tolerance is adopted.
The full F32/CPU graph diagnostic passes the strict limits, and clean repeated
packaging reproduces the exact binary and all content hashes. A newer
whole-input diagnostic head series preserves all 81 pairs and measures 0.844%
improvement, with a negative confidence interval. It does not certify a
stock25 Metal-head package; the selected shipping host head stays unchanged.
See the [implementation evidence](../../openspec/changes/add-gigaam-600m-transcribe-fork/implementation-evidence.md)
for exact candidate hashes, checks and remaining acceptance gaps. This ADR
stays proposed pending complete evidence review.

The reviewed exact F16 pair is accepted for host-local use on the tested
macOS 26.6.2 Apple Silicon machine, recorded in the separate
`host-local-acceptance.json` attestation. The immutable candidate manifest
remains unaccepted for distribution. Actual packaged C/Swift Metal execution
on macOS 15 is the remaining external F16 distribution gate; compiling with
deployment target 15.0 does not verify that runtime compatibility. The static
GGUF's content/conversion/quality/license verdict is independent of native OS
compatibility and does not authorize model publication.

## Links

- [Change proposal](../../openspec/changes/add-gigaam-600m-transcribe-fork/proposal.md)
- [Native runtime delta](../../openspec/changes/add-gigaam-600m-transcribe-fork/specs/native-gigaam-600m-runtime/spec.md)
- [Design and acceptance protocol](../../openspec/changes/add-gigaam-600m-transcribe-fork/design.md)
- [Upstream transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
- [Upstream multilingual request](https://github.com/handy-computer/transcribe.cpp/issues/87)
- [Separate Whisper-only decision](2026-10-19-metal-only-whisper.md)
