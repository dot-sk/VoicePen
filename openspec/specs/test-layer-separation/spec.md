# Test Layer Separation Specification

## Purpose

VoicePen unit tests were run as hosted macOS app tests, so even pure logic tests
started `VoicePen.app`. This made the default test loop slower and blurred the
boundary between unit tests and app-host integration coverage.

## Requirements

### Requirement: Test Layer Separation

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen shall keep fast unit tests separate from tests that require the macOS
application host. The default test command shall validate specs and run unit
tests without launching `VoicePen.app`. Hosted app integration tests shall be
available through an explicit command.

#### Scenario: Developer runs the default test command

- **WHEN** a developer runs the default test command
- **THEN** VoicePen shall validate specs and execute tests in a non-hosted unit-test runner.

#### Scenario: Default test command runs from an environment with an inherited SDKROOT

- **WHEN** the default test command runs from an environment with an inherited `SDKROOT`
- **THEN** VoicePen shall still use the macOS SDK from the configured Xcode developer directory.

#### Scenario: Pull request or main-branch push changes only documentation, specs, or repository instructions

- **WHEN** a pull request or main-branch push changes only documentation, specs, or repository instructions
- **THEN** VoicePen CI shall skip code-quality checks, unit tests, and dead-code analysis.

#### Scenario: Pull request or main-branch push changes specs

- **WHEN** a pull request or main-branch push changes specs
- **THEN** VoicePen CI shall run the dedicated spec-validation job even if the same change also affects code.

#### Scenario: Pull request or main-branch push changes code-impacting files

- **WHEN** a pull request or main-branch push changes code-impacting files
- **THEN** VoicePen CI shall run code-quality checks and unit tests.

#### Scenario: CI runs macOS code-quality checks and unit tests

- **WHEN** VoicePen CI runs macOS code-quality checks and unit tests
- **THEN** it shall restore and save SwiftPM package and build caches keyed by Swift package manifests so expensive dependencies can be reused between runs.

#### Scenario: Dead-code analysis is needed in CI

- **WHEN** dead-code analysis is needed in CI
- **THEN** VoicePen shall provide it as an optional manually dispatched job rather than part of the default pull-request or main-branch push checks.

#### Scenario: Developer installs Git hooks

- **WHEN** a developer installs Git hooks
- **THEN** VoicePen shall use Lefthook as the hook runner while keeping `make` commands as the source of truth.

#### Scenario: Developer pushes commits with no code-impacting changes

- **WHEN** a developer pushes commits with no code-impacting changes
- **THEN** the local pre-push hook shall skip `make test`.

#### Scenario: Developer pushes commits with code-impacting changes

- **WHEN** a developer pushes commits with code-impacting changes
- **THEN** the local pre-push hook shall run `make test`.

#### Scenario: Developer needs app-host coverage

- **WHEN** a developer needs app-host coverage
- **THEN** VoicePen shall provide a separate hosted integration-test command.

#### Scenario: Unit tests

- **WHEN** this capability applies
- **THEN** Unit tests shall import the core VoicePen module directly rather than loading through the app target.

#### Scenario: Hosted integration tests

- **WHEN** this capability applies
- **THEN** Hosted integration tests shall remain able to launch `VoicePen.app` for behavior that depends on the macOS app runtime.

#### Scenario: Unit tests 2

- **WHEN** this capability applies
- **THEN** Unit tests shall not validate production Swift/App behavior via source-string assertions (`sourceFile`, `sourceSlice`, regex, substring checks) against `VoicePen/**/*.swift`. Shared presentation/format logic must be moved to testable core types and covered with direct unit tests.

#### Scenario: Production Swift implementation contracts for status menu behavior are covered through direct model tests

- **WHEN** this capability applies
- **THEN** Production Swift implementation contracts for status menu behavior are covered through direct model tests of `VoicePenStatusMenuModel` (visibility, command ordering, language options, icon state, tint flag).

#### Scenario: Production Swift formatting for meeting duration is covered through direct unit tests of MeetingDurationFormatter

- **WHEN** this capability applies
- **THEN** Production Swift formatting for meeting duration is covered through direct unit tests of `MeetingDurationFormatter`.
