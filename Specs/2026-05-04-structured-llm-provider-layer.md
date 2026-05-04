---
id: SPEC-010
status: implemented
updated: 2026-05-05
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
output support, and secret redaction. It does not know about developer commands,
intent IDs, active app contexts, or command rendering.

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
- Settings shall expose an AI section that displays and edits the current LLM provider plus the active provider's everyday connection settings.
- The AI settings section shall make provider configuration distinct from per-feature enablement: configuring a provider shall not imply that dictation will be sent to AI.
- When the selected provider is Ollama, the AI settings section shall show Ollama base URL and model fields and shall hide OpenRouter fields.
- When the selected provider is OpenRouter, the AI settings section shall show OpenRouter base URL, model, and API key fields and shall hide Ollama fields.
- The AI settings section shall automatically save changes to LLM provider and active provider connection settings back to `~/.voicepen/config.toml` without requiring Save or Discard buttons.
- When the user switches the selected AI provider, VoicePen shall save the provider change after the current SwiftUI view update rather than synchronously publishing from the provider picker update.
- The AI settings section shall use the same immediate settings binding model as other settings sections: controls read from the loaded user config and write changes through the settings controller to TOML, without maintaining a separate editable draft or reload state.
- The AI settings section shall display only whether the OpenRouter API key is configured, never the key value itself.
- The AI settings section shall not expose Developer-mode intent parser controls; Modes settings owns feature-specific command parsing behavior.
- The AI settings section shall not expose advanced LLM tuning fields such as provider timeouts or Ollama thinking mode; those remain editable through TOML config only.
- The AI settings section shall not expose generic config file controls; opening and reloading TOML config belongs to the dedicated Config settings section.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default provider | `[llm]` omitted | `ollama` provider config is selected |
| Missing OpenRouter key | `provider = "openrouter"` with empty `api_key` | typed configuration error before HTTP request |
| Ollama unavailable | Ollama provider cannot connect to `base_url` | typed provider-unavailable error |
| OpenRouter key in AI settings | `api_key = "sk-or-secret"` | AI settings shows `API key: Configured` and never displays the key |
| Edit provider in AI settings | User changes provider to OpenRouter | TOML `[llm]` settings are updated without using generic config file controls or a Save button |
| Provider switch in AI settings | User selects OpenRouter | OpenRouter fields replace Ollama fields in the provider settings block |
| Developer command parsing | User wants to enable AI command parsing | User changes the setting in Modes, not AI |
| Advanced settings | User wants to tune `timeout_seconds` or `think` | User edits `~/.voicepen/config.toml` through Config settings |
| Config controls | User wants to open or reload TOML | Config settings owns the action, AI settings only reflects loaded values |

## Test Mapping

- Automated: `VoicePenTests/LLM/LLMClientTests.swift` covers Ollama and OpenRouter request shape, status failures, timeouts, invalid JSON, strict schema unsupported errors, unreachable provider errors, and API key redaction.
- Automated: `VoicePenTests/Settings/UserConfigStoreTests.swift` covers default LLM provider config, OpenRouter empty-key config validation, AI settings summary values, immediate settings persistence while preserving TOML-only advanced values, and OpenRouter API key status without exposing the key.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that the settings sidebar exposes the AI section, routes it to the AI settings view, writes provider-specific controls through shared settings bindings, defers provider picker persistence until after the current view update, shows active provider controls, leaves Developer command parsing in Modes, and keeps generic config controls in Config settings.
- Manual: edit LLM values in Settings > AI, switch between Ollama and OpenRouter, then open Settings > Config > Open Config File and verify the TOML values changed immediately while provider timeout and Ollama thinking remain whatever TOML configured.

## Notes

The standalone LLM feature is infrastructure only. It does not decide whether a
transcript is eligible for model use and does not execute model output.

## Open Questions

- None.
