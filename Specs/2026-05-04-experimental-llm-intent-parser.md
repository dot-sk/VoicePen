---
id: SPEC-009
status: implemented
updated: 2026-05-05
tests:
  - VoicePenTests/DeveloperMode/LLMIntentParserTests.swift
  - VoicePenTests/DeveloperMode/LLMIntentPromptBuilderTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/Settings/UserConfigStoreTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Experimental LLM Intent Parser

## Problem

Developer mode can map exact configured phrases to commands, but noisy Russian
developer speech often expresses the same supported action with wording that is
hard to cover with trigger lists. VoicePen needs an experimental LLM parser that
classifies only supported first-party intents without asking the model to invent
shell commands.

## Behavior

VoicePen provides an experimental intent parsing use case backed by the
standalone structured-output LLM provider layer from SPEC-010. The feature is
behind the AI feature flag and disabled by default. When the feature flag,
config, and non-plain context are all enabled, live dictation first applies
deterministic TOML command matching; if no configured command matches, it applies local
candidate gates, then sends only likely short developer command utterances and a
registry-derived intent catalog to the selected LLM provider. It validates the
JSON response against the active allowlist, applies a confidence threshold, and
renders supported intents through local deterministic command templates.

The intent parser owns the prompt, registry, validation, confidence policy,
privacy gates, and typed result. Command rendering and execution remain
deterministic and allowlist-based.

## Acceptance Criteria

- When `[developer.intent_parser].enabled` is absent, the parser shall be disabled.
- When `[developer.intent_parser].confidence_threshold` is absent, the parser shall use `0.75`.
- When the AI feature flag is disabled, live dictation shall not call the LLM intent parser even if TOML enables it.
- When the AI feature flag is disabled, VoicePen shall hide the AI settings section.
- When context is `plain`, the intent parser shall return `disabled` without calling an LLM.
- When the parser is disabled, it shall return `disabled` without calling an LLM.
- When live dictation finds a deterministic TOML command trigger match, VoicePen shall use that command without calling the LLM parser.
- When live dictation finds no deterministic command match and parser settings are enabled, VoicePen shall call the LLM parser only if local candidate gates pass.
- When the LLM parser returns a supported parsed intent during live terminal dictation, VoicePen shall render the command locally and insert it using the configured terminal command action.
- When the LLM parser is disabled, gated out, rejected, invalid, or unavailable during live dictation, VoicePen shall keep normal dictation behavior instead of blocking insertion.
- When context is `developer` or `terminal`, the parser shall build its allowed intent catalog from a code registry for that context.
- When the active registry is empty, the parser shall return `disabled` without calling an LLM.
- When the transcript is too long to be a short command utterance, the parser shall return `disabled` without calling an LLM.
- When the transcript does not contain local command-intent trigger signals, the parser shall return `disabled` without calling an LLM.
- When local trigger matching runs, it shall include conversational Russian command forms and common ASR artifacts for first-party git intents.
- When the LLM returns valid JSON with an allowed intent and confidence at or above the threshold, the parser shall return `parsed(CommandIntent)`.
- When confidence is below the configured threshold, the parser shall return `rejected(.lowConfidence)`.
- When the LLM returns an intent outside the active registry, the parser shall return `rejected(.unsupportedIntent)`.
- When model output is invalid JSON or does not match the output contract, the parser shall return `invalidModelOutput`.
- When the provider fails, the parser shall return `providerFailed`.
- When the parser is enabled with provider `ollama` but Ollama is not installed, not running, or unreachable at `base_url`, VoicePen shall return a typed provider-unavailable failure without changing dictation behavior or crashing.
- When building prompts, VoicePen shall use one canonical short user prompt with JSON-only and no-shell-command instructions, and shall insert only a registry-derived catalog.
- When parsing succeeds, `argumentText` shall preserve the useful spoken target or message and shall not contain a generated shell command.
- The Modes settings section shall present intent parser controls inside the relevant per-mode section rather than as a global AI enable switch.
- The Modes settings section shall display the current parser enabled state and confidence threshold from user TOML config.
- The Modes settings section shall let the user edit and save parser enabled state and confidence threshold back to user TOML config.
- The AI settings section shall not expose intent parser controls; it shall only connect the reusable AI provider.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Plain context | `создай ветку TTP сто` in plain context | `disabled`, no LLM request |
| Ordinary prose | `напиши текст про git workflow` | `disabled`, no LLM request |
| Too long | Long paragraph containing `создай ветку` | `disabled`, no LLM request |
| Configured trigger | `git status` matches TOML command | Deterministic command is inserted; no LLM request |
| Branch intent | `создай фича ветку TTP сто` in terminal context | `parsed` with `git.branch.create`, `argumentText: "TTP сто"`, and optional `branchKind: "feature"` |
| Live branch intent | `сделай бранч TTP сто` in terminal context with parser enabled | Local renderer inserts `git checkout -b ttp_sto` |
| ASR artifact | `сделай бранч TTP сто` in terminal context | Eligible for LLM parse |
| Low confidence | Valid output with `confidence: 0.5` | `rejected(.lowConfidence)` |
| Unsupported | Model returns `shell.run` | `rejected(.unsupportedIntent)` |
| Invalid output | Model returns prose or missing keys | `invalidModelOutput` |

## Test Mapping

- Automated: `VoicePenTests/DeveloperMode/LLMIntentParserTests.swift` covers disabled/plain behavior, registry allowlists, parsed output, low confidence, unsupported intents, invalid output, provider failures, and command-free `argumentText`.
- Automated: `VoicePenTests/DeveloperMode/LLMIntentPromptBuilderTests.swift` covers prompt signals and registry-derived catalog insertion without snapshotting the full prompt.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers live pipeline integration, including deterministic trigger priority, gated LLM fallback, local command rendering, and provider failure fallback.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers skipping LLM parsing when the AI feature flag is disabled.
- Automated: `VoicePenTests/Settings/UserConfigStoreTests.swift` covers intent parser config defaults, AI settings summary values for parser state, and saving parser settings through the same immediate settings persistence path used by settings UI.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that Developer command parsing controls live in Modes settings and are not exposed in AI settings.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers hiding the AI settings section behind the AI feature flag.
- Manual: keep `[developer.intent_parser].enabled = false`, dictate in developer and terminal modes, and verify live dictation behavior uses only configured triggers and normal dictation.
- Manual: enable `[developer.intent_parser]`, use a short supported terminal command phrase that is not listed in TOML triggers, and verify it is parsed and rendered locally.
- Manual: edit parser settings in Settings > Modes and verify the next Settings > Config reload reflects the same TOML-backed values.

## Notes

The v1 registry contains only first-party developer intents. User TOML commands
do not automatically become LLM intents.

The canonical prompt asks for exactly `intent`, `confidence`, `argumentText`,
and `slots`. `slots` may contain obvious controlled metadata only, using string
values.

## Open Questions

- None.
