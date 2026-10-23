## Automated verification

- Before the scheduling fix, all three new hosted tests failed and reproduced the stale status snapshot.
- After the fix, `make integration-test` passed: 8 tests, 2 skipped native-model fixture tests, no failures. All three status subscription regressions passed.
- `make build` passed.
- `make test` passed on retry: 755 tests in 84 suites. The first full unit run stalled and its test helper was terminated before retrying separately from Xcode builds.
- `openspec validate --all --strict --no-interactive` passed: 26 items.
- Focused `xcrun swift-format lint --configuration .swift-format --strict VoicePen/VoicePenApp.swift VoicePenIntegrationTests/VoicePenStatusItemControllerTests.swift` and `git diff --check` passed.

## Manual verification

Sergey reported that he checked the fix and the behavior appeared correct.

## Not verified by the agent

Live microphone dictation, cancellation, and visual inspection of the installed app were not exercised manually. Hosted tests cover the common state subscription without starting capture or opening the tray menu; existing unit tests cover dictation cleanup and status selection.
