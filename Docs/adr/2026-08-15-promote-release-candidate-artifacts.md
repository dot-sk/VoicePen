---
id: ADR-0011
status: accepted
date: 2026-08-15
---

# Promote Verified Release-Candidate Artifacts

## Context

VoicePen release pull requests and tagged releases compile the same commit in
separate GitHub Actions runs. The tagged workflow also reruns the unit-test suite
after the release pull request is already required to have green checks. For
v1.10.0 these sequential duplicate builds dominated the release time, while the
actual signing and publication steps took less than one minute.

GitHub Actions caches are scoped by branch or tag and do not provide a reliable
way to reuse compiled release output across different release tags. A release
artifact can instead be transferred explicitly between workflow runs and bound
to the source commit that produced it.

## Decision

Build an unsigned production release candidate from the exact release pull-request
head commit in parallel with quality and unit tests. Store the candidate as a
short-lived immutable workflow artifact whose name includes that commit SHA.

When a release tag is pushed, require an open release pull request and a
successful CI run for the exact tagged commit. Download and validate that run's
candidate, verify its application version and build number, then sign, verify,
archive, and publish it. Production signing and Sparkle keys remain available
only to the tagged workflow.

If the successful CI run exists but its candidate artifact is unavailable, the
tagged workflow may rebuild from the same commit before signing. It must fail
before publication when the exact tagged commit has no successful release CI.

## Consequences

The normal tagged workflow no longer recompiles the app or reruns tests, reducing
tag-to-release latency while keeping the same tested source identity. Candidate
builds add one parallel macOS job to release pull requests and consume temporary
artifact storage.

The workflow must maintain an explicit commit-to-artifact contract. Changes to
candidate naming, checkout behavior, retention, or release lookup must update
the workflow-contract tests together.

## Links

- `Specs/2026-05-02-github-release-auto-updates.md`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `scripts/promote-release-candidate.sh`
