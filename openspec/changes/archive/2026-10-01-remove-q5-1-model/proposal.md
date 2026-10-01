## Why

Q5_1 sits between Q5_0 and Q8_0 without providing a distinct model choice worth maintaining. Removing it leaves one compact default and one higher-precision option, which makes model selection clearer.

## What Changes

- **BREAKING** Remove Whisper large-v3 turbo Q5_1 from the local transcription model choices.
- Keep Q5_0 as the recommended model and Q8_0 as the higher-precision alternative.
- Resolve a previously saved Q5_1 selection to the recommended Q5_0 model.
- Remove an obsolete downloaded Q5_1 model directory from VoicePen-managed storage after upgrade.
- Keep the immutable Q5_1 GitHub release asset available for older VoicePen versions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-transcription-model-handling`: Retire Q5_1 from the supported model catalog and define upgrade behavior for saved selections and downloaded files.

## Impact

- Bundled transcription model manifest and Model settings choices.
- Startup reconciliation of saved model selection and app-managed model storage.
- Model manifest, controller, settings, and cleanup tests.
- Existing published model-assets releases remain unchanged for backward compatibility.
