## 1. Contract and automated coverage

- [x] 1.1 Define draft preparation, human confirmation, immutable export, and local review requirements.
- [x] 1.2 Add automated tests mapping original scenarios: read-only import/refuse overwrite; persistence/no-speech/stale-save validation; confirmed-only immutable export/empty and changed-audio rejection; restricted HTTP resources/origin/range playback.
- [x] 1.3 Cover minimum actual-audio duration, longest-first selection, and no short-example backfill.

## 2. Local workflow

- [x] 2.1 Implement corpus preparation, reference storage, and fingerprinted export with standard-library tooling.
- [x] 2.2 Implement loopback review UI and make commands; exclude personal corpus data from Git.
- [x] 2.3 Document annotation rules and the distinction between processed audio, drafts, and confirmed gold.

## 3. Verification and first corpus

- [x] 3.1 Run strict OpenSpec validation, focused tooling tests, and attempt make test. Tooling tests pass; default Swift run is blocked by the Xcode license, and the active Command Line Tools fallback lacks PreviewsMacros in KeyboardShortcuts. App build is unnecessary because app-target wiring does not change.
- [x] 3.2 Prepare the selected 27 private real-audio drafts of at least 20 seconds, verify audio fingerprints, and review the UI in agent-browser using a disposable fixture for edit/confirmation checks.
- [x] 3.3 Start the real local review page, report the actual confirmation count, and leave manual reference validation to Sergey. Served at http://127.0.0.1:8765 with 0/27 confirmed at delivery; real audio metadata loads without decoder errors.
