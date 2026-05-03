# Testing Guidelines

VoicePen keeps the fast unit loop separate from hosted macOS app coverage.

## Commands

- `make test` validates specs and runs SwiftPM unit tests without launching
  `VoicePen.app`.
- `make integration-test` runs hosted Xcode tests against `VoicePen.app`.

Use `make test` for the default development loop. Use `make integration-test`
only when the behavior depends on the app host, AppKit lifecycle, entitlements,
or other macOS runtime wiring.

## Unit Tests

Unit tests should exercise core behavior through `VoicePenCore` and injected
fakes. They should not require `VoicePen.app` to launch.

For async behavior, prefer deterministic synchronization:

- Return spawned `Task` handles from production commands that start background
  work, and mark them `@discardableResult` when callers usually fire and forget.
- In tests, await the returned task when the assertion depends on completion.
- For blocking fakes, expose explicit async checkpoints such as
  `started.wait()` and `cancelled.wait()`.
- Use continuations, injected clocks, or injected schedulers for time-dependent
  behavior.

Avoid polling loops and `Task.sleep` in unit tests when a task handle, latch,
continuation, clock, or scheduler can model the event directly.

## Integration Tests

Integration tests belong in `VoicePenIntegrationTests` and should cover behavior
that is only meaningful with the hosted app runtime. Keep them narrow so the
default unit loop stays fast.
