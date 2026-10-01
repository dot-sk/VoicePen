# Experimental LLM Intent Parser Specification

## Purpose

Developer mode can map exact configured phrases to commands, but noisy Russian
developer speech often expresses the same supported action with wording that is
hard to cover with trigger lists. VoicePen needs an experimental LLM parser that
classifies only supported first-party intents without asking the model to invent
shell commands.

## Requirements

### Requirement: Experimental LLM Intent Parser

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen provides an experimental intent parsing use case backed by the
standalone structured-output LLM provider layer from `structured-llm-provider-layer` capability. The feature is
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

#### Scenario: [developer.intentparser].enabled is absent

- **WHEN** `[developer.intent_parser].enabled` is absent
- **THEN** the parser shall be disabled.

#### Scenario: [developer.intentparser].confidencethreshold is absent

- **WHEN** `[developer.intent_parser].confidence_threshold` is absent
- **THEN** the parser shall use `0.75`.

#### Scenario: AI feature flag is disabled

- **WHEN** the AI feature flag is disabled
- **THEN** live dictation shall not call the LLM intent parser even if TOML enables it.

#### Scenario: Shall not show an AI settings section for configuring the reusable provider

- **WHEN** this capability applies
- **THEN** VoicePen shall not show an AI settings section for configuring the reusable provider.

#### Scenario: Context is plain

- **WHEN** context is `plain`
- **THEN** the intent parser shall return `disabled` without calling an LLM.

#### Scenario: Parser is disabled

- **WHEN** the parser is disabled
- **THEN** it shall return `disabled` without calling an LLM.

#### Scenario: Live dictation finds a deterministic TOML command trigger match

- **WHEN** live dictation finds a deterministic TOML command trigger match
- **THEN** VoicePen shall use that command without calling the LLM parser.

#### Scenario: Live dictation finds no deterministic command match and parser settings are enabled

- **WHEN** live dictation finds no deterministic command match and parser settings are enabled
- **THEN** VoicePen shall call the LLM parser only if local candidate gates pass.

#### Scenario: LLM parser returns a supported parsed intent during live terminal dictation

- **WHEN** the LLM parser returns a supported parsed intent during live terminal dictation
- **THEN** VoicePen shall render the command locally and insert it using the configured terminal command action.

#### Scenario: LLM parser is disabled, gated out, rejected, invalid, or unavailable during live dictation

- **WHEN** the LLM parser is disabled, gated out, rejected, invalid, or unavailable during live dictation
- **THEN** VoicePen shall keep normal dictation behavior instead of blocking insertion.

#### Scenario: Context is developer or terminal

- **WHEN** context is `developer` or `terminal`
- **THEN** the parser shall build its allowed intent catalog from a code registry for that context.

#### Scenario: Active registry is empty

- **WHEN** the active registry is empty
- **THEN** the parser shall return `disabled` without calling an LLM.

#### Scenario: Transcript is too long to be a short command utterance

- **WHEN** the transcript is too long to be a short command utterance
- **THEN** the parser shall return `disabled` without calling an LLM.

#### Scenario: Transcript does not contain local command-intent trigger signals

- **WHEN** the transcript does not contain local command-intent trigger signals
- **THEN** the parser shall return `disabled` without calling an LLM.

#### Scenario: Local trigger matching runs

- **WHEN** local trigger matching runs
- **THEN** it shall include conversational Russian command forms and common ASR artifacts for first-party git intents.

#### Scenario: LLM returns valid JSON with an allowed intent and confidence at or above the

- **WHEN** the LLM returns valid JSON with an allowed intent and confidence at or above the threshold
- **THEN** the parser shall return `parsed(CommandIntent)`.

#### Scenario: Confidence is below the configured threshold

- **WHEN** confidence is below the configured threshold
- **THEN** the parser shall return `rejected(.lowConfidence)`.

#### Scenario: LLM returns an intent outside the active registry

- **WHEN** the LLM returns an intent outside the active registry
- **THEN** the parser shall return `rejected(.unsupportedIntent)`.

#### Scenario: Model output is invalid JSON or does not match the output contract

- **WHEN** model output is invalid JSON or does not match the output contract
- **THEN** the parser shall return `invalidModelOutput`.

#### Scenario: Provider fails

- **WHEN** the provider fails
- **THEN** the parser shall return `providerFailed`.

#### Scenario: Parser is enabled with provider ollama but Ollama is not installed, not running, or

- **WHEN** the parser is enabled with provider `ollama` but Ollama is not installed, not running, or unreachable at `base_url`
- **THEN** VoicePen shall return a typed provider-unavailable failure without changing dictation behavior or crashing.

#### Scenario: Building prompts

- **WHEN** building prompts
- **THEN** VoicePen shall use one canonical short user prompt with JSON-only and no-shell-command instructions, and shall insert only a registry-derived catalog.

#### Scenario: Parsing succeeds

- **WHEN** parsing succeeds
- **THEN** `argumentText` shall preserve the useful spoken target or message and shall not contain a generated shell command.

#### Scenario: Modes settings section

- **WHEN** this capability applies
- **THEN** The Modes settings section shall present intent parser controls inside the relevant per-mode section rather than as a global AI enable switch.

#### Scenario: Modes settings section 2

- **WHEN** this capability applies
- **THEN** The Modes settings section shall display the current parser enabled state and confidence threshold from user TOML config.

#### Scenario: Modes settings section 3

- **WHEN** this capability applies
- **THEN** The Modes settings section shall let the user edit and save parser enabled state and confidence threshold back to user TOML config.

#### Scenario: App UI

- **WHEN** this capability applies
- **THEN** The app UI shall not expose intent parser controls in an AI settings section.
