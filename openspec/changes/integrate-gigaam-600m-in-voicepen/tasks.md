## 1. Accepted dependency and delivery inputs

- [x] 1.1 Record the accepted F16/stock25 package/model pair from `add-gigaam-600m-transcribe-fork`, exact hashes, capabilities, license provenance, and native acceptance report. Do not substitute the research dylib, GigaAM v3, or an unaccepted Q8 variant.
- [x] 1.2 Implement or request predecessor packaging corrections for isolated dynamic linkage, hidden ggml symbols, isolated or absent Objective-C Metal resource classes, framework-owned kernels, and relocatable install names. Verify the export/dependency lists and rerun affected predecessor acceptance gates for the resulting pin.
- [x] 1.3 Prepare the exact GGUF model-assets manifest and immutable release coordinates using the existing build/publication tooling. Produce reviewable local assets, digests, notices, and install fixtures; complete external publication/readback before activating a distributable download entry. Never ship placeholder coordinates.

## 2. Behavior tests before application implementation

- [x] 2.1 Extend manifest, settings/controller, and model-menu policy tests for GigaAM selection/restart/missing weights, unchanged Whisper recommendation, effective capabilities, saved preference restoration, and metadata incompatibility. Map these to the coverage table below.
- [x] 2.2 Extend routing/download tests and add GigaAM adapter contract tests using injected native/file boundaries for dispatch, supported-option translation, raw text/results, model metadata, unavailable Metal, and typed native errors. Preserve existing Whisper routing/profile tests.
- [x] 2.3 Add deterministic async lifecycle tests for shared cold loading, serialization, canceled waiters, failed-load retry, old/new warmup generations, active-context leases, safe deletion, and queued/active cancellation. Use task handles and explicit checkpoints, not timing sleeps.
- [x] 2.4 Extend dictation and Meeting pipeline tests for captured recognizer/options, preprocessing once, dictionary replacement, complete-master requests, GigaAM text-only output, skipped diarization/progress, retry metadata, and no late insertion/save after cancellation. Keep existing Whisper behavior cases.
- [x] 2.5 Add verified GigaAM download/install tests for confirmation, progress, proxies, size/hash failure, atomic completion, cancellation/timeout/retry, and model-isolated deletion. Use temporary paths and local/injected payloads.

## 3. Native package and shared recognition service

- [x] 3.1 Add the pinned `Vendor/transcribe.spm` wrapper and reproducible artifact preparation/verification command. Wire the same accepted package into `Package.swift` and the Xcode project, including embedded framework signing and Metal resource delivery. Keep the existing Whisper dependency.
- [x] 3.2 Implement the GigaAM C-ABI bridge with file-to-16-kHz-mono input, typed statuses, model/session/result-buffer ownership, actual stage diagnostics, and explicit required-Metal execution. Keep expensive work off the main actor and avoid duplicate audio preprocessing.
- [x] 3.3 Implement tracked load sharing, explicit native execution serialization, per-request abort tokens, retry after failure, and safe release after outstanding owners finish. Add the small shared cross-family execution gate and verify cancellation cannot affect another request.
- [x] 3.4 Extend `RoutingTranscriptionClient` and warmup injection for GigaAM, capturing model/package/effective configuration once and attaching actual model metadata. Retain existing Whisper behavior without moving Whisper inference to transcribe.cpp.
- [x] 3.5 Update `AppModelRuntimeStore` and facade composition to guard load/warmup completion and cleanup by model plus operation generation, preserve timeout semantics, and release inactive resources safely during switches/deletion.

## 4. Model selection, installation, and capability-aware settings

- [x] 4.1 Add the stable GigaAM F16 manifest entry and backend with accurate accepted model languages, digest/size/version, installation marker checks, and backward-compatible capability decoding. Preserve existing recommended/selected Whisper IDs and their files.
- [x] 4.2 Implement the GigaAM downloader through `VerifiedModelAssetDownloader`, extend download dispatch, and reuse `AppModelRuntimeStore` progress/cancel/timeout/retry/delete behavior. Ensure incomplete assets never make the model ready.
- [x] 4.3 Implement the shared effective-capability policy for automatic/greedy/text-only GigaAM versus existing Whisper preferences. Gate unsupported native options, expose effective diagnostics, and retain saved preferences unchanged.
- [x] 4.4 Integrate GigaAM into the existing Model selector and lifecycle actions. Make language/decoding/Meeting feature controls and the native tray language submenu reflect the capability policy through shared settings, without per-screen draft persistence or SwiftUI tray rows.

