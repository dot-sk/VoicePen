## Context

See `proposal.md` for motivation.

Currently, `AppController` initializes a single `dictationAudioPreprocessor` instance of `LiveAudioPreprocessingClient` with a fixed `RNNoiseAudioDenoiser`. Dictation recording always runs through RNNoise regardless of acoustic environment. Audio settings are stored in SQLite via `AppSettingsStore` and published to SwiftUI settings views. `LiveAudioPreprocessingClient` works with 16 kHz Mono Float32 PCM samples (`MonoPCM`).

## Goals / Non-Goals

**Goals:**
- Provide a user-facing toggle in Settings → Audio for dictation background noise suppression (`dictationDenoisingEnabled`, default: `true`).
- Allow `LiveAudioPreprocessingClient` to dynamically enable or bypass RNNoise suppression per dictation attempt without recreating the preprocessor.
- Implement an in-memory acoustic clarity filter (`WhisperOptimalAudioProcessor`) that runs on 16 kHz `MonoPCM`:
  - 80 Hz 2nd-order High-Pass Filter (Butterworth biquad) to remove sub-audible desk rumble, AC hum, and breathing pops.
  - 280 Hz gentle parametric notch filter (-2.5 dB, $Q = 1.2$) to strip chest resonance and desk boundary boominess.
  - Loudness normalization (target -16 LUFS / -14 dBFS RMS, peak limited to 0.95 headroom) to ensure consistent log-Mel filterbank activation in Whisper.
- Apply this acoustic clarity filter to dictation audio both when noise suppression is enabled and when disabled, prior to silence trimming.
- Preserve Meeting Mode behavior and existing audio capture contracts.

**Non-Goals:**
- Golden dataset curation and automated prompt evaluation harness (explicitly deferred to subsequent work).
- Changing Meeting audio capture or Meeting voice leveling.
- Introducing external DSP or ML framework dependencies.

## Decisions

### 1. In-memory DSP via Accelerate / Direct Biquad Filters vs. AVAudioEngine
- **Choice**: Implement `WhisperOptimalAudioProcessor` directly on `[Float]` samples using standard Audio EQ Cookbook biquad difference equations (supported by Accelerate `vDSP`).
- **Rationale**: `AVAudioEngine` offline rendering requires file I/O, CoreAudio device graph initialization, and non-trivial teardown lifecycle. Operating directly on `MonoPCM.samples` takes under 1 ms on Apple Silicon for a 15-second buffer, introduces zero async hops or temporary disk files, and is 100% testable in hermetic Swift Testing unit tests.
- **Alternatives considered**:
  - `AVAudioUnitEQ` via `AVAudioEngine.manualRenderingMode`: Rejected due to disk I/O overhead and complex lifecycle management for short push-to-talk clips.
  - Fixed pre-emphasis filter ($y[n] = x[n] - 0.97 x[n-1]$): Rejected because research demonstrates extreme high-frequency tilt increases Whisper's phonetic substitution errors.

### 2. Dynamic Noise Suppression Resolution in `LiveAudioPreprocessingClient`
- **Choice**: Inject an `audioDenoiserProvider: () -> AudioDenoising?` closure into `LiveAudioPreprocessingClient`.
- **Rationale**: Keeps `LiveAudioPreprocessingClient` decoupled from `AppSettingsStore` and SQLite while reading the latest setting dynamically on each dictation attempt. In `AppController`, the provider checks `settingsStore.dictationDenoisingEnabled ? microphoneDenoiser : nil`.
- **Alternatives considered**:
  - Passing `dictationDenoisingEnabled` as a parameter in `preprocess(audioURL:)`: Viable, but requires plumbing through `DictationPipeline` and all its callers. A provider closure keeps the pipeline interface clean.

### 3. Settings Persistence Key & Default Value
- **Choice**: Add `dictationDenoisingEnabledKey = "dictation_denoising_enabled"` in `AppSettingsStore`, defaulting to `true`.
- **Rationale**: Open-space and office environments are common; keeping noise suppression enabled by default prevents unexpected background voice leakage for existing users. Users in quiet environments can deliberately toggle it off.

## Risks / Trade-offs

- **[Risk: Filter numerical instability on extreme inputs]** → Biquad coefficients use double-precision floating-point calculation during filter coefficient setup; peak limiter / headroom conditioning ensures samples remain strictly finite within $[-0.95, 0.95]$.
- **[Risk: Performance overhead on dictation completion]** → Direct float-array biquad processing on 16 kHz mono audio requires ~16,000 multiply-adds per second of audio, consuming less than 1 millisecond on M-series chips.
