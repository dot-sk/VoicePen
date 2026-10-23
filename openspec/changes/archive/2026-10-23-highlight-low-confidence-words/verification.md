## Verification

- `openspec validate highlight-low-confidence-words --strict --no-interactive`: passed
- `make test`: 740 tests in 82 suites passed; log `/tmp/voicepen-confidence-tests.log`
- `make build`: final app build succeeded; log `/tmp/voicepen-confidence-app-build-final.log`
- `xcrun swift-format lint --configuration .swift-format --strict` on changed and new Swift files: passed
- `git diff --check`: passed

The existing Q8 configuration was used unchanged to inspect confidence extraction on 32 confirmed working recordings. All recognized texts matched the prior baseline. Policy details, false positives, and missed errors are in confidence-review.md. This is feature verification rather than a new ASR candidate or independent corpus evaluation.

The actual TranscriptTextEditor and STTextView dependencies were compiled into an isolated native QA host without loading the user's database. Light and dark snapshots were inspected. The host checked native tooltip availability, complete Unicode word emphasis, selection preservation on theme/confidence changes, removal of stale attributes, selected plain text copy, full-copy routing, selection reset on text replacement, and scrolling 200 lines. Final native host exited successfully. Private screenshots and QA files are under `.local/asr-quality/confidence-review-20261022/`; log `/tmp/voicepen-confidence-ui-run.log`.

The first selected-copy QA assertion incorrectly expected macOS to expose only one pasteboard type. macOS exposes both public.utf8-plain-text and its legacy NSStringPboardType alias for the same plain text. That assertion stopped the initial host before it restored the original clipboard contents; those contents were lost. The corrected host saves a durable snapshot, restores the clipboard before assertions, and validates plain text and routing successfully. No rich text annotation was copied.

An existing meeting/dictation overlap test repeatedly failed under load because it depended on a 500 ms delay. It now uses the already-existing two-call blocking fake with explicit checkpoints and retains the same behavior assertions. The legacy hotkey migration fixture was also updated to include the existing history schema before applying the new nullable metadata column.

The existing Sessions editor is retained. No confidence screen, separate text block, counter, button, punctuation processing, extra model, or second inference pass was added. The initial implementation supplied Whisper confidence only; the authorized native GigaAM extension below supersedes that initial limitation. Old sessions and missing evidence still render without synthetic hints. No user database migration, installation, commit, or release was performed.

## Native GigaAM extension verification

- Clean pinned-archive preparation with the maintained third patch: passed
- Framework and native tests/tools builds with CMake 4.4.4 and two build jobs: passed
- `ctest --test-dir .local/asr-quality/gigaam-confidence/build-tests-v3 --output-on-failure --parallel 1`: 53/53 passed, including the new CTC test with Release assertions enabled
- `uv --native-tls run --offline --no-project --python 3.13 --with numpy==2.5.4 --with gguf==0.19.0 --with safetensors==0.8.0 --with jiwer==4.0.0 -m unittest discover -s Vendor/transcribe-native/tests -v`: 21/21 passed
- New candidate package content/interface/resource/license verification and `prepare-gigaam-runtime.sh ... --allow-unaccepted-candidate`: passed; candidate.3 retains the exact existing F16 model digest
- Controlled previous/candidate/previous native comparison: 42 recordings, 126 measured calls per run, 378 total; every paired text, token and frame position identical; all candidate probabilities finite and bounded
- Replaying all 126 candidate outputs through production Swift confidence mapping: passed; backend policy and example review in confidence-review.md
- `make test` with `VOICEPEN_GIGAAM_CONFIDENCE_MODEL` and `VOICEPEN_GIGAAM_CONFIDENCE_AUDIO` set to the pinned private model and sample-013: 748 tests in 83 suites passed, including actual packaged runtime inference with and without timestamp requests; log `/tmp/voicepen-giga-confidence-swift-tests.log`
- `make build`: passed; log `/tmp/voicepen-giga-confidence-app-build.log`
- C API call against the framework inside the built VoicePen.app: version 0.4.0 and exact runtime commit `1dc22fac+voicepen-gigaam-600m-candidate.3` confirmed
- Strict OpenSpec validation, changed/new Swift strict formatting, and `git diff --check`: passed

The first package validation attempt falsely classified the absolute path printed as the first line of `otool -L` as a dependency. The packager now checks the actual dependency rows while retaining private-dylib and user-checkout rejection. Failed attempt and subsequent verified package remain separate private directories.

Previously installed candidate.2 weights are reused only for the explicit candidate.3 transition with matching model identity, version, size and digest; actual model loading still checks the full artifact. Tests cover both reuse without rewriting the marker and rejection of incompatible identities/runtime/file size. No user installation marker or settings were changed by this work.

The package remains a locally verified candidate with `acceptance=unaccepted`. Existing distribution and broader predecessor acceptance gates are not claimed complete. No model assets were republished, no weights were changed, and no application installation, commit or release was performed. Private evidence is under `.local/asr-quality/gigaam-confidence/`.
