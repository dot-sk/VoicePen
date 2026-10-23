## ADDED Requirements

### Requirement: Nemotron finalizes with silent trailing context

Every Nemotron English transcription SHALL submit all original audio followed by 2.24 seconds of generated silence before final decoding. This SHALL apply to short and long recordings in every workflow using Nemotron, without a real-time wait. Synthetic context SHALL NOT modify source recordings, saved audio, recording duration or reported original input sample count. Other recognizers SHALL remain unchanged. Cancellation SHALL be checked before and after the added inference, and every completed, failed or canceled request SHALL leave the next request with a fresh session.

#### Scenario: Short speech needs final context

- **WHEN** an English word recording that previously decoded to blank is transcribed with Nemotron
- **THEN** the silent tail allows final decoding while all original samples are submitted and original file contents and sample counts remain unchanged

#### Scenario: Input ends at a chunk boundary

- **WHEN** Nemotron receives a recording ending exactly on its native chunk boundary
- **THEN** it still receives the full additional silent context before final decoding

#### Scenario: Silence or longer speech is transcribed

- **WHEN** Nemotron transcribes a silence-only recording or a known longer English recording
- **THEN** finalization keeps the silence result empty and preserves the longer recording's expected speech without repeating a trailing word

#### Scenario: Cancel and retry

- **WHEN** Nemotron transcription is canceled or fails during audio submission or finalization and another request follows
- **THEN** the canceled result is not returned and the subsequent request starts with a reset session and its own silent tail
