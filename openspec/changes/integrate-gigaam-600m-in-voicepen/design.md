## Context

See [proposal.md](proposal.md) for the product outcome. `add-gigaam-600m-transcribe-fork` owns conversion, native correctness, model capabilities, and the accepted package/model pair. Its preserved prototype is an input, not an application dependency ready for release.

Current integration points:

- `ModelManifestModel` and `ModelBackend` represent only Whisper as a supported backend; `supportsTimestamps` assumes every Whisper model supports timing.
- `RoutingTranscriptionClient` captures a model/profile in `PreparedTranscription`, attaches history metadata, and routes only to `WhisperCppTranscriptionClient`. Warmup and downloads have equivalent single-backend dispatch.
- `AppModelRuntimeStore` owns download/warmup effects. Its late-completion callbacks need model/generation checks when adding cross-family changes.
- Model settings use `controller.modelManifest.compatibleModels` and shared persisted settings. The tray language submenu currently exposes the same global language preference without capability gating.
- Dictation builds a glossary and normalizes after decoding. Meeting processing currently adds VAD and requests timestamps whenever timecodes or diarization is enabled.
- Both `Package.swift` and `VoicePen.xcodeproj/project.pbxproj` directly consume `Vendor/whisper.spm`. Both old Whisper ggml and the research transcribe.cpp ggml define the Objective-C class `GGMLMetalClass`, and both look for Metal resources. A standalone Swift import test cannot establish safe coexistence.

## Goals / Non-Goals

Deliver the existing model-installation and recognition workflow for the accepted GigaAM F16 profile, with one shared GigaAM service for dictation and Meetings. Keep native ownership and cancellation local to the adapter; retain `AppController` as the composition/facade layer.

This change consumes the native acceptance evidence and adds application acceptance. It does not reimplement CTC, move Whisper to transcribe.cpp, add Python runtime inference, or implement forced alignment, punctuation restoration, or beam search for GigaAM. Initial GigaAM output is text-only. Existing offline SpeakerKit remains a separate feature available when the selected ASR supports its timing inputs.

## Decisions

### Consume a pinned package and isolate its internals

Add a local Swift package wrapper under `Vendor/transcribe.spm` for the accepted macOS arm64 XCFramework and its resource/identity manifest. Pin source/build provenance and checksums; use the same package in SwiftPM and the Xcode app. The wrapper must resolve an immutable accepted artifact, never a research `.local` dylib or mutable branch. Artifact placement/download mechanics follow the build environment, with a repository-owned reproducible preparation command and no checked-in model weights.

Package transcribe.cpp as a dynamic framework containing its private ggml, with hidden C/C++ internals and an export list limited to its public C ABI. Remove its Objective-C Metal resource class when embedding framework-owned Metal source, or uniquely prefix any retained globally registered classes; ordinary hidden symbols do not isolate Objective-C class registration. Bind Metal lookup to this framework's own packaged kernels, not a process-global environment variable or a shared `default.metallib` location. Validate exported symbols, dependent library paths, both backend load orders, and a relocated app with both runtimes linked. If the predecessor's package needs these packaging patches, make that correction there, rerun affected native gates, and accept the new exact pin before app adoption.

This is recorded in proposed [ADR-0014](../../../Docs/adr/2026-10-19-coexisting-local-asr-runtimes.md). Statically linking both unmodified ggml versions risks symbol collisions; sharing one ggml ABI would couple unrelated versions; replacing Whisper would expand scope and invalidate its existing evidence.

### Reuse verified delivery and keep defaults stable

Add one stable GigaAM F16 model ID tied to the accepted multilingual checkpoint, distinct from upstream GigaAM v3 and optional Q8. Extend manifest/backend decoding compatibly, retaining safe defaults for old manifests. Keep the recommended Whisper ID and all valid saved selections. List accurate supported languages from accepted model metadata; do not copy the prototype's incomplete ru/en/kk list or conflate multilingual recognition with configurable language forcing.

The main GGUF is the only ASR weight artifact for GigaAM. Reuse `VerifiedModelAssetDownloader` and model download event/state handling through a GigaAM downloader and `RoutingModelDownloadClient`. Installation checks require validated content and the completion marker, not only directory existence. Deletion waits for safe resource release and affects only the selected app-managed model directory.

Extend existing `scripts/build-model-assets.sh` and publication manifest preparation as needed. Prepare exact size, digest, license notices, immutable release coordinates, and local install fixtures before external publication review. A real distributable manifest entry cannot be completed using an invented URL or a missing release asset. No runtime Hugging Face discovery/download is introduced. Local tests inject fixtures through the downloader's existing seam.

### Resolve saved preferences into an explicit effective request

Use a small value-type capability policy shared by request preparation, Model settings, diagnostics, and tray menu state. Retain global saved preferences through `AppSettingsStore`; derive GigaAM's effective automatic multilingual, greedy CTC, text-only configuration without mutating those preferences. Disable unsupported model controls with a short reason; switching back to Whisper restores their existing behavior. Keep the tray as native AppKit menu snapshots.

Treat the initial GigaAM application adapter as text-only even if a future native build offers additional options. Opting into timing/prompting requires its own evidence and behavior change. The adapter submits only supported native defaults, no fixed-language override, glossary prompt, beam, timestamp request, or Whisper VAD flag. It must not send an unsupported explicit option and rely on silent native ignoring. A caller bypassing the effective policy receives a typed unsupported-option error. Report saved and effective settings separately.

The alternative of changing the global settings to match each model would lose preferences. Silently passing Whisper's options would fail the native contract and mislead users about what was applied.

### Keep one shared GigaAM adapter with explicit native ownership

