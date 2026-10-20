## 1. Automated behavior contracts

- [x] 1.1 Extend manifest/model-runtime/download tests for `Whisper.cpp model is selected`, `Valid Whisper weights exist without an encoder companion`, `Legacy encoder files remain beside the weights`, and `Whisper installation is new or incomplete`. Cover both quantizations, valid completion-state reuse, invalid weights, interrupted installs, and unchanged selection/defaults.
- [x] 1.2 Add context-load tests for owned alias lifetime, canonical identity sharing, creation failure, missing targets, retry, and cleanup restricted to owned paths. Retain existing loading tests for canceled waiters, non-cooperative initialization, selection changes, and cold-load timeout exclusion. Do not inspect production Swift source as text.
- [x] 1.3 Add an automated native regression for `Whisper.cpp runs on Apple Silicon`: initialize the pinned framework with legacy encoder files beside canonical weights and assert actual Metal encoder/decoder execution through the isolated path. Verify app and SwiftPM resources. Large-weight checks can be opt-in locally but are mandatory for release.
- [x] 1.4 Add diagnostics and unavailable-device/resource tests for `Diagnostics are copied` and `Metal ASR cannot initialize`. Assert actual device signals, required artifact status, no transcript/prompt logs, and actionable failure without silent CPU inference.

## 2. Whisper loading and artifact migration

- [x] 2.1 Implement owned isolated weight paths in the context/load path using the pinned framework and canonical model identity. Remove app-side Core ML ASR validation/loading and preserve GPU/kernel configuration.
- [x] 2.2 Update bundled manifest and fallback, weights-only readiness, downloads, warmup checks, and artifact diagnostics. Reuse valid weights and completion state; preserve IDs, selected quantization/profile/language, legacy files, and separate diarization assets.
- [x] 2.3 Report active Metal encoder/decoder initialization and route unavailable Metal/resources through retryable errors. Keep dictation and Meeting on their existing actor/routing path.

## 3. Verification and delivery

- [x] 3.1 Run focused Whisper, routing, manifest, download, and loading checks, then `make test` and `make build`. Run real-runtime Q5/Q8 integration checks for both legacy installations and weights without companions.
- [x] 3.2 Re-run the accepted 27-recording Q8 comparison with unchanged weights, prompt, language, decoder settings, and corpus snapshot. Preserve WER/CER, inference timing, load/warmup separation, sample counts, and clean process exit. Keep private data outside Git and report Q5 quality as unmeasured unless evaluated.
- [x] 3.3 Run `openspec validate use-metal-only-whisper --strict`, inspect the final diff, and review proposed ADR-0012 against measured behavior before accepting it. Report exact checks and unavailable integration prerequisites.
- [x] 3.4 Sync delta specs into main specs, verify unrelated scenarios remain unchanged, validate strictly, and leave archival to a separate user request after implementation and verification are complete.
