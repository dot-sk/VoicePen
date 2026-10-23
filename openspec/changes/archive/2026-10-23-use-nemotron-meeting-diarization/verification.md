# Verification

- `openspec validate use-nemotron-meeting-diarization --strict --no-interactive`: passed.
- `make test`: 749 tests in 83 suites passed before the final cache-race/deletion tests were added.
- `VOICEPEN_NEMOTRON_REGRESSION_ROOT="$PWD/.local/diarization-alternatives-20261022" make test`: 749 tests passed, including the opt-in production adapter regression. Debug execution, not a performance benchmark.
- Short meeting: 54 postprocessed turns, three speaker IDs, both repeats match all frozen turn coordinates and IDs within 0.1 ms.
- Long meeting: 470 postprocessed turns, three speaker IDs, both repeats match all frozen turn coordinates and IDs within 0.1 ms.
- Each repeat is followed by canceled inference, reset and reload. The next input/repeat still matches its own complete reference.
- Initial Core ML model load took 45.44 seconds; reloads took 0.10 to 0.15 seconds. The existing diarization warmup is asynchronous and does not use the ASR model's 30-second timeout.

The reference is an earlier whole-buffer run on exactly the same local audio and
model artifacts. This verifies integration and state isolation, including the
recording tail. It does not establish human-labeled attribution accuracy or DER.
Private inputs and raw outputs stay under `.local` and are not distributed.

- `make build CONFIGURATION=Release DERIVED_DATA="$PWD/.local/nemotron-migration-build"`: BUILD SUCCEEDED.
- Automated inspection of both resolved dependency graphs confirms FluidAudio 0.17.7. Release link inputs contain FluidAudio and VoicePenDiarization and exclude SpeakerKit, WhisperKit, ArgmaxCore and NemoTextProcessing. The optional normalizer is also absent from the app bundle.
- Live version check on 2026-10-22: GitHub's latest FluidAudio release is v0.17.7; the HF Core ML repository HEAD matches the pinned revision. The official NVIDIA model is Nemotron-3-Diarization.

- Final `make test`: 751 tests in 83 suites passed, including reset during runtime creation and deletion of interrupted staging files.
- Release bundle: 45,661,132 bytes of regular files, excluding symlinks. This is approximately 43.55 MiB and excludes downloaded models.
- `git diff --check` and strict swift-format lint on the changed runtime/installation/integration files passed.

## Immediate release after analysis

The subsequent lifecycle adjustment removes automatic diarization prewarming on
startup, enabling or completed download. Cache-owned runtime references are
released immediately after the final active warmup/analysis operation, on success,
error or cancellation. Installed-file status remains available while unloaded.

- `make test`: 755 tests in 84 suites passed. New deterministic tests cover release on all exit paths, loading again for a later request, explicit validation, cancellation at an inference boundary and overlapping operations.
- `make build CONFIGURATION=Release DERIVED_DATA="$PWD/.local/nemotron-migration-build"`: BUILD SUCCEEDED.
- `openspec validate use-nemotron-meeting-diarization --strict --no-interactive`, strict swift-format lint of the lifetime implementation/tests and `git diff --check`: passed.
- Native turn parity was not rerun for this adjustment; model math and preprocessing are unchanged. Releasing VoicePen references does not guarantee that Core ML's system caches or allocator pages immediately leave process RSS.
