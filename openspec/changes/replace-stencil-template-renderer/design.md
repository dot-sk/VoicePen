## Context

See proposal.md. CommandTemplateRenderer currently creates a Stencil Environment per render. Its exposed context is three strings; eight custom filters delegate to existing string operations and CaseFormatter. The processor already catches render failures and returns normalized text plus diagnostics. TOML config reloads for each dictation.

## Goals / Non-Goals

Replace the rendering dependency with a small deterministic parser. Preserve documented variable/filter semantics, command matching priority, aliases, valid-template insertion policy and the error fallback. Do not implement a general template engine, change TOML format, rewrite user files, or add UI/config toggles and a second production renderer.

## Decisions

### Parse a small grammar completely before rendering

Grammar: a template is a sequence of literal strings and `{{ variable (| filter)* }}` substitutions. Names are case-sensitive identifiers from fixed allowlists; whitespace around names/separators is ignored. Filters have no arguments. Preserve all text outside substitutions. Recognize `{% ... %}` and `{# ... #}` as unsupported constructs, reject unmatched/nested delimiters and stray closing substitution delimiters. No implicit default value for unknown names and no pass-through of unknown syntax. Values are rendered once and are never reparsed. Use a linear scanner and typed local parse errors, not repeated regular-expression replacement.

Reuse CaseFormatter and existing transforms to avoid changing outputs. Missing speech arguments are an available empty string, distinct from an unknown variable. Validate the entire source before producing output so a late syntax error cannot create a partial shell command.

### Keep migration problems local to commands

Validate command templates during config loading and attach command-scoped diagnostics to the existing config-diagnostic flow. Retain invalid commands for trigger matching so a more general valid trigger cannot execute instead. The renderer remains the authoritative validation path at execution, including injected/test configs. The existing processor catches the error, keeps normalized dictation, and never emits pasteAndSubmit for that failed command. No global fallback to bundled config because one template is unsupported.

Full Stencil compatibility is intentionally not promised. Audit bundled templates, repository fixtures and available local user templates read-only before dependency removal; do not log private template values. Compare supported templates byte-for-byte against the pinned old engine in a temporary differential harness. Unsupported templates receive actionable command-scoped diagnostics; migration is documented with supported examples and there is no automatic file rewriting. Keep no Stencil runtime fallback after the switch.

A standard-library-only renderer is preferred over another templating dependency because the language is small and bounded. Supporting loops, includes or arbitrary expressions would recreate the dependency being removed.

## Risks / Trade-offs

- Existing users may use full Stencil syntax: make this scope reduction explicit in migration documentation and detect affected commands on reload.
- A bad template could execute a different or partial command: validate fully, preserve trigger selection and test the normal-dictation fallback and absence of command submission.
- Whitespace/Unicode changes alter terminal commands: use byte-for-byte differential fixtures for the supported grammar, including all shipped templates.
- Removing a direct dependency does not prove all packages disappear: inspect resolved graphs and app link inputs; Spectre is test-only and must not be counted as runtime savings.

## Migration Plan

Capture supported-output fixtures against Stencil, implement parser and config diagnostics, run differential and processor tests, then remove Stencil/PathKit references from SwiftPM and Xcode where no other consumer remains. Document unsupported syntax and compare Release artifacts. Revert renderer and package-wiring changes to roll back; the user's config format and file remain intact.
