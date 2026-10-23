# Verification

- `make test TEST_FILTER='RecognitionSelectionTests|AppSettingsStoreTests|nemotronSelectionRetains|languageSwitchFromNemotron|effectivePolicyPreservesWhisperPreferences|capabilities'`: 52 tests passed.
- `make test`: 779 tests in 87 suites passed, natural exit 0.
- `make build`: BUILD SUCCEEDED, exit 0. Covers Settings and native tray app-target wiring.
- `openspec validate --all --strict --no-interactive`: all 23 items passed.
- Strict swift-format and SwiftLint checks passed for every changed and new Swift file.
- `git diff --check` passed.

Coverage maps routing scenarios to RecognitionSelectionTests, Russian restoration and active dictation rejection to AppControllerTests, and round-trip/malformed/missing-map/transaction rollback to AppSettingsStoreTests. Existing backend capability tests verify native decoding remains constrained.

Not verified manually in the running app. No model weights, native decoder implementation or download behavior changed. Older releases have no language-to-model history; the first unsupported-language switch uses the compatible installed fallback.

## Last-used priority correction

Language selection restores its remembered compatible model before considering the current model, including English when the current multilingual model also supports it. Missing model files do not erase that preference. Symmetric Russian/English round-trip and missing-files coverage were added before verification.

- `make test`: 780 tests in 87 suites passed, natural exit 0.
- Strict swift-format, SwiftLint and `git diff --check` passed for the correction.
- `openspec validate --all --strict --no-interactive`: 23 items passed.
