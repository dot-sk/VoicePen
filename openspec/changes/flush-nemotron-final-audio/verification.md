# Verification

## Native regression

Before implementation, `make test TEST_FILTER=shortWordsAndChunkBoundaryReceiveFinalContextWithoutChangingSource` with the pinned model directory and short-audio fixture directory failed with four empty-text assertions: synthetic Two and Three both raw and extended to the exact 35,840-frame boundary.

After implementation:

```sh
VOICEPEN_NEMOTRON_ENGLISH_MODEL_DIR="$PWD/.local/nemotron-english-asr/e673531caa6d25ab7baf5a8c14c9b99ba1551838" \
VOICEPEN_NEMOTRON_SHORT_AUDIO_DIR=/private/tmp/voicepen-nemotron-short \
VOICEPEN_NEMOTRON_ENGLISH_AUDIO=/private/tmp/voicepen-nemotron-jfk.wav \
make test TEST_FILTER='NemotronNativeTests|NemotronTranscriptionTests'
```

All 12 tests in two suites passed, natural exit 0. Short fixtures were generated locally with the macOS Samantha voice saying Two and Three, then converted to 16 kHz mono WAV. Native tests need local model weights and the indicated audio fixtures; the default test run does not load weights.

Coverage verifies recovered short words at both input lengths, unchanged input bytes and original sample accounting, empty silence at 0.5/2.24/4.48 seconds, longer English speech through the public JFK sample, repeated requests and canceled-request retry. Client tests retain coverage for serialization, cancellation and inference failure recovery.

## Required checks

- `make test`: 782 tests in 87 suites passed, natural exit 0.
- `make build`: BUILD SUCCEEDED, natural exit 0.
- `openspec validate --all --strict --no-interactive`: 24 items passed.
- Strict swift-format for the native adapter and its test file, SwiftLint for the test file, and `git diff --check` passed.

## Scope and limits

The silent tail is generated inside the shared Nemotron file adapter for every request, after consuming source audio and before finalization. It does not change source files, persisted recordings, original frame accounting, other recognizers or the independent application recording-duration cutoff. Cancellation checks surround tail inference and the existing reset path handles failure/cancellation.

No manual microphone/UI check was run. The experiment supporting this change reproduced short-word omissions; it did not reproduce the user's sentence-final omission, so recovery of that symptom is not claimed as verified. Existing uncommitted language-selection work was preserved.
