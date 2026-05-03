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

Use Swift Testing unit tests for core behavior, persistence, model routing, dictionary logic, and pipeline decisions. Use UI tests only when behavior depends on the macOS UI surface. When automated coverage is not practical, add a manual verification item in `Test Mapping` with enough detail for another engineer to repeat it.

Follow `Docs/testing.md` for local test layering and async test style. Prefer
task handles, explicit async checkpoints, continuations, clocks, or schedulers
over polling sleeps in unit tests.

Do not add copywriting snapshot tests. For labels, disclosures, prompts,
diagnostics, or other user-facing text, test the behavior contract: that text is
passed, surfaced, or includes a required signal. Avoid asserting full prose
unless exact wording is itself the product requirement.

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
