## 1. Specification & Test Harness

- [x] 1.1 Add unit tests in `AppSettingsStoreTests` verifying `dictationDenoisingEnabled` default value (`true`), persistence in SQLite, and update mutations.
- [x] 1.2 Add unit tests in `WhisperOptimalAudioProcessorTests` validating 80 Hz high-pass attenuation, 280 Hz notch filtering, loudness normalization, and finite sample bounds.
- [x] 1.3 Add unit tests in `LiveAudioPreprocessingClientTests` validating that dictation preprocessing respects the dynamic noise suppression provider and chains acoustic clarity processing.

## 2. Audio Processing DSP & Pipeline Implementation

- [x] 2.1 Implement `WhisperOptimalAudioProcessor` with biquad 80 Hz low-cut, 280 Hz notch, and level normalization.
- [x] 2.2 Update `LiveAudioPreprocessingClient` to accept dynamic `audioDenoiserProvider` and chain `WhisperOptimalAudioProcessor` before silence trimming.

## 3. Settings Persistence & UI Controls

- [x] 3.1 Update `AppSettingsStore` with `dictationDenoisingEnabled` property, database migration/key, and mutation method.
- [x] 3.2 Update `AppController` with facade access and wire dynamic `audioDenoiserProvider` to `dictationAudioPreprocessor`.
- [x] 3.3 Add the "Background Noise Suppression" toggle to Settings audio view with explanatory description.

## 4. Verification & Validation

- [x] 4.1 Run `openspec validate dictation-clarity-and-noise-toggle --strict` to ensure spec compliance.
- [x] 4.2 Run `make test` to verify all automated test suites pass.
- [x] 4.3 Run `make build` to verify clean app target compilation.
