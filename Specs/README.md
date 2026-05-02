# VoicePen Specs

Specs are the source of truth for intended VoicePen behavior. AI-assisted changes must start from a spec and end with the spec, tests, and implementation agreeing.

## Creating A Spec

1. Copy `templates/feature-spec.md` for new behavior or `templates/bug-spec.md` for fixes.
2. Name the file `YYYY-MM-DD-short-name.md`.
3. Add it to `index.md`.
4. Fill every required section before implementation begins.
5. Keep `Acceptance Criteria` and `Test Mapping` specific enough to verify.

## Required Sections

Every spec must include:

- `Metadata`
- `Problem`
- `Behavior`
- `Acceptance Criteria`
- `Examples`
- `Test Mapping`
- `Notes`
- `Open Questions`

Every spec must also start with YAML frontmatter:

```yaml
---
id: SPEC-000
status: draft
updated: YYYY-MM-DD
tests: []
---
```

Allowed `status` values are `draft`, `active`, `implemented`, and `superseded`. Use `tests` for automated test files that verify the spec. Keep manual checks in the `Test Mapping` section.

Specs should describe behavior. Put durable architecture rationale and tradeoffs in ADRs under `Docs/adr/`.

## Authoring Checklist

Before marking a spec `active`, check these points:

- Review neighboring specs. If the feature changes an existing behavior, update the existing spec in the same change.
- Define vague terms in observable language. Avoid leaving words like "recent", "successful", "eligible", "valid", "empty", "changed", or "same flow" without exact criteria.
- For limits, thresholds, caps, and retention counts, specify the default, allowed values, and where the chosen value applies.
- For shared behavior, name the shared path. File, clipboard, UI, and automation flows should not grow separate parsing, validation, or mutation rules unless the spec explicitly requires that difference.
- Cover negative and partial cases for imports, exports, prompts, and generated data: empty input, malformed input, prose instead of data, partially valid data, duplicates, zero-impact valid input, and cancellation.
- For previews before mutation, specify that the preview simulates the exact state that will exist after confirmation, including merge, deduplication, overwrite, and filtering rules.
- For persisted data changes, describe new data, old data behavior, migration or fallback behavior, and how missing values appear in UI or export.
- For clipboard, file, prompt, diagnostics, or debug-bundle export, require an explicit user action and make clear what user data is included before it leaves VoicePen.
- For external-tool output contracts, specify the exact format, escaping rules, whether prose is allowed, and what VoicePen does when the output violates the contract.
- Map tests to behavior decisions, not just files. Include default values, selected values, old data, invalid input, partial input, zero-impact cases, and cancellation when those cases exist.

## Validation

Run:

```bash
scripts/validate-specs.sh
```

`make test-strict` runs this validation before the unit test suite.
