## ADDED Requirements

### Requirement: Command templates use an explicit bounded language

VoicePen SHALL render literal text and substitutions of `text`, `normalized` and `args` inside double braces, with optional whitespace and left-to-right chains of the existing eight documented string filters. Literal whitespace SHALL be preserved. Substituted values SHALL be treated as data and SHALL NOT be parsed recursively as template syntax. This requirement defines the supported command-template language in place of incidental access to the full former template engine.

#### Scenario: Supported template renders variables and chained filters

- **WHEN** a matched command uses literals and supported variables with zero or more supported filters
- **THEN** the rendered command preserves existing variable values, filter behavior and literal whitespace, including Unicode, empty values and repeated substitutions

#### Scenario: Recognized speech contains template delimiters

- **WHEN** a substituted variable contains braces, filter separators or template control-tag text
- **THEN** VoicePen inserts that value literally after the requested filters without evaluating it again

### Requirement: Unsupported templates fail without executing a partial command

VoicePen SHALL reject unknown variables, unknown filters, filter arguments, malformed substitutions and template control tags instead of partially rendering them. It SHALL report the affected command in configuration diagnostics without rewriting the user's file. Invalid commands SHALL NOT prevent unrelated valid commands or aliases from loading.

#### Scenario: Existing configuration uses unsupported template syntax

- **WHEN** a command template contains unsupported or malformed syntax
- **THEN** config diagnostics identify the affected command and template problem while retaining valid commands, aliases and the original file

#### Scenario: An invalid template's trigger is spoken

- **WHEN** a spoken phrase matches a command whose template is invalid or unsupported
- **THEN** VoicePen returns the existing normalized dictation fallback with a diagnostic, does not choose another command in its place, and does not submit or insert any partially rendered command

#### Scenario: User fixes an invalid template

- **WHEN** a previously invalid template is corrected in the user configuration before the next dictation
- **THEN** VoicePen uses the corrected template through the existing config reload path without restarting or changing settings
