## Why

VoicePen currently uses a full Stencil engine and PathKit for a small command-template interface. A local bounded renderer can preserve the documented variables and filters while making the supported language and invalid-template behavior explicit.

## What Changes

- Replace Stencil with a local renderer for literal text, `text`, `normalized`, `args`, and chains of the eight documented string filters.
- Preserve whitespace and existing transformations for supported templates without evaluating inserted values as new template syntax.
- **BREAKING**: Full Stencil constructs outside this bounded grammar become unsupported. Existing affected templates must be detected and surfaced as configuration diagnostics rather than silently changed or partially executed.
- Invalid or unsupported matched templates use the existing ordinary-dictation fallback and diagnostic path, without command submission.
- Remove Stencil and its now-unneeded transitive packages after compatibility checks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `developer-mode-user-toml-config`: define the bounded template language and safe behavior for malformed or unsupported templates.

## Impact

CommandTemplateRenderer, user-config diagnostics, command rendering tests and SwiftPM/Xcode dependencies. TOMLKit, command matching, aliases, public supported filters and insertion behavior for valid templates remain unchanged. No automatic rewriting of user configuration.
