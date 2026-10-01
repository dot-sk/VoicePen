# Developer Mode And User TOML Config Specification

## Purpose

Developers need VoicePen to turn spoken technical intent into predictable text or terminal commands without asking an LLM to invent shell commands.

## Requirements

### Requirement: Developer Mode And User TOML Config

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen defaults to plain dictation. When the Modes feature flag is enabled,
VoicePen reads a single user-editable TOML file at `~/.voicepen/config.toml`,
creates it from a bundled default when missing, applies configured aliases before
command matching, and processes terminal commands from explicit trigger
allowlists. The config is reloaded for each dictation. The UI labels the
developer text mode as Writing Code while preserving the TOML value `developer`,
and automatic mode classifies the active app as terminal, developer, or plain.

#### Scenario: ~/.voicepen/config.toml is missing

- **WHEN** `~/.voicepen/config.toml` is missing
- **THEN** VoicePen shall create it from the bundled default config before reading user config.

#### Scenario: ~/.voicepen/config.toml already exists

- **WHEN** `~/.voicepen/config.toml` already exists
- **THEN** VoicePen shall not overwrite it.

#### Scenario: [env] contains proxy values

- **WHEN** `[env]` contains proxy values
- **THEN** VoicePen shall normalize and apply them like existing environment settings.

#### Scenario: Dictation is processed

- **WHEN** a dictation is processed
- **THEN** VoicePen shall reread `~/.voicepen/config.toml` without requiring an app restart.

#### Scenario: Config parsing fails

- **WHEN** config parsing fails
- **THEN** VoicePen shall keep using the last valid config and add a diagnostic note to the current history entry without marking dictation as failed.

#### Scenario: Modes feature flag is disabled

- **WHEN** the Modes feature flag is disabled
- **THEN** VoicePen shall hide the Modes settings section and process dictation as plain text without reading TOML mode, aliases, commands, or UI mode override.

#### Scenario: Modes feature flag is disabled 2

- **WHEN** the Modes feature flag is disabled
- **THEN** VoicePen shall not call the LLM intent parser because developer and terminal contexts are unavailable.

#### Scenario: User has selected Plain, Auto, Writing Code, or Terminal in the UI

- **WHEN** the user has selected Plain, Auto, Writing Code, or Terminal in the UI
- **THEN** VoicePen shall use that mode instead of `[developer].mode`.

#### Scenario: Settings window is open

- **WHEN** the settings window is open
- **THEN** VoicePen shall show Plain, Auto, Writing Code, and Terminal mode selection in a dedicated Modes settings tab rather than Home.

#### Scenario: No feature-flag-only sections are enabled

- **WHEN** no feature-flag-only sections are enabled
- **THEN** VoicePen shall order sidebar sections as Home, Meetings, History, then a Settings block with Dictionary, Model, Settings, and About.

#### Scenario: Settings window is open 2

- **WHEN** the settings window is open
- **THEN** VoicePen shall show push-to-talk shortcut controls in the Settings screen.

#### Scenario: UI shows Writing Code

- **WHEN** the UI shows Writing Code
- **THEN** VoicePen shall keep storing and reading the compatible TOML mode value `developer`.

#### Scenario: Modes settings tab is open

- **WHEN** the Modes settings tab is open
- **THEN** VoicePen shall show a short user-facing summary of mode routing plus a note that a configured AI provider is needed for full supported command parsing; detailed behavior for Plain, Auto, Writing Code, and Terminal shall live in separate per-mode sections, including a terminal command example.

#### Scenario: Settings window is open 3

- **WHEN** the settings window is open
- **THEN** VoicePen shall expose TOML file path, status, reload, diagnostics, and open-file controls only in the Settings screen, with path and status grouped under a `Config file` block.

#### Scenario: User chooses to open the config file from the Settings screen

- **WHEN** the user chooses to open the config file from the Settings screen
- **THEN** VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.

#### Scenario: User chooses to reload config from the Settings screen

- **WHEN** the user chooses to reload config from the Settings screen
- **THEN** VoicePen shall reread `~/.voicepen/config.toml`, refresh settings displays backed by user config, and surface config diagnostics there.

#### Scenario: User chooses to reload config from the Settings screen 2

