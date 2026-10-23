## Automated verification

- `make test`: 770 tests in 86 suites passed on the final implementation. The real-model test is opt-in and disabled in the default run.
- `make build`: BUILD SUCCEEDED on the final implementation.
- `VOICEPEN_NEMOTRON_ENGLISH_MODEL_DIR="$PWD/.local/nemotron-english-asr/e673531caa6d25ab7baf5a8c14c9b99ba1551838" VOICEPEN_NEMOTRON_ENGLISH_AUDIO=/private/tmp/voicepen-nemotron-jfk.wav make test TEST_FILTER='Nemotron|RoutingTranscriptionClientTests|RoutingModelDownloadClientTests|ModelManifestTests|nemotronSelectionRetainsPreferencesAndMissingSelectionAcrossStartup'`: 32 tests passed, including actual native English recognition, complete file sample-count verification, repeatability and cancellation before execution followed by recognition. Late non-cooperative cancellation and queued request isolation have separate deterministic fake-runtime coverage.
- All 18 required upstream files were downloaded at immutable revision `e673531caa6d25ab7baf5a8c14c9b99ba1551838` and their sizes and SHA-256 digests verified. The bundled manifest records the verified descriptors; weights remain in ignored local test storage.
- `openspec validate --all --strict --no-interactive`: 22 items passed before final documentation updates.
- Strict swift-format and SwiftLint passed for changed Swift files with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. SwiftLint without that environment could not locate SourceKit and was rerun successfully with the configured Xcode.
- `git diff --check`: passed.

## Not verified

Live microphone dictation, manual settings UI review and comparative recognition quality on personal English recordings were not exercised. The model was not installed into the running user's app or selected automatically. The new app build offers its existing confirmed download flow for the optional model.
