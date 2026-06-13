---
id: SPEC-010
status: implemented
updated: 2026-06-14
tests:
  - VoicePenTests/LLM/LLMClientTests.swift
  - VoicePenTests/Settings/UserConfigStoreTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Structured LLM Provider Layer

## Problem

VoicePen needs a reusable LLM capability for experimental local and hosted AI
features. The provider layer must not be coupled to developer-mode command
semantics because future uses may include dictionary assistance, diagnostics,
or other structured tasks.

## Behavior

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

## Acceptance Criteria

- When `[llm].provider` is absent, VoicePen shall select `ollama`.
- When provider is `openrouter` and `api_key` is empty, routing shall return a typed config error before making a request.
- The Ollama client shall call `/api/chat` with `stream=false`, configured `think`, and the supplied JSON schema in `format`.
- The OpenRouter client shall call `/chat/completions` with `Authorization`, `stream=false`, `temperature=0`, `max_completion_tokens=256`, and `response_format=json_schema`.
- When OpenRouter does not support strict JSON schema for the requested model/provider, VoicePen shall return a typed provider or config error and shall not silently fall back to a plain JSON prompt.
- Provider status failures, timeouts, invalid JSON, and unreachable providers shall surface as typed errors.
- When provider errors are surfaced, API keys and bearer tokens shall be redacted.
- The LLM provider layer shall not contain developer-mode intent catalogs, command IDs, active app allowlists, or shell-rendering behavior.
- Settings shall not expose an AI section or AI sidebar icon.
- Provider configuration shall remain editable through `~/.voicepen/config.toml`.
- Configuring an LLM provider shall not imply that dictation will be sent to AI.
- The app UI shall not expose Developer-mode intent parser controls in an AI section; Modes settings owns feature-specific command parsing behavior.
- Opening and reloading TOML config belongs to the dedicated Settings screen.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default provider | `[llm]` omitted | `ollama` provider config is selected |
| Missing OpenRouter key | `provider = "openrouter"` with empty `api_key` | typed configuration error before HTTP request |
| Ollama unavailable | Ollama provider cannot connect to `base_url` | typed provider-unavailable error |
| OpenRouter key in app UI | `api_key = "sk-or-secret"` | App UI does not show the AI settings section or expose the key |
| Edit provider config | User wants to change provider to OpenRouter | User edits `[llm]` in TOML through the Settings screen config-file controls |
| Developer command parsing | User wants to enable AI command parsing | User changes the setting in Modes, not AI |
| Advanced settings | User wants to tune `timeout_seconds` or `think` | User edits `~/.voicepen/config.toml` through the Settings screen |
| Config controls | User wants to open or reload TOML | Settings screen owns the action |

## Test Mapping

- Automated: `VoicePenTests/LLM/LLMClientTests.swift` covers Ollama and OpenRouter request shape, Ollama availability ping behavior, status failures, timeouts, invalid JSON, strict schema unsupported errors, unreachable provider errors, and API key redaction.
- Automated: `VoicePenTests/Settings/UserConfigStoreTests.swift` covers default LLM provider config, OpenRouter empty-key config validation, and TOML save behavior while preserving TOML-only advanced values.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that the settings sidebar does not expose the AI section and keeps generic config controls in the Settings screen.
- Manual: open the main window and verify there is no AI sidebar icon or AI settings section; edit LLM values through Settings > Config > Open Config File when provider changes are needed.

## Notes

The standalone LLM feature is infrastructure only. It does not decide whether a
transcript is eligible for model use and does not execute model output.

## Open Questions

- None.
