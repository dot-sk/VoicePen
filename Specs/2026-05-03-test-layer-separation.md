---
id: SPEC-007
status: implemented
updated: 2026-05-05
tests:
  - VoicePenTests/App/AppControllerTests.swift
  - VoicePenIntegrationTests/VoicePenIntegrationHostTests.swift
---

# Test Layer Separation

## Problem

VoicePen unit tests were run as hosted macOS app tests, so even pure logic tests
started `VoicePen.app`. This made the default test loop slower and blurred the
boundary between unit tests and app-host integration coverage.

## Behavior

VoicePen shall keep fast unit tests separate from tests that require the macOS
application host. The default test command shall validate specs and run unit
tests without launching `VoicePen.app`. Hosted app integration tests shall be
available through an explicit command.

## Acceptance Criteria

- When a developer runs the default test command, VoicePen shall validate specs
  and execute tests in a non-hosted unit-test runner.
- When the default test command runs from an environment with an inherited
  `SDKROOT`, VoicePen shall still use the macOS SDK from the configured Xcode
  developer directory.
- When a pull request or main-branch push changes only documentation, specs, or
  repository instructions, VoicePen CI shall skip code-quality checks, unit
  tests, and dead-code analysis.
- When a pull request or main-branch push changes specs, VoicePen CI shall run
  the dedicated spec-validation job even if the same change also affects code.
- When a pull request or main-branch push changes code-impacting files, VoicePen
  CI shall run code-quality checks, unit tests, and dead-code analysis.
- When a release-branch pull request changes code-impacting files, VoicePen CI
  shall keep code-quality checks and unit tests but skip dead-code analysis.
- When a developer installs Git hooks, VoicePen shall use Lefthook as the hook
  runner while keeping `make` commands as the source of truth.
- When a developer pushes commits with no code-impacting changes, the local
  pre-push hook shall skip `make test`.
- When a developer pushes commits with code-impacting changes, the local
  pre-push hook shall run `make test`.
- When a developer needs app-host coverage, VoicePen shall provide a separate
  hosted integration-test command.
- Unit tests shall import the core VoicePen module directly rather than loading
  through the app target.
- Hosted integration tests shall remain able to launch `VoicePen.app` for
  behavior that depends on the macOS app runtime.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default local check | `make test` | Specs validate and SwiftPM unit tests run without `VoicePen.app` opening |
| Inherited SDKROOT | `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk make test` | Tests still run with the macOS SDK selected from `DEVELOPER_DIR` |
| Docs-only PR | Change only `README.md`, `Docs/`, `Specs/`, or `AGENTS.md` | CI skips code-quality checks, unit tests, and dead-code analysis |
| Spec and code PR | Change both `Specs/` and code-impacting files | CI runs the dedicated spec-validation job and the code-quality jobs |
| Code PR | Change `VoicePen/`, `VoicePenTests/`, package files, scripts, or CI workflow | CI runs code-quality checks, unit tests, and dead-code analysis |
| Release PR | Open `release/v1.1.0` into `main` after normal feature PRs are green | CI runs code-quality checks and unit tests without the Dead Code job |
| Hook install | `make install-hooks` | Lefthook installs the configured Git hooks |
| Docs-only push | Push commits that only touch docs or specs | Pre-push skips `make test` |
| Code push | Push commits that touch Swift, package, project, script, or CI files | Pre-push runs `make test` |
| App-host check | `make integration-test` | Xcode runs hosted integration tests against `VoicePen.app` |

## Test Mapping

- Automated: `make test` verifies spec validation and the non-hosted unit test
  target.
- Automated: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk make
  test` verifies the default test command does not inherit an incompatible SDK
  from Git hook environments.
- Automated: `make integration-test` verifies the hosted app integration target.
- Automated: `.github/workflows/ci.yml` gates code-quality checks, unit tests,
  and dead-code analysis on code-impacting changed paths, skips dead-code
  analysis for `release/v*` pull requests, and runs the dedicated
  spec-validation job for spec changes.
- Automated: `scripts/code-impacting-changes.sh` is shared by CI and local
  hooks to classify changed paths.
- Manual: run `make install-hooks` in a checkout with Lefthook installed and
  verify `lefthook.yml` installs pre-commit and pre-push hooks.
- Manual: observe that `make test` does not open the VoicePen app window, while
  `make integration-test` may launch the app host by design.

## Notes

`VoicePenCore` is the unit-testable module for app logic. The app target remains
responsible for SwiftUI/AppKit composition and production wiring.

Async unit tests should synchronize on explicit task handles, continuations,
clocks, schedulers, or fake-client checkpoints rather than elapsed-time polling.
See `Docs/testing.md` for the project testing conventions.

## Open Questions

- None.
