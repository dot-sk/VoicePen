## ADDED Requirements

### Requirement: RNNoise output stays within the supported audio range

VoicePen SHALL validate successful RNNoise microphone output before using it for
silence analysis, saved transcription-input audio, Meeting mastering, or local
transcription. When the output exceeds the supported full-scale range, VoicePen
SHALL uniformly attenuate the complete processed signal to leave headroom,
preserve relative sample amplitudes and sample count, and avoid hard clipping.
VoicePen MUST NOT amplify output that is already within the supported range.

#### Scenario: RNNoise output exceeds full scale

- **WHEN** successful RNNoise processing produces one or more finite samples outside the supported full-scale range
- **THEN** VoicePen uniformly attenuates the complete processed signal before downstream use so every sample is finite and within the supported range

#### Scenario: RNNoise output is already within full scale

- **WHEN** successful RNNoise processing produces only finite samples within the supported full-scale range
- **THEN** VoicePen passes the processed signal onward without changing its amplitude

#### Scenario: RNNoise output cannot be safely conditioned

- **WHEN** RNNoise output contains a non-finite sample or cannot be conditioned into the supported range
- **THEN** VoicePen treats noise suppression as failed, logs a diagnostic, and continues through the existing original-microphone fallback

#### Scenario: Meeting microphone noise suppression succeeds

- **WHEN** VoicePen applies RNNoise to a Meeting microphone source
- **THEN** it conditions only the processed microphone signal while leaving Meeting system audio, raw microphone capture, and retained recovery audio unchanged

#### Scenario: VoicePen conditions RNNoise output

- **WHEN** VoicePen accepts or attenuates successful RNNoise output
- **THEN** diagnostics identify the input peak, output peak, and whether attenuation was applied without logging audio content
