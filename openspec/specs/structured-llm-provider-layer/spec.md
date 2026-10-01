# Structured LLM Provider Layer Specification

## Purpose

VoicePen needs a reusable LLM capability for experimental local and hosted AI
features. The provider layer must not be coupled to developer-mode command
semantics because future uses may include dictionary assistance, diagnostics,
or other structured tasks.

## Requirements

### Requirement: Structured LLM Provider Layer

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen provides a standalone LLM feature that sends structured JSON prompts to
the configured provider and returns model text or typed errors. The layer owns
provider configuration, HTTP request shape, timeout handling, strict structured
output support, and secret redaction. LLM provider configuration is edited
through TOML config, not through a visible AI settings section. The layer does
not know about developer commands, intent IDs, active app contexts, or command
rendering.

Developer-mode intent parsing is one consumer of this LLM feature. Future
features may reuse the same provider routing without importing developer-mode
prompt or registry logic.

#### Scenario: [llm].provider is absent

- **WHEN** `[llm].provider` is absent
- **THEN** VoicePen shall select `ollama`.

#### Scenario: Provider is openrouter and apikey is empty

- **WHEN** provider is `openrouter` and `api_key` is empty
- **THEN** routing shall return a typed config error before making a request.

#### Scenario: Ollama client

- **WHEN** this capability applies
- **THEN** The Ollama client shall call `/api/chat` with `stream=false`, configured `think`, and the supplied JSON schema in `format`.

#### Scenario: OpenRouter client

- **WHEN** this capability applies
- **THEN** The OpenRouter client shall call `/chat/completions` with `Authorization`, `stream=false`, `temperature=0`, `max_completion_tokens=256`, and `response_format=json_schema`.

#### Scenario: OpenRouter does not support strict JSON schema for the requested model/provider

- **WHEN** OpenRouter does not support strict JSON schema for the requested model/provider
- **THEN** VoicePen shall return a typed provider or config error and shall not silently fall back to a plain JSON prompt.

#### Scenario: Provider status failures, timeouts, invalid JSON, and unreachable providers

- **WHEN** this capability applies
- **THEN** Provider status failures, timeouts, invalid JSON, and unreachable providers shall surface as typed errors.

#### Scenario: Provider errors are surfaced

- **WHEN** provider errors are surfaced
- **THEN** API keys and bearer tokens shall be redacted.

#### Scenario: LLM provider layer

- **WHEN** this capability applies
- **THEN** The LLM provider layer shall not contain developer-mode intent catalogs, command IDs, active app allowlists, or shell-rendering behavior.

#### Scenario: Settings

- **WHEN** this capability applies
- **THEN** Settings shall not expose an AI section or AI sidebar icon.

#### Scenario: Provider configuration

- **WHEN** this capability applies
- **THEN** Provider configuration shall remain editable through `~/.voicepen/config.toml`.

#### Scenario: Configuring an LLM provider

- **WHEN** this capability applies
- **THEN** Configuring an LLM provider shall not imply that dictation will be sent to AI.

#### Scenario: App UI

- **WHEN** this capability applies
- **THEN** The app UI shall not expose Developer-mode intent parser controls in an AI section; Modes settings owns feature-specific command parsing behavior.

#### Scenario: Opening and reloading TOML config belongs to the dedicated Settings screen

- **WHEN** this capability applies
- **THEN** Opening and reloading TOML config belongs to the dedicated Settings screen.
