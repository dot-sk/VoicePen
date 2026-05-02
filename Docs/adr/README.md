# Architecture Decision Records

ADRs capture important decisions and the tradeoffs behind them. Specs describe how VoicePen should behave; ADRs explain why a significant technical direction was chosen.

Write an ADR when a change affects architecture, data shape, storage, model/backend strategy, privacy/security posture, distribution, or a dependency that would be expensive to reverse.

Do not write an ADR for routine bug fixes, small UI changes, or implementation details already obvious from a spec and tests.

## Format

Copy `template.md`, assign the next number, and keep the record short.

```text
Docs/adr/0001-use-sqlite-for-local-state.md
```

Statuses: `proposed`, `accepted`, `superseded`.
