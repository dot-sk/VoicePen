## Why

English-only model selection currently locks the language menu. Users need to switch languages without manually finding a compatible model each time.

## What Changes

- Keep language selection available in Settings and the tray for every model.
- Restore the last-used model for each selected language, equally for English and Russian, even when the current model supports both.
- Persist language-to-model preferences and use a deterministic compatible fallback without automatic downloads.
- Selecting an incompatible model explicitly changes the selected language to that model's supported language.

## Capabilities

### New Capabilities

### Modified Capabilities

- `local-transcription-model-handling`: language-driven compatible model selection and consistent controls.
- `history-settings-persistence`: persistent language-to-model preferences with safe migration.

## Impact

Shared settings persistence, a local routing policy, AppController selection commands, Settings/tray bindings, and automated tests. Native ASR decoding remains unchanged.
