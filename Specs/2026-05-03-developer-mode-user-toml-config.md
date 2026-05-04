---
id: SPEC-008
status: implemented
updated: 2026-05-04
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/Settings/UserConfigStoreTests.swift
  - VoicePenTests/DeveloperMode/ActiveAppContextClassifierTests.swift
  - VoicePenTests/DeveloperMode/DeveloperModeProcessorTests.swift
  - VoicePenTests/Settings/AppSettingsStoreTests.swift
  - VoicePenTests/Pipeline/DictationPipelineTests.swift
  - VoicePenTests/History/VoiceHistoryStoreTests.swift
---

# Developer Mode And User TOML Config

## Problem

Developers need VoicePen to turn spoken technical intent into predictable text or terminal commands without asking an LLM to invent shell commands.

## Behavior

VoicePen reads a single user-editable TOML file at `~/.voicepen/config.toml`, creates it from a bundled default when missing, applies configured aliases before command matching, and processes terminal commands from explicit trigger allowlists. The config is reloaded for each dictation. The UI labels the developer text mode as Writing Code while preserving the TOML value `developer`, and automatic mode classifies the active app as terminal, developer, or plain.

## Acceptance Criteria

- When `~/.voicepen/config.toml` is missing, VoicePen shall create it from the bundled default config before reading user config.
- When `~/.voicepen/config.toml` already exists, VoicePen shall not overwrite it.
- When `[env]` contains proxy values, VoicePen shall normalize and apply them like existing environment settings.
- When a dictation is processed, VoicePen shall reread `~/.voicepen/config.toml` without requiring an app restart.
- When config parsing fails, VoicePen shall keep using the last valid config and add a diagnostic note to the current history entry without marking dictation as failed.
- When the user has selected Plain, Auto, Writing Code, or Terminal in the UI, VoicePen shall use that mode instead of `[developer].mode`.
- When the settings window is open, VoicePen shall show Plain, Auto, Writing Code, and Terminal mode selection in a dedicated Modes settings tab rather than General settings.
- When the UI shows Writing Code, VoicePen shall keep storing and reading the compatible TOML mode value `developer`.
- When the Modes settings tab is open, VoicePen shall show a short user-facing description of what modes do and a per-mode explanation for Plain, Auto, Writing Code, and Terminal, including a terminal command example.
- When the user chooses to open the config file from Modes settings, VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.
- When the user presses the standard macOS Settings shortcut `Command + ,`, VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.
- When no UI mode override exists, VoicePen shall use `[developer].mode`; `auto` shall classify the active app as terminal, developer, or plain.
- When aliases are applied, VoicePen shall apply `aliases.common` in all contexts, then active-context aliases, case-insensitively, longest-first, and only across word boundaries.
- When common and context aliases conflict, the active-context alias shall win.
- When a voice correction is useful only for terminal commands, VoicePen shall keep it in terminal aliases so plain dictation keeps ordinary words unchanged.
- When command triggers are matched, VoicePen shall match after alias normalization, require the normalized input tokens to start with the normalized trigger tokens, and choose the longest matching trigger.
- When command triggers are matched, VoicePen shall use the raw transcript plus TOML aliases before applying the custom dictionary, so dictionary entries cannot prevent configured commands from matching.
- When command triggers are matched, VoicePen shall normalize command phrases by treating dictation punctuation as separators and collapsing repeated whitespace.
- When command phrases include filler words such as "ну", "давай", "пожалуйста", or "please" before or inside the spoken trigger, VoicePen shall ignore those fillers for command matching.
- When default terminal commands are configured, VoicePen shall include conversational Russian trigger phrases for common git status, history, diff, staged diff, branch listing, and branch creation commands.
- When no command matches, VoicePen shall apply the custom dictionary and then TOML aliases for normal dictation text.
- When text resembles a command but no command matches, VoicePen shall keep normal dictation behavior and add a diagnostic note only for command-like text.
- When a terminal command template renders successfully, VoicePen shall insert the rendered command instead of the spoken phrase.
- When a command template renders, VoicePen shall expose the remaining text after the matched trigger as `args`.
- When terminal command action is `pasteAndSubmit`, VoicePen shall paste and press Enter only in terminal context; other contexts shall paste without Enter.
- When templates use filters, VoicePen shall support `trim`, `lowercase`, `uppercase`, `kebabcase`, `snakecase`, `pascalcase`, `camelcase`, and `gitBranch`.
- When `gitBranch` formats text, VoicePen shall produce a best-effort snake_case branch-safe value, collapse repeated separators, and trim unsafe edge separators without blocking command insertion.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Russian git history | `покажи гит историю` in terminal context | `git log --oneline --decorate --graph` |
| Russian git history phrasing | `Покажи историю в гите.` in terminal context | `git log --oneline --decorate --graph` |
| English git history | `show git history` in terminal context | `git log --oneline --decorate --graph` |
| All branch history | `покажи всю гит историю` or `show all git history` | `git log --oneline --decorate --graph --all` |
| Misheard git status | `Покажи гид статус.` in terminal context | `git status --short --branch` |
| Short git status | `Что в git?` in terminal context | `git status --short --branch` |
| Conversational git status | `Что там в гите?` in terminal context | `git status --short --branch` |
| Conversational git diff | `Что изменилось в гите?` in terminal context | `git diff` |
| Conversational staged diff | `Что в индексе?` in terminal context | `git diff --cached` |
| Conversational branches | `Какие ветки?` in terminal context | `git branch --all` |
| Branch creation | `создай ветку Developer Mode Config` | `git checkout -b developer_mode_config` |
| Conversational branch creation | `Сделай ветку Developer Mode Config` | `git checkout -b developer_mode_config` |
| Feature branch | `create feature branch Developer Mode Config` | `git checkout -b feature/developer_mode_config` |
| Dictionary conflict | User dictionary maps `гит` differently, terminal command says `гит status` | Command still matches via TOML alias and inserts `git status --short --branch` |
| Plain app | Unknown foreground app in auto mode | Normal dictation text is inserted |
| Standard settings shortcut | User presses `Command + ,` | User TOML config is created if needed and opened in the default editor |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers `Command + ,` being wired to opening the user TOML config.
- Automated: `VoicePenTests/Settings/UserConfigStoreTests.swift` covers default TOML creation, non-overwrite, env normalization, config reload, and invalid-config fallback diagnostics.
- Automated: `VoicePenTests/DeveloperMode/ActiveAppContextClassifierTests.swift` covers terminal, developer, and plain active app classification.
- Automated: `VoicePenTests/DeveloperMode/DeveloperModeProcessorTests.swift` covers aliases, command matching, longest triggers, filters, branch formatting, action gating, command-like diagnostics, and user-facing mode description signals.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers persisted UI mode override.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers per-dictation config reload and history diagnostics passing through pipeline results.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers persistence of diagnostic notes.
- Manual: open Settings, verify mode selection, the short modes overview, and per-mode explanations appear under the Modes tab and no longer appear under General.
- Manual: use Open Config File from Modes settings with no existing `~/.voicepen/config.toml`, verify the default file is created and opens in the system default editor.
- Manual: press `Command + ,` with VoicePen active and verify the same config file opens.
- Manual: edit `~/.voicepen/config.toml`, add one custom alias and one custom terminal command, keep VoicePen running, dictate both, and verify the next dictation uses the edited config.

## Notes

Command execution is allowlist-based in v1: VoicePen renders configured templates from explicit triggers and safe template context only. Templates receive `text`, `normalized`, and `args`. VoicePen does not infer arbitrary shell commands from free-form dictation.

Default branch prefixes are `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`, and `test/`.

## Open Questions

- None.
