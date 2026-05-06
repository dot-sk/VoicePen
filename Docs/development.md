# Development Tooling

VoicePen keeps the default development loop small, with heavier checks split
into explicit commands.

## Commands

- `make format` formats Swift source with `swift-format`.
- `make format-check` strictly checks Swift formatting without changing files.
- `make lint` checks `swift-format` formatting and runs SwiftLint.
- `make lint-fix` runs `swift-format` and SwiftLint auto-fix.
- `make dead-code` runs Periphery unused-code analysis.
- `make install-hooks` installs repository Git hooks through Lefthook.
- `make check` runs linting and the unit test loop.
- `make test` validates specs and runs SwiftPM unit tests.

`make test` stays focused on fast unit feedback. Formatting and linting live in
`make lint`, while `make lint-fix` applies the available mechanical fixes.
Periphery is separate because it builds the Xcode project and performs
index-based analysis.

## Git Hooks

Run this once per checkout:

```bash
make install-hooks
```

Lefthook reads `lefthook.yml` and installs generated hook wrappers into the
ignored local `.githooks/` directory. The pre-commit hook formats staged Swift
files with `swift-format`, runs SwiftLint auto-fix, stages the formatting
changes, and then runs SwiftLint on those staged Swift files.

The pre-push hook runs `make test` only when the pushed commits contain
code-impacting changes. Documentation-only pushes skip the local unit-test loop.

## Tools

- `swift-format` is resolved from the active Xcode toolchain with `xcrun`.
- `lefthook` can be installed with `brew install lefthook`.
- `swiftlint` can be installed with `brew install swiftlint`.
- `periphery` can be installed with
  `brew install peripheryapp/periphery/periphery`.
- `xcbeautify` is optional for local `xcodebuild` output:
  `brew install xcbeautify`.

CI runs SwiftLint and unit tests for code-impacting pull requests and pushes,
restoring the SwiftPM build cache before the macOS job so expensive package
builds can be reused. Documentation-only pull requests skip those code checks.
Unused-code analysis stays available through `make dead-code` and the optional
manual CI input `run_dead_code`.
