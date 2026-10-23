## ADDED Requirements

### Requirement: GigaAM effective timing capability is distinct from native timestamp output

VoicePen SHALL allow Meeting timecodes and speaker labeling with GigaAM when its accepted native package provides aligned token positions, while continuing to report that the native backend has no direct segment or word timestamp output. Unsupported GigaAM decoding controls SHALL remain unavailable.

#### Scenario: GigaAM selected with saved Meeting timing preferences

- **WHEN** GigaAM is selected and Meeting timecodes or diarization are enabled
- **THEN** those preferences are effective for new Meeting recognition requests without enabling forced language, decoder prompting, beam search, or VAD

#### Scenario: GigaAM dictation without timing request

- **WHEN** push-to-talk dictation uses GigaAM without a timing request
- **THEN** it returns the same recognized text without additional alignment processing or speaker analysis
