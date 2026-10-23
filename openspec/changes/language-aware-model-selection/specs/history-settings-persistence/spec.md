## ADDED Requirements

### Requirement: Language-specific model choices persist together

VoicePen SHALL persist the selected language, model and remembered language-to-model choices through the existing shared SQLite settings path. Selection updates SHALL commit atomically before publishing. Existing settings without remembered choices SHALL preserve their valid selection and initialize a compatible current language/model pair. Missing or malformed remembered data SHALL behave as an empty preference map without blocking startup.

#### Scenario: Restart after choosing models for different languages

- **WHEN** VoicePen restarts after separate Russian and English model selections
- **THEN** the selected language/model and remembered choices are restored for subsequent switches

#### Scenario: Upgrade without a valid preference map

- **WHEN** remembered choices are missing or malformed
- **THEN** startup preserves existing settings and seeds a compatible current selection without inventing unsupported language associations

#### Scenario: Selection persistence fails

- **WHEN** a selection cannot be saved
- **THEN** persisted and published selection values remain unchanged and VoicePen surfaces the error
