## 1. Native runtime and installation

- [x] 1.1 Add the pinned FluidAudio wrapper with optional normalization disabled, local-only loading, request-local offline streaming state and cancellation/reset handling (local inference and cancellation scenarios).
- [x] 1.2 Replace SpeakerKit metadata and archive installation with verified immutable Nemotron files and transactional installation. Add automated success, missing/legacy installation, corruption, rollback, cancellation and retry tests.
- [x] 1.3 Route fresh and legacy settings to Nemotron, preserve meeting/history contracts and update automated settings and pipeline coverage.

## 2. Dependency and integration migration

- [x] 2.1 Replace SpeakerKit/Argmax in SwiftPM and Xcode with the local runtime product and resolve both dependency graphs (distribution scenario).
- [x] 2.2 Add opt-in native regression coverage for both frozen meeting inputs, repeated inference and cancellation/retry; retain existing transcript postprocessing and failure coverage.
- [x] 2.3 Record the superseding ADR and runtime/model provenance, then synchronize the main meeting spec.

## 3. Verification

- [x] 3.1 Run strict OpenSpec validation and make test.
- [x] 3.2 Build the Release application and inspect its dependency graph for removed products and optional normalization.
- [x] 3.3 Run the production native adapter against both frozen recordings and compare complete turns/tail with frozen results; report quality limits separately.

## 4. On-demand runtime lifetime

- [x] 4.1 Cover success, error, cancellation, retry and overlapping operations with deterministic cache lifetime tests; update app tests for on-demand loading on startup/enable/download.
- [x] 4.2 Release the cache after the last operation and remove automatic diarization prewarming; keep installed status accurate.
- [x] 4.3 Sync lifecycle specifications and ADR, run make test and a Release build.
