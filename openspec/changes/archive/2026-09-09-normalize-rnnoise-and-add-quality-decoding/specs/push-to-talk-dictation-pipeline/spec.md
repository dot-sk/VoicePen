## ADDED Requirements

### Requirement: Dictation uses bounded denoised transcription audio

When RNNoise succeeds for a valid push-to-talk recording, VoicePen SHALL use the
same conditioned, finite, full-scale-bounded signal for silence analysis, the
derived transcription-input file, saved dictation audio, and local
transcription.

#### Scenario: Dictation RNNoise output requires attenuation

- **WHEN** RNNoise succeeds for a valid dictation recording and its output exceeds the supported full-scale range
- **THEN** VoicePen transcribes and, when enabled, saves one derived audio file containing the uniformly attenuated signal

#### Scenario: Dictation RNNoise output is already safe

- **WHEN** RNNoise succeeds for a valid dictation recording and its output is already finite and within the supported full-scale range
- **THEN** VoicePen preserves that signal's amplitude while continuing the existing silence-trimming, saving, and transcription flow

#### Scenario: Dictation RNNoise output is invalid

- **WHEN** RNNoise returns output that cannot be safely conditioned
- **THEN** VoicePen uses the existing original-recording fallback and does not save or transcribe the invalid processed signal