Implement `GigaAMTranscriptionClient` and an isolated native context service, injected alongside Whisper into the existing routing and warmup paths. Reuse a narrow common backend protocol where necessary, without rewriting Whisper's implementation. Keep file/audio parsing, expensive native loading, and execution off the main actor. Decode each ASR input once to the runtime's required 16 kHz mono samples; do not rerun RNNoise, trimming, resampling, or application chunking inside the recognizer adapter.

Track one in-flight load by exact model content/package identity and hold ownership leases for prepared/in-flight requests. Swift actor reentrancy alone does not serialize async inference: use an explicit cancellation-aware queue or task-chain gate. Dictation and Meeting calls for GigaAM share that instance. Coordinate expensive cross-family load/inference through a small shared execution gate so a model switch does not start competing native work; keep this outside app state/UI. Canceling a queued request removes only that request.

The native model/session and C result buffers have deterministic ownership and cleanup. Swift task cancellation drives the native abort callback through a thread-safe per-request cancellation token. A stale canceled operation cannot abort a later request, insert text, publish readiness, or save success. A timeout stops waiting promptly while non-cooperative native work remains tracked until its real completion; prevent overlapping reuse/free. After failure, clear failed state and allow retry. Release inactive contexts once their owners finish rather than retaining both model families indefinitely.

Guard `AppModelRuntimeStore` callbacks by captured model and operation generation, including completion/failure and task cleanup. An old warmup must not clear a new warmup task. Keep existing model-wait versus processing-timeout semantics and preserve permission/missing-model states.

### Capture routing once for each workflow

`RoutingTranscriptionClient` captures model identity, package identity, effective configuration, and metadata into a prepared request. No later selection read is allowed to change that request's model or history attribution. Preserve the current guard against changing models during active dictation. Test captured-request isolation directly and during permitted Meeting/model-change flows.

Dictation retains its current preprocessor, dictionary normalization, insertion, and empty/error paths. Meeting processing and retry prepare once for the complete master, derive timecode/diarization/timeline preprocessing from the captured effective capabilities, and submit one request. GigaAM's 25-second planner remains inside the native library, with retained encoder frames stitched before CTC collapse.

For GigaAM, suppress timestamp/VAD flags and skip timestamp-dependent speaker analysis. Save plain text with empty timing segments, actual model/app metadata, and existing recovery/status rules. Show feature unavailability in Model settings and Meeting controls without rewriting stored preferences. Timing-free GigaAM processing must not reserve progress for skipped diarization. Existing Whisper timing, VAD fallback, and SpeakerKit remain unchanged.

Dictionary snapshots and deterministic replacements are still taken/applied in each pipeline. The native adapter boundary accepts glossary prompts only for a capable backend. No dictionary is added or tuned to make this port pass quality acceptance.

### Accept application quality independently of native parity

Build an offline evaluation entry point that calls the production Swift GigaAM adapter with the accepted package/model on the frozen 27 saved ASR-input WAVs. Those inputs are already preprocessed: feed them directly to the adapter and do not preprocess them a second time. Compare raw adapter/native text before post-filtering and dictionary replacement; require equality after the frozen base normalization to the accepted native F16/stock25 candidate on every recording. Keep any final-text/dictionary result in a separately labeled output.

Use snapshot `c49eabd7e9a517bb85185f61c7b182af127071d3eaaa8ec49f8fc624fdec4561` and the same scorer/alias/hesitation hashes as the native change. Report base WER/CER, term spelling diagnostics, hesitation-filtered scores, and their composition. Freeze references and policies; do not accept only an aggregate score hiding per-file changes. Record exact package/model digests, effective policy, stage placement, cold load, warm inference, and application overhead separately. Never treat the research median as a UI latency guarantee.

Add separate pipeline tests proving the existing preprocessing and normalization path is applied once. Add packaged long-input coverage beyond 25 seconds and a bounded long-Meeting stress run at the existing 120-minute limit, with coverage/resource evidence and explicit OOM errors. This is not a claim that the current 81-second corpus validates multi-hour memory behavior.

## Risks / Trade-offs

- Two ggml implementations can collide in C symbols, Objective-C classes, or Metal lookup. Use the isolation package above and test the combined app, not just standalone clients.
- Swift cancellation does not by itself interrupt C++. Use per-request abort tokens, deterministic test checkpoints, tracked completion, and ownership tests.
- Full frontend and stitched-frame storage still grow with input length. Exercise long inputs and resource failures; never truncate or change context policy silently.
- GigaAM text-only Meetings do not provide timecodes or speaker labels. Show the limitation before use and retain preferences for Whisper.
- Model release coordinates and accepted artifact digests do not yet exist. They are required implementation outputs from the predecessor/delivery work, not unresolved product decisions or placeholders to ship.
- Native package isolation changes can alter the accepted binary. Re-run applicable native/package/full-corpus checks on the exact application dependency pin.

## Migration Plan

1. Implement and accept the predecessor's F16/stock25 package/model pair, including coexistence packaging where required. Record its evidence and immutable pins.
2. Add tests and model-capability policy, then package wiring, delivery, shared adapter/lifecycle, and both workflow routes. Prepare verified asset publication inputs; activate the distributable manifest only with real immutable coordinates.
3. Run `make test`, `make build`, focused hosted integration tests for bundle resources and native model selection/installation, and the Swift-adapter corpus evaluation. Review long-input results and retained Whisper behavior, including the separate Metal-only change if applied.
4. Preserve existing user selections on upgrade. A user opts into GigaAM through Model settings and confirms its weight download. No automatic download or model migration occurs.
5. Roll back to the previous accepted app/package pair. Do not delete GigaAM files or history on binary rollback; an older app follows its existing unsupported-selection recovery. No settings/history storage migration is required.