## 5. Dictation and Meeting integration

- [x] 5.1 Connect GigaAM prepared requests to dictation through the shared router, preserving recording/preprocessing/normalization/insertion, empty/error/timeout behavior, and actual model/app history metadata.
- [x] 5.2 Prepare Meeting/retry recognition once with captured model/capabilities, submit the complete master, and preserve recovery and history semantics. For GigaAM, suppress timestamp/VAD requests, skip timestamp-dependent speaker analysis, and do not reserve progress for skipped work or synthesize timing segments.
- [x] 5.3 Preserve dictionary snapshots/replacements for both workflows, gating native glossary prompting to capable backends. Verify Whisper prompting, VAD retry, timestamps, diarization, and configured decoding profiles still work after switching back.

## 6. Application acceptance

- [x] 6.1 Add and run a combined native C/Swift client and hosted-app coexistence test with both model families in both load orders. Verify hidden private symbols, isolated or absent Objective-C resource classes, actual kernel provenance, cancellation/reuse, and a relocated packaged app with no development-checkout or Python/MLX runtime dependency.
- [x] 6.2 Add the offline evaluation entry point using the production Swift GigaAM adapter. Run all 27 frozen preprocessed ASR inputs with the accepted model/package, without a second preprocessing pass; require per-file base-normalized equality to accepted native F16/stock25 output. Report all four frozen WER/CER protocols, pins, cold/warm timing, and adapter overhead separately from optional final-text dictionary effects.
- [x] 6.3 Run packaged input tests beyond 25 seconds, cross-window speech/repetitions, and a bounded 120-minute Meeting stress case. Record full input coverage, memory, cancellation, and explicit resource failures; reject silent truncation or policy changes. Reuse predecessor fixtures/evidence when unchanged, but do not infer long-Meeting readiness from the 81-second corpus maximum.
- [x] 6.4 Run `make test`, `make build`, and focused hosted cases via `make integration-test` for selector/installation/capability state and bundle/native-resource behavior. Use injected model assets for UI lifecycle tests and the accepted local artifacts for native runs. Keep existing UI test IDs; do not assert presentation copy/layout in unit tests.
- [ ] 6.5 Exercise upgrade/restart with valid Whisper and GigaAM selections, switch back after each workflow, missing/corrupt assets, canceled queued/active work, retry after errors, diagnostics privacy, and previous-package rollback. Include the Metal-only Whisper configuration if that independent change is present.

## 7. Handoff

- [x] 7.1 Run `openspec validate integrate-gigaam-600m-in-voicepen --strict` and `git diff --check`. Review ADR-0014, the scenario coverage table, exact verification evidence, distributable asset coordinates, and dependency pins before accepting implementation.
- [ ] 7.2 Document installation/capability limits and known-good rollback inputs. Sync the five deltas to main specs before archiving after implementation. Keep any hosted publication or signed app release separate from local verification and report delivery steps still outstanding.

## Automated scenario coverage

The table maps scenarios to automated coverage. Completed local checks and exact evidence are recorded in [verification.md](verification.md); unchecked tasks may have candidate-only evidence pending dependency acceptance or delivery. The verified public GigaAM asset is active in the bundled manifest. Completed dependency tasks use the reviewed host-local acceptance on macOS 26.6.2; general macOS 15 distribution acceptance is still open in the predecessor.

