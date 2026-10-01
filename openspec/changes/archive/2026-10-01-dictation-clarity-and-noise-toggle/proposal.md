## Why

Real-world dictations recorded with common hardware (Apple EarPods, MacBook built-in microphones, AirPods Pro) suffer from proximity effect, chest resonance (150–350 Hz), and sub-bass room rumble, making the recorded voice sound muffled and bottom-heavy. Furthermore, while neural noise suppression (RNNoise) is vital in open-space offices to prevent background conversations from leaking into recognition, in quiet rooms RNNoise unnecessarily attenuates high-frequency speech formants and weakens phoneme clarity.

Providing an acoustic "Whisper Optimal" preprocessing stage (80 Hz high-pass filter, gentle 280 Hz de-muffler, and loudness normalization) together with a user-configurable background noise suppression toggle enables users to achieve pristine transcription accuracy in quiet environments while keeping robust noise suppression available for noisy open spaces.

## What Changes

- Add a user-facing toggle in Settings → Audio for dictation background noise suppression (`dictationDenoisingEnabled`, enabled by default).
- When background noise suppression is enabled, RNNoise runs during dictation preprocessing to filter out ambient chatter and open-space noise.
- When background noise suppression is disabled, raw microphone audio bypasses RNNoise, preventing Bark-band over-suppression and preserving natural speech formants in quiet environments.
- Integrate an acoustic "Whisper Optimal" voice clarity shaping filter into the dictation preprocessing pipeline:
  - 80 Hz high-pass filter (12 dB/oct) to strip sub-audible HVAC rumble and desk bumps.
  - Gentle 280 Hz de-muffler (-2.5 dB) to clean chest resonance and boundary reflections.
  - Loudness normalization (target -16 LUFS, peak -1 dBFS) to prevent quiet speech transcription failure and decoder hallucinations.
- Persist the noise suppression setting across app launches with default value `true`.

## Capabilities

### New Capabilities

*(None)*

### Modified Capabilities

- `audio-settings-voice-processing`: Add a configurable setting and persistence for dictation background noise suppression, and require "Whisper Optimal" acoustic shaping (low-cut, de-muffler, and loudness normalization) in the dictation preprocessing pipeline.

## Impact

- **Audio Preprocessing**: `LiveAudioPreprocessingClient` dynamically accepts noise suppression enabling/disabling, and chains acoustic clarity filtering before silence trimming.
- **Settings & Persistence**: `AppSettingsStore` persists `dictationDenoisingEnabled` (default: `true`), exposed via `AppController`.
- **UI**: Settings audio controls expose a toggle with clear explanatory copy for open-space vs. quiet room usage.
- **Dependencies**: Uses native macOS CoreAudio / `AVAudioEngine` / `vDSP` capabilities without external audio dependencies.