- **WHEN** the user chooses to reload config from the Settings screen
- **THEN** VoicePen shall show short success feedback on the reload control without resizing the control.

#### Scenario: User switches to the Settings screen

- **WHEN** the user switches to the Settings screen
- **THEN** VoicePen shall refresh TOML-backed settings after the settings view update rather than synchronously publishing during SwiftUI view construction.

#### Scenario: User presses the standard macOS Settings shortcut Command +

- **WHEN** the user presses the standard macOS Settings shortcut `Command + ,`
- **THEN** VoicePen shall ensure `~/.voicepen/config.toml` exists and then open it with the system default editor.

#### Scenario: Saves TOML-backed settings from the UI

- **WHEN** VoicePen saves TOML-backed settings from the UI
- **THEN** it shall write non-ASCII config text such as Russian aliases and triggers as readable UTF-8 characters rather than unicode escape sequences.

#### Scenario: No UI mode override exists

- **WHEN** no UI mode override exists
- **THEN** VoicePen shall use `[developer].mode`; `auto` shall classify the active app as terminal, developer, or plain.

#### Scenario: Aliases are applied

- **WHEN** aliases are applied
- **THEN** VoicePen shall apply `aliases.common` in all contexts, then active-context aliases, case-insensitively, longest-first, and only across word boundaries.

#### Scenario: Common and context aliases conflict

- **WHEN** common and context aliases conflict
- **THEN** the active-context alias shall win.

#### Scenario: Voice correction is useful only for terminal commands

- **WHEN** a voice correction is useful only for terminal commands
- **THEN** VoicePen shall keep it in terminal aliases so plain dictation keeps ordinary words unchanged.

#### Scenario: Command triggers are matched

- **WHEN** command triggers are matched
- **THEN** VoicePen shall match after alias normalization, require the normalized input tokens to start with the normalized trigger tokens, and choose the longest matching trigger.

#### Scenario: Command triggers are matched 2

- **WHEN** command triggers are matched
- **THEN** VoicePen shall use the raw transcript plus TOML aliases before applying the custom dictionary, so dictionary entries cannot prevent configured commands from matching.

#### Scenario: Command triggers are matched 3

- **WHEN** command triggers are matched
- **THEN** VoicePen shall normalize command phrases by treating dictation punctuation as separators and collapsing repeated whitespace.

#### Scenario: Command phrases include filler words such as "ну", "давай", "пожалуйста", or "please" before or

- **WHEN** command phrases include filler words such as "ну", "давай", "пожалуйста", or "please" before or inside the spoken trigger
- **THEN** VoicePen shall ignore those fillers for command matching.

#### Scenario: Default terminal commands are configured

- **WHEN** default terminal commands are configured
- **THEN** VoicePen shall include conversational Russian trigger phrases for common git status, history, diff, staged diff, branch listing, and branch creation commands.

#### Scenario: No command matches

- **WHEN** no command matches
- **THEN** VoicePen shall apply the custom dictionary and then TOML aliases for normal dictation text.

#### Scenario: Text resembles a command but no command matches

- **WHEN** text resembles a command but no command matches
- **THEN** VoicePen shall keep normal dictation behavior and add a diagnostic note only for command-like text.

#### Scenario: Terminal command template renders successfully

- **WHEN** a terminal command template renders successfully
- **THEN** VoicePen shall insert the rendered command instead of the spoken phrase.

#### Scenario: Command template renders

- **WHEN** a command template renders
- **THEN** VoicePen shall expose the remaining text after the matched trigger as `args`.

#### Scenario: Terminal command action is pasteAndSubmit

- **WHEN** terminal command action is `pasteAndSubmit`
- **THEN** VoicePen shall paste and press Enter only in terminal context; other contexts shall paste without Enter.

#### Scenario: Templates use filters

- **WHEN** templates use filters
- **THEN** VoicePen shall support `trim`, `lowercase`, `uppercase`, `kebabcase`, `snakecase`, `pascalcase`, `camelcase`, and `gitBranch`.

#### Scenario: GitBranch formats text

- **WHEN** `gitBranch` formats text
- **THEN** VoicePen shall produce a best-effort snake_case branch-safe value, collapse repeated separators, and trim unsafe edge separators without blocking command insertion.