| Spec scenario | Planned automated coverage | Tasks |
|---|---|---|
| Prepared audio requires several partial reads | `GigaAMAudioReadTests` full synthetic PCM equality; real adapter corpus asserts actual input count | 2.2, 3.2, 6.2, 6.3 |
| Select GigaAM in Model settings | `AppControllerTests`, manifest/settings tests, focused hosted selector action | 2.1, 4.1, 4.4, 6.4 |
| Restart with a valid GigaAM selection | temporary settings/install fixtures and controller startup tests | 2.1, 4.1, 6.5 |
| Upgrade with an existing Whisper selection | existing-manifest/settings compatibility and upgrade fixtures | 2.1, 4.1, 6.5 |
| Install the selected GigaAM model | routing/downloader/controller events plus hosted install fixture | 2.5, 4.2, 6.4 |
| Prepare and publish immutable GigaAM assets | offline publication plan/archive validation and publisher dry-run refusal fixtures | 1.3 |
| Published GigaAM assets fail readback | fail-closed publisher readback path; verified entry emitted only after both asset checks | 1.3 |
| GigaAM download fails verification or is interrupted | downloader fault and controller cancellation/timeout fixtures | 2.5, 4.2 |
| Delete GigaAM safely | model-runtime lease/deletion tests with temporary model directories | 2.3, 2.5, 3.5, 4.2 |
| Select GigaAM with saved Whisper preferences | shared capability-policy, controller/menu state, and native request tests | 2.1, 2.2, 4.3, 4.4 |
| Return to Whisper | persisted-preference round trip and backend switch tests | 2.1, 4.3, 5.3, 6.5 |
| Bundled model metadata disagrees with the runtime | manifest/native capability compatibility rejection fixtures | 2.1, 2.2, 3.2 |
| Copy diagnostics after GigaAM recognition | diagnostic value-model and captured native execution tests | 2.2, 3.2, 4.3, 6.1 |
| GigaAM Metal resources are unavailable | injected backend failure and packaged missing-resource tests | 2.2, 3.2, 6.1 |
| No decoding profile has been selected | existing settings fallback and effective-policy tests | 2.1, 4.3 |
| User selects maximum quality | existing Whisper routing/profile tests with capability policy | 2.1, 2.2, 5.3 |
| User selects standard decoding | existing Whisper routing/profile tests with capability policy | 2.1, 2.2, 5.3 |
| Decoding profile changes during transcription | prepared-request capture tests with explicit async checkpoints | 2.2, 3.4 |
| Meeting VAD decoding retries without VAD | existing Whisper VAD/profile retry tests | 2.2, 2.4, 5.3 |
| Local transcription completes or fails | effective-profile diagnostics tests without transcript logging | 2.2, 4.3, 6.5 |
| Warmup and both workflows request cold GigaAM | shared-load/serial execution checkpoints | 2.3, 3.3, 3.5 |
| Old warmup completes after a model change | controller/runtime old-success/failure/cleanup checkpoints | 2.3, 3.5 |
| Cancel a GigaAM load waiter and retry | waiter cancellation plus load failure/retry checkpoints | 2.3, 3.3, 3.5 |
| Switch models while a request owns GigaAM | captured-context lease and deferred release tests | 2.3, 3.3, 3.4 |
| Complete GigaAM dictation | pipeline fake/native adapter tests, metadata and insertion assertions | 2.4, 5.1, 6.2 |
| Selection changes after dictation preparation | prepared-router identity/configuration capture tests | 2.2, 2.4, 3.4 |
| Cancel or time out native GigaAM dictation | queued/active abort and no-late-insertion checkpoints | 2.3, 2.4, 5.1 |
| GigaAM returns silence or fails | pipeline empty/error fixtures and packaged silence/reuse tests | 2.2, 2.4, 5.1, 6.1 |
| Process a complete Meeting with GigaAM | Meeting complete-master/native-request/result-history assertions | 2.4, 5.2, 6.3 |
| GigaAM is selected with Meeting timing preferences enabled | effective policy and Meeting no-timing/diarization/progress decisions | 2.1, 2.4, 4.4, 5.2 |
| Retry a Meeting after selecting another recognizer | recovery-audio retry and captured metadata tests | 2.4, 5.2, 6.5 |
| Cancel GigaAM Meeting processing while dictation is waiting | shared-service queued/active per-request abort checkpoints | 2.3, 2.4, 3.3, 5.2 |
| GigaAM recognizes a configured dictionary variant | dictation/Meeting normalization plus native prompt-boundary assertions | 2.2, 2.4, 5.3 |
| Switch to Whisper with the same dictionary | Whisper glossary/pipeline regression and switch tests | 2.2, 2.4, 5.3 |
