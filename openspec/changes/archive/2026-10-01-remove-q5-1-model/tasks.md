## 1. Add retirement coverage

- [x] 1.1 Add a bundled-manifest test that requires Q5_0 as recommended, exposes only Q5_0 and Q8_0, and rejects Q5_1 as a selectable model.
- [x] 1.2 Add startup tests proving a saved Q5_1 or other unsupported model ID is replaced and persisted as Q5_0 before model warmup.
- [x] 1.3 Add path cleanup tests proving the exact app-managed Q5_1 directory is removed while Q5_0, Q8_0, saved recordings, and unrelated files remain unchanged.
- [x] 1.4 Add startup tests proving a Q5_1 cleanup failure is logged without blocking Q5_0 selection or startup, and a new launch attempts cleanup again.

## 2. Retire Q5_1

- [x] 2.1 Remove Q5_1 from the bundled model manifest while keeping Q5_0 recommended and Q8_0 available.
- [x] 2.2 Reconcile an unsupported saved model ID to the recommended model and persist the replacement during startup.
- [x] 2.3 Add exact-ID cleanup for the app-managed Q5_1 model directory and run it before model warmup through an injectable, non-blocking startup operation.
- [x] 2.4 Keep the immutable Q5_1 GitHub release asset, checksums, publication scripts, and third-party notices unchanged for older VoicePen versions.

## 3. Verify

- [x] 3.1 Run `openspec validate remove-q5-1-model --strict`, `make validate-specs`, and `make format-check`.
- [x] 3.2 Run `make test`.
- [x] 3.3 Run `make build`.
- [x] 3.4 Run `git diff --check` and confirm the change contains no edits to the immutable model-assets release metadata.

## Verification notes

- The repository-wide `make format-check` still reports pre-existing formatting errors in `VoicePen/App/SettingsViews.swift` and `VoicePen/Features/AudioProcessing/WhisperOptimalAudioProcessor.swift`. The Swift files changed by this change pass the same strict formatter check.
