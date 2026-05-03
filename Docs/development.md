# Development Tooling

VoicePen keeps the default development loop small, with heavier checks split
into explicit commands.

## Commands

- `make format` formats Swift source with `swift-format`.
- `make format-check` strictly checks Swift formatting without changing files.
- `make lint` runs SwiftLint.
- `make lint-fix` runs `swift-format` and SwiftLint auto-fix.
- `make dead-code` runs Periphery unused-code analysis.
- `make install-hooks` enables repository Git hooks.
- `make check` runs linting and the unit test loop.
- `make test` validates specs and runs SwiftPM unit tests.

`make test` stays focused on fast unit feedback. `swift-format` is intentionally
available as an explicit formatting command instead of being enforced in CI
until the existing source tree gets one mechanical formatting pass. Periphery is
also separate because it builds the Xcode project and performs index-based
analysis.

## Pre-Commit Hook

Run this once per checkout:

```bash
make install-hooks
```

The pre-commit hook formats staged Swift files with `swift-format`, runs
SwiftLint auto-fix, stages the formatting changes, and then runs SwiftLint on
those staged Swift files.

## Tools

- `swift-format` is resolved from the active Xcode toolchain with `xcrun`.
- `swiftlint` can be installed with `brew install swiftlint`.
- `periphery` can be installed with
  `brew install peripheryapp/periphery/periphery`.
- `xcbeautify` is optional for local `xcodebuild` output:
  `brew install xcbeautify`.

CI runs SwiftLint, unit tests, and unused-code analysis as separate jobs on pull
requests, manual runs, and every push.
