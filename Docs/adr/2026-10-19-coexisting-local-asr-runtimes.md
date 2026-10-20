---
id: ADR-0014
status: proposed
date: 2026-10-19
---

# Isolate the GigaAM runtime alongside Whisper

## Context

VoicePen already links a vendored whisper.cpp/ggml and needs to consume the accepted GigaAM transcribe.cpp package from ADR-0013. These runtimes use different ggml versions. Both checked source trees define `GGMLMetalClass` and perform Metal resource lookup. Standalone package success does not prove that both can run safely inside the same application.

## Decision

Keep Whisper on its current runtime. Consume GigaAM through a pinned dynamic macOS XCFramework with a public C ABI, hidden C/C++ internals, and framework-owned Metal resources. The selected package embeds its Metal source and removes the Objective-C resource class entirely; any future resource class must have a unique prefix. Link the same package in SwiftPM and the app target. Do not share one ggml ABI, expose internal ggml symbols, or select kernels through process-global overrides.

Require a combined-client and relocated-app test that loads and runs both backends in both orders, verifies actual stage placement and kernel provenance, and detects Objective-C class collisions, unresolved private dylibs, or resource crossover. Accept the exact isolated package/model pair after applicable native quality and package gates.

## Consequences

The application carries two native runtimes and their resources. This costs package size and packaging work, but lets each backend retain its own tested version and supports independent rollback. Static linking both unmodified libraries or unifying ggml would create broader coupling. Inactive native contexts are released after their last owner completes to limit memory retention.

This is a proposed dependency/distribution decision, not authorization to publish a package or app release.

## Links

- [Application integration change](../../openspec/changes/integrate-gigaam-600m-in-voicepen/proposal.md)
- [Integration design](../../openspec/changes/integrate-gigaam-600m-in-voicepen/design.md)
- [Native GigaAM strategy](2026-10-19-native-gigaam-600m-transcribe-fork.md)
