---
id: SPEC-008
status: implemented
updated: 2026-05-06
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

VoicePen defaults to plain dictation. When the Modes feature flag is enabled,
VoicePen reads a single user-editable TOML file at `~/.voicepen/config.toml`,
creates it from a bundled default when missing, applies configured aliases before
command matching, and processes terminal commands from explicit trigger
allowlists. The config is reloaded for each dictation. The UI labels the
developer text mode as Writing Code while preserving the TOML value `developer`,
and automatic mode classifies the active app as terminal, developer, or plain.

## Acceptance Criteria

- When `~/.voicepen/config.toml` is missing, VoicePen shall create it from the bundled default config before reading user config.
- When `~/.voicepen/config.toml` already exists, VoicePen shall not overwrite it.
- When `[env]` contains proxy values, VoicePen shall normalize and apply them like existing environment settings.
- When a dictation is processed, VoicePen shall reread `~/.voicepen/config.toml` without requiring an app restart.
- When config parsing fails, VoicePen shall keep using the last valid config and add a diagnostic note to the current history entry without marking dictation as failed.
- When the Modes feature flag is disabled, VoicePen shall hide the Modes settings section and process dictation as plain text without reading TOML mode, aliases, commands, or UI mode override.
- When the Modes feature flag is disabled, VoicePen shall not call the LLM intent parser because developer and terminal contexts are unavailable.
- When the user has selected Plain, Auto, Writing Code, or Terminal in the UI, VoicePen shall use that mode instead of `[developer].mode`.
- When the settings window is open, VoicePen shall show Plain, Auto, Writing Code, and Terminal mode selection in a dedicated Modes settings tab rather than General settings.
- When the settings window is open, VoicePen shall order settings sections by expected use frequency and meaning: General first, Meetings and History together near the top, workflow configuration next, advanced config/permissions/about last.
- When the settings window is open, VoicePen shall show push-to-talk shortcut controls in General settings instead of a separate Shortcuts settings section.
- When the UI shows Writing Code, VoicePen shall keep storing and reading the compatible TOML mode value `developer`.
- When the Modes settings tab is open, VoicePen shall show a short user-facing summary of mode routing plus a note that AI settings are needed for full supported command parsing; detailed behavior for Plain, Auto, Writing Code, and Terminal shall live in separate per-mode sections, including a terminal command example.
- When the settings window is open, VoicePen shall expose TOML file path, status, reload, diagnostics, and open-file controls only in a dedicated Config settings tab, with path and status grouped under a `Config file` block.
- When the user chooses to open the config file from Config settings, VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.
- When the user chooses to reload config from Config settings, VoicePen shall reread `~/.voicepen/config.toml`, refresh settings displays backed by user config, and surface config diagnostics in the Config tab.
- When the user chooses to reload config from Config settings, VoicePen shall show short success feedback on the reload control without resizing the control.
- When the user switches to Config settings, VoicePen shall refresh TOML-backed settings after the settings view update rather than synchronously publishing during SwiftUI view construction.
- When the user presses the standard macOS Settings shortcut `Command + ,`, VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.
- When VoicePen saves TOML-backed settings from the UI, it shall write non-ASCII config text such as Russian aliases and triggers as readable UTF-8 characters rather than unicode escape sequences.
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
| TOML autosave readability | Config contains `"гит"` and AI settings are changed from UI | Saved config still contains `"гит"` as UTF-8 text |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers `Command + ,` being wired to opening the user TOML config.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers settings sidebar ordering, push-to-talk controls living in General, and the dedicated Config settings tab.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers hiding Modes and AI sidebar entries behind feature flags.
- Automated: `VoicePenTests/Settings/UserConfigStoreTests.swift` covers default TOML creation, non-overwrite, env normalization, config reload, readable UTF-8 autosave, and invalid-config fallback diagnostics.
- Automated: `VoicePenTests/DeveloperMode/ActiveAppContextClassifierTests.swift` covers terminal, developer, and plain active app classification.
- Automated: `VoicePenTests/DeveloperMode/DeveloperModeProcessorTests.swift` covers aliases, command matching, longest triggers, filters, branch formatting, action gating, and command-like diagnostics.
- Automated: `VoicePenTests/Settings/AppSettingsStoreTests.swift` covers persisted UI mode override.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers per-dictation config reload and history diagnostics passing through pipeline results.
- Automated: `VoicePenTests/Pipeline/DictationPipelineTests.swift` covers plain dictation behavior when the Modes feature flag is disabled.
- Automated: `VoicePenTests/History/VoiceHistoryStoreTests.swift` covers persistence of diagnostic notes.
- Manual: open Settings, verify push-to-talk hotkey and hold-duration controls appear under General with no separate Shortcuts sidebar item.
- Manual: open Settings, verify the Modes overview is short, mentions AI setup for full command parsing, and leaves detailed behavior to the per-mode explanations under the Modes tab.
- Manual: open Settings, verify Config contains a `Config file` block with the config path and status, plus Reload Config, Open Config File, and any parse diagnostics, while Modes and AI do not show config file controls.
- Manual: press Reload Config in Config settings and verify the control briefly shows successful reload feedback without shifting neighboring controls.
- Manual: switch between Settings sections including Config and verify the console does not log a SwiftUI warning about publishing changes from within view updates.
- Manual: use Open Config File from Config settings with no existing `~/.voicepen/config.toml`, verify the default file is created and opens in the system default editor.
- Manual: press `Command + ,` with VoicePen active and verify the same config file opens.
- Manual: edit `~/.voicepen/config.toml`, add one custom alias and one custom terminal command, keep VoicePen running, dictate both, and verify the next dictation uses the edited config.

## Notes

Command execution is allowlist-based in v1: VoicePen renders configured templates from explicit triggers and safe template context only. Templates receive `text`, `normalized`, and `args`. VoicePen does not infer arbitrary shell commands from free-form dictation.

Default branch prefixes are `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`, and `test/`.

## Open Questions

- None.
