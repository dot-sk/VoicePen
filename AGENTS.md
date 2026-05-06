# VoicePen AI Workflow

This repository uses a strict spec-driven workflow for AI-assisted changes.

## Start Or Resume

After any `CompactContext`, resume, or handoff, re-read `AGENTS.md` and
`Specs/index.md` before changing or reviewing behavior. Treat this file as the
repository contract, not the compacted summary.

## Behavior Changes

Before changing behavior:

1. Find the relevant spec in `Specs/index.md`; if none exists, create one from `Specs/templates/feature-spec.md` or `Specs/templates/bug-spec.md`.
2. Capture intended behavior as acceptance criteria before editing production code.
3. Map each acceptance criterion to an automated test or explicit manual verification.
4. Implement the smallest change that satisfies the spec.
5. Update the spec in the same change when behavior, edge cases, or tests change.
6. Run `make test` before handoff when local tooling is available.

Write an ADR in `Docs/adr/` only for technical decisions that are expensive to
reverse: architecture, persistence shape, model/backend strategy,
privacy/security posture, distribution, or dependencies.

## Feature Architecture

Keep `AppController` as a thin app-facing facade for SwiftUI, menu commands,
published app state, and cross-feature wiring. Do not add substantial feature
lifecycle logic, long-running task ownership, timeout orchestration, permission
flows, or domain-specific state machines directly to `AppController`.

For new features or refactors with meaningful state transitions, prefer a local
feature store in the app layer:

- Use a small `@MainActor` feature store when the feature owns UI-facing state,
  async effects, cancellation, timeout handling, or multi-step user actions.
- Keep the store local to one feature. Do not introduce a global Redux-style app
  store or a third-party architecture dependency unless the user asks for it and
  the decision is captured in an ADR.
- Model the feature with explicit `State`, `Action`, and `Environment` types
  when that reduces lifecycle ambiguity. Keep reducers/transitions synchronous
  and put side effects in store methods or effect helpers.
- Inject dependencies through the feature environment: pipelines, stores,
  clients, settings, permissions, prompts, clocks/timeouts, and app-facade
  callbacks.
- Let `AppController` expose stable facade methods used by SwiftUI and tests,
  then delegate feature-specific work to the feature store.
- Keep general app commands in `AppController` when they intentionally share
  cross-feature behavior, such as clipboard, insertion, model selection,
  global app state, or shared settings persistence.

For simpler features, a dedicated view model, service, pipeline, or persistence
store is enough. Do not add a feature store just to follow a pattern.

## Settings Screens

Settings screens should use one shared app/settings controller path for reading
and writing persistent settings. Controls should bind to the current published
settings state and write changes back through the controller immediately, using
the same persistence path as related settings screens.

Do not introduce per-screen draft models, local reload/apply flows, or bespoke
file-writing helpers for ordinary settings. Use local `@State` only for
ephemeral UI state such as transient errors, confirmation dialogs, search text,
or selection.

## Branch And Commit Conventions

Use short, descriptive branch names in lowercase `kebab-case`. Prefer a common
work-type prefix when it makes the change clearer, such as `feature/`, `fix/`,
`chore/`, `docs/`, `refactor/`, or `test/`; if slash-separated branch names are
not practical in the local checkout, use the same type as a kebab-case prefix.

Write commit messages using Conventional Commits: `type(scope): summary` or
`type: summary`. Use common types such as `feat`, `fix`, `docs`, `test`,
`refactor`, `chore`, or `ci`, and keep the summary concise and imperative.

## Guardrails

- Do not treat code as the only source of truth for product behavior. Specs describe intended behavior; tests and code implement it.
- Do not add hidden product behavior without updating a spec.
- Do not leave `Open Questions` unresolved when the answer changes implementation behavior.
- Do not rewrite unrelated files or revert uncommitted user changes.
- Keep specs concise and testable. Prefer observable behavior and examples over implementation narration.
- Keep specs resilient to refactoring. Capture stable product behavior and meaningful constraints, not incidental constants, exact copy, or implementation details unless those exact values are themselves the requirement.
- Keep rationale in ADRs, not specs, when the "why" is a durable technical decision.

## Spec Status

- `draft`: intent is still being shaped; implementation should not begin unless the user explicitly asks for a spike.
- `active`: ready for implementation and test mapping.
- `implemented`: behavior is present in code and tests/manual checks are mapped.
- `superseded`: retained for history; link to the replacing spec.

## Test Expectations

Use Swift Testing unit tests for business logic: core behavior, persistence,
model routing, dictionary logic, grouping/filtering decisions, and pipeline
decisions. Do not unit-test SwiftUI view structure or incidental layout. Extract
business decisions from views into small testable types when practical. Use UI
tests only when behavior depends on the macOS UI surface, and keep view-level
tests to stable product contracts rather than exact source structure. When
automated coverage is not practical, add a manual verification item in `Test
Mapping` with enough detail for another engineer to repeat it.

Follow `Docs/testing.md` for local test layering and async test style. Prefer
task handles, explicit async checkpoints, continuations, clocks, or schedulers
over polling sleeps in unit tests.

Do not add tests that verify copywriting, marketing text, explanatory prose, or
exact wording of settings/help text. For labels, disclosures, prompts,
diagnostics, or other user-facing text, test the behavior contract: that text is
passed, surfaced, or includes a required semantic signal. Avoid asserting full
prose unless exact wording is itself the product requirement.

Prefer positive assertions over negative substring checks. For prompts and other
generated text, assert the required structure and signals that must be present;
avoid maintaining lists of incidental strings that must not appear unless their
absence is the actual safety or privacy requirement.

## Local Test Runner

`make test` commonly needs to write into Xcode and SwiftPM cache
locations under the user's home directory (`~/Library/Caches`, `~/.cache`, and
CoreSimulator logs). The workspace sandbox blocks those writes before tests
execute, so request escalated execution for `make test` immediately
instead of trying a sandboxed run first.
