# Verification

## Provenance

On 2026-10-22, the official GitHub releases API reported v1.9.5 as the latest stable release. Resolving the annotated v1.9.5 tag and binary b5454 tag independently produced source commit d1be6fde11ac6e0407606b4e42fe72d34add8037. The official b5454 XCFramework asset digest and local archive both matched e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b.

The official framework C API returns `1.9.5-dev`. Diagnostics now use this actual native string. A ctypes check against the framework embedded in the built app confirmed the same version.

## Automated checks

- `make test` with `VOICEPEN_WHISPER_NATIVE_CONFIG=/tmp/voicepen-whisper-upgrade-fixtures.json`, `VOICEPEN_GIGAAM_CONFIDENCE_MODEL` pointing to the verified existing GigaAM weights, and `VOICEPEN_GIGAAM_CONFIDENCE_AUDIO` pointing to sample-013: **748 tests in 83 suites passed**, process exit 0. Final log: `/tmp/voicepen-whisper-upgrade-tests-final.log`.
- Scenario mapping: `WhisperMetalNativeTests.pinnedRuntimeUsesMetalWithBothQuantizationsAndLegacyInstallations` covers Q5/Q8 existing-weight reuse, legacy companion isolation, actual runtime identity, Metal encoder/decoder, word evidence and timestamped segments. `GigaAMConfidenceTests.packagedNativeRuntimeSuppliesWordEvidenceWithoutTimestamps` runs actual GigaAM inference in the same test process, including confidence with/without timestamp requests. Both native tests executed, rather than skipping.
- `make build`: succeeded, process exit 0. Log: `/tmp/voicepen-whisper-upgrade-build.log`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/run-gigaam-coexistence.sh <verified-gigaam-model> <installed-q8-model> <sample-013-float32-pcm> .local/asr-quality/whisper-v1.9.5-coexistence`: passed, process exit 0. Both load orders produced identical text per backend, GigaAM cancellation and reuse passed, and native resource classes remained isolated with no duplicate-class log. Evidence: `.local/asr-quality/whisper-v1.9.5-coexistence/result.json` and `run.log`.
- `xcrun swift-format lint --strict Vendor/whisper.spm/Package.swift VoicePen/Features/Transcription/WhisperCppContext.swift VoicePenTests/Transcription/WhisperMetalNativeTests.swift`: passed.
- `openspec validate update-whisper-runtime --strict` and `openspec validate --specs --strict --no-interactive`: passed. The new requirement was merged into the main spec, preserving existing requirements.
- `git diff --check`: passed.

The first build attempt found an old precompiled Whisper C module at the same generated framework path. Clearing the generated explicit C-module cache resolved the stale-header failure. Final checks use the new binary and headers.

## Limits

This verifies runtime compatibility on this Apple Silicon Mac with installed Q5/Q8 weights and the private GigaAM candidate already in the workspace. It does not establish a corpus-wide quality or speed improvement, test Intel hardware, install or release the app, publish artifacts, or create a commit. No model artifacts, defaults, preprocessing, or decoding settings were changed by this update.
